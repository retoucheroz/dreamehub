/* Run the actual shipped refresh function against deferred, offline API responses. */
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const html = fs.readFileSync(path.resolve(__dirname, '../../Sources/DreameHub/Resources/index.html'), 'utf8');
const start = html.indexOf('let mapRequestGeneration=');
const end = html.indexOf('\nlet savedLoginAttempted=', start);
assert(start >= 0 && end > start, 'Actual loadMap source found');
const stop = html.match(/^function stopMapLive\([^\n]+/m)[0];
const i18n = html.match(/^const LANG=[^\n]+/m)[0] + '\n' + html.match(/^function t\([^\n]+/m)[0];
const refresh = html.slice(start, end);
const {create:createMotion}=require('../../Sources/DreameHub/Resources/assets/robot-motion.js');

function harness() {
  const elements = new Map(), calls = [], drawn = [], samples = [], scheduled = [];
  let frozen = 0, resets = 0, animations = 0;
  const $ = id => {
    if (!elements.has(id)) elements.set(id, {value:id==='historySelect'?'current':'',hidden:true,textContent:''});
    return elements.get(id);
  };
  const s = {
    $, window:{}, activeTab:'map', document:{visibilityState:'visible'}, mapFetchBusy:false,
    mapLiveTimer:null, mapFrameTimer:null, mapTarget:null, navigationActive:false, navigationArrivalHits:0,
    lastMap:null, lastMapFrameId:null, lastMapTimestamp:null, lastMapPoseKey:'',
    robotMotion:{freeze(){frozen++},reset(){resets++}},
    performance:{now:()=>100}, clearTimeout(){},cancelAnimationFrame(){},
    api(url){return new Promise((resolve,reject)=>calls.push({url,resolve,reject}));},
    announceMapAlerts(){},mapChanges(){return []},sampleRobotPose(map){samples.push(map);return true;},
    drawMap(map){drawn.push(map);s.lastMap=map;$('mapMessage').hidden=true;},ensureMapAnimation(){animations++},
    scheduleMapLive(delay){scheduled.push(delay)},targetDistance(){return null},showToast(){},
  };
  vm.createContext(s);vm.runInContext(i18n+'\n'+stop+'\n'+refresh,s);
  return {s,$,calls,drawn,samples,scheduled,get frozen(){return frozen},get resets(){return resets},
    get animations(){return animations},stop(){s.stopMapLive()}};
}
const map=(frame)=>({map_id:7,frame_id:frame,timestamp_ms:1700000000000+frame*1000,robot_position:[frame,0,10]});
const flush=async()=>{await Promise.resolve();await Promise.resolve();await Promise.resolve();};

async function testDelayedLiveResponseCannotReplaceSelectedHistory() {
  const h=harness(), first=h.s.loadMap();
  h.$('historySelect').value='1';h.stop();
  await h.s.loadMap();
  assert.equal(h.calls.length,1,'Selection reload queues instead of overlapping requests');
  h.calls[0].resolve({map:map(1)});await first;await flush();
  assert.equal(h.drawn.length,0,'Discard delayed live response after history selection');
  assert.equal(h.calls[1].url,'/api/cleaning/history/1/map');
  h.calls[1].resolve({map:map(2)});await flush();
  assert.equal(h.drawn.length,1);assert.equal(h.drawn[0].frame_id,2);
  assert.equal(h.samples[0].history_map,true);assert.equal(h.resets,1);
  assert.equal(h.scheduled.length,0,'Archived maps must not start live polling');
}
async function testDelayedHistoryResponseCannotReplaceLive() {
  const h=harness();h.$('historySelect').value='3';const first=h.s.loadMap();
  h.$('historySelect').value='current';h.stop();await h.s.loadMap();
  h.calls[0].resolve({map:map(30)});await first;await flush();
  assert.equal(h.drawn.length,0);assert.equal(h.calls[1].url,'/api/map/current');
  h.calls[1].resolve({map:map(2)});await flush();
  assert.equal(h.drawn[0].frame_id,2);assert.equal(h.samples[0].history_map,false);
  assert.equal(h.scheduled.length,1);
}
async function testRepeatedReloadCoalescesAndContinuesPolling() {
  const h=harness(), first=h.s.loadMap();
  await h.s.loadMap();await h.s.loadMap();await h.s.loadMap();
  assert.equal(h.calls.length,1);
  h.calls[0].resolve({map:map(1)});await first;await flush();
  assert.equal(h.calls.length,2,'Three pending requests coalesce to one reload');
  h.calls[1].resolve({map:map(2)});await flush();
  assert.equal(h.drawn.length,2);assert.equal(h.scheduled.length,1);
}
async function testHiddenOrOtherTabRejectsInflightResponse() {
  for(const reason of ['hidden','tab']) {
    const h=harness(), first=h.s.loadMap();await h.s.loadMap();
    if(reason==='hidden')h.s.document.visibilityState='hidden';else h.s.activeTab='overview';
    h.stop();h.calls[0].resolve({map:map(1)});await first;await flush();
    assert.equal(h.drawn.length,0,reason);assert.equal(h.calls.length,1,reason);
    assert.equal(h.scheduled.length,0,reason);assert.equal(h.frozen,1,reason);
  }
}
async function testErrorFreezesAndRetainsLastValidMap() {
  const h=harness(), prior=map(1);h.s.lastMap=prior;
  const pending=h.s.loadMap();h.calls[0].reject(new Error('offline'));await pending;
  assert.equal(h.frozen,1);assert.equal(h.s.lastMap,prior);assert.equal(h.drawn[0],prior);
  assert.equal(h.$('mapMessage').hidden,false);assert.match(h.$('mapMessage').textContent,/offline/);
  assert.equal(h.scheduled.length,1,'A read failure must not permanently stop polling');
}
async function testStaleErrorDoesNotOverrideNewSelection() {
  const h=harness(), first=h.s.loadMap();h.$('historySelect').value='1';h.stop();await h.s.loadMap();
  h.calls[0].reject(new Error('old failure'));await first;await flush();
  assert.doesNotMatch(h.$('mapMessage').textContent,/old failure/);
  assert.equal(h.calls.length,2);assert.equal(h.frozen,1,'Only selection stop, no stale failure freeze');
  h.calls[1].resolve({map:map(1)});await flush();
}
async function testOldLivePacketCannotRewindMap() {
  for(const frame of [1,2+32768]) {
    const h=harness(),prior=map(2);h.s.lastMap=prior;
    const incoming=map(frame);if(frame>100)incoming.timestamp_ms=prior.timestamp_ms;
    const pending=h.s.loadMap();h.calls[0].resolve({map:incoming});await pending;
    assert.equal(h.s.lastMap,prior);assert.equal(h.samples.length,0);assert.equal(h.drawn.length,1);
    assert.equal(h.drawn[0],prior);assert.equal(h.$('mapMessage').hidden,true,'Retained map clears manual loading overlay');
    assert.equal(h.scheduled.length,1,'Ignored old packet must not stop polling');
  }
}
async function testDisplayedHistoryDoesNotBlockCurrentMap() {
  const h=harness();h.$('historySelect').value='1';
  const history=h.s.loadMap();h.calls[0].resolve({map:{...map(30),history_map:true}});await history;
  h.$('historySelect').value='current';h.stop();
  const live=h.s.loadMap();h.calls[1].resolve({map:map(2)});await live;
  assert.equal(h.s.lastMap.frame_id,2,'Current acquisition is a different source, not an older history poll');
  assert.equal(h.samples.at(-1).history_map,false);
}
async function testMotionRejectsConflictingDuplicateAndHalfWrap() {
  const motion=createMotion(),first=map(2),wall=first.timestamp_ms;
  motion.sample(first,0,wall);
  motion.sample({...first,robot_position:[900,900,180]},100,wall);
  assert.deepEqual(motion.pose(100),first.robot_position,'Conflicting duplicate identity cannot teleport pose');
  motion.sample({...first,frame_id:first.frame_id+32768,robot_position:[800,800,170]},200,wall);
  assert.deepEqual(motion.pose(200),first.robot_position,'Half-wrap ordering is ambiguous, not a fresh observation');
}
async function testCachedFrameKeepsGeometryButUpdatesWarningAndAge() {
  const h=harness(),prior=map(2);h.s.lastMap=prior;
  const pending=h.s.loadMap();
  h.calls[0].resolve({map:{...prior,robot_position:[999,999,80],telemetry:{freshness_ms:9000},update_warning:'offline'}});
  await pending;
  assert.equal(h.s.lastMap.robot_position,prior.robot_position);
  assert.equal(h.s.lastMap.telemetry.freshness_ms,9000);assert.equal(h.s.lastMap.update_warning,'offline');
  assert.equal(h.frozen,1,'Cached degraded response freezes motion');
}
(async()=>{
  for(const test of [testDelayedLiveResponseCannotReplaceSelectedHistory,testDelayedHistoryResponseCannotReplaceLive,
    testRepeatedReloadCoalescesAndContinuesPolling,testHiddenOrOtherTabRejectsInflightResponse,
    testErrorFreezesAndRetainsLastValidMap,testStaleErrorDoesNotOverrideNewSelection,
    testOldLivePacketCannotRewindMap,testDisplayedHistoryDoesNotBlockCurrentMap,
    testMotionRejectsConflictingDuplicateAndHalfWrap,testCachedFrameKeepsGeometryButUpdatesWarningAndAge]) await test();
  console.log('PASS: shipped loadMap delayed live/history responses, queued reload coalescing, hidden/tab cancellation, failure freeze/cache and retry');
})().catch(error=>{console.error(error);process.exitCode=1;});
