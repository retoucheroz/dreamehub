/* Executes the shipped Canvas renderer, not a reimplementation of its geometry. */
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const html = fs.readFileSync(path.resolve(__dirname, '../../Sources/DreameHub/Resources/index.html'), 'utf8');
const js = html.match(/<script>([\s\S]*?)<\/script>/)[1];
const functionLine = name => {
  const match = js.match(new RegExp('^function ' + name + '\\([^\\n]*$', 'm'));
  assert(match, name + ' exists');
  return match[0];
};
const draw = js.slice(js.indexOf('function drawMap(m){'), js.indexOf('\nasync function loadHistory'));
const helpers = ['mapPoint', 'mapCellY', 'getRobotPose', 'targetDistance', 'mapCellSnapshot'].map(functionLine).join('\n');
// The shipped translation layer (Turkish source text, no table loaded) so labels stay the Turkish keys.
const i18n = js.match(/^const LANG=[^\n]*$/m)[0] + '\n' + functionLine('t');

function render(rawAngle, mode = '2d', width = 720, height = 500) {
  const strokes = [], labels = [], coordinates = [];
  let line = [];
  const context = new Proxy({
    beginPath() { line = []; },
    moveTo(x, y) { line.push([x, y]); coordinates.push([x, y]); },
    lineTo(x, y) { line.push([x, y]); coordinates.push([x, y]); },
    stroke() { strokes.push({ width: this.lineWidth, points: line.slice() }); },
    fillText(text, x, y) { labels.push({ text, x, y }); },
    createRadialGradient() { return { addColorStop() {} }; }
  }, { get(object, key) { return key in object ? object[key] : () => {}; } });
  const elements = new Map();
  const element = id => {
    if (!elements.has(id)) elements.set(id, {
      textContent: '', hidden: false, value: id === 'historySelect' ? 'current' : '',
      classList: { toggle() {} }, getContext() { return context; },
      clientWidth: width, clientHeight: height,
      getBoundingClientRect() { return { left: 0, top: 0, bottom: height, width, height }; }
    });
    return elements.get(id);
  };
  const state = {
    mode, angle: mode === '2d' ? 0 : Math.PI / 4, tilt: mode === '2d' ? 1 : .56,
    zoom: 1, wallHeight: 1, walls: true, route: false, points: true, wireframe: false,
    panX: 0, panY: 0, detections: []
  };
  const sandbox = {
    $: element, window: { devicePixelRatio: 1 },
    document: { querySelector() { return null; } },
    mapView: state, lastMap: null, mapTarget: null, navigationActive: false,
    performance: { now() { return 123456; } }, OBSTACLE_LABELS: {},
    robotMotion: require('../../Sources/DreameHub/Resources/assets/robot-motion.js').create(),
    Math, Number, Map, Date, console
  };
  vm.createContext(sandbox);
  vm.runInContext(i18n + '\n' + helpers + '\n' + draw, sandbox);
  const fixture = {
    size: [0, 0, 3000, 3000, 60, 60, 50], data: { 1: [0, 0, 60, 0, 59, 60] },
    robot_position: [1500, 1500, rawAngle], charger_position: [1000, 1000, rawAngle],
    obstacles: [], laser_obstacles: [], cliffs: [], segments: [], path: [],
    telemetry: { metrics: { occupancy_cells: 120 } }, timestamp_ms: Date.now()
  };
  const before = JSON.stringify(fixture);
  sandbox.drawMap(fixture);
  assert.equal(JSON.stringify(fixture), before, 'Rendering must not rotate or mutate device coordinates');
  assert(coordinates.every(pair => pair.every(Number.isFinite)), 'Canvas coordinates finite');
  assert.equal(sandbox.getRobotPose(), fixture.robot_position, 'Latest exact device pose returned');
  // Old samples do not fabricate a new coordinate or heading after time has elapsed.
  sandbox.robotMotion.reset();
  assert.equal(sandbox.getRobotPose(1e10), fixture.robot_position, 'No stale-pose extrapolation');
  return { strokes, labels, projection: state.projection, fixture, coordinates };
}

const east = render(0), south = render(90);
function nose(result) {
  const segment = result.strokes.find(s => s.width === 2.4 && s.points.length === 2);
  assert(segment, 'Actual robot heading stroke exists');
  return [segment.points[1][0] - segment.points[0][0], segment.points[1][1] - segment.points[0][1]];
}
const zero = nose(east), ninety = nose(south);
assert(zero[0] > 0 && Math.abs(zero[1]) < 1e-6, 'Robot angle 0 points right, +90 clockwise from old up-facing render');
assert(ninety[1] > 0 && Math.abs(ninety[0]) < 1e-6, 'Robot angle 90 points down on the canvas');
function dockLabelRelative(result) {
  const label = result.labels.find(x => x.text === 'İstasyon');
  assert(label, 'Actual dock label exists');
  const v = result.projection, q = [20, 39];
  return [(label.x - 8 - v.ox) / v.scale - q[0], (label.y - v.oy) / v.scale - q[1]];
}
const dockZero = dockLabelRelative(east), dockNinety = dockLabelRelative(south);
assert(Math.abs(dockZero[0] + 3.6) < 1e-6, 'Dock angle 0 tower runs left from bay');
assert(Math.abs(dockNinety[0]) < 1e-6, 'Dock angle 90 tower center remains aligned');
assert(Math.abs((dockNinety[1] - dockZero[1]) + 3.6) < 1e-6, 'Dock rotates +90 clockwise with robot');
for (const mode of ['2d', '3d', 'clay', 'pov']) {
  for (const size of [[720, 500], [360, 420], [1000, 700]]) render(35, mode, ...size);
}
for (const forbidden of ['simulationButton', 'mapView.simulation', 'halfFov', 'ROBOT_EXTRAPOLATION_LIMIT_MS', 'openPlans']) {
  assert(!html.includes(forbidden), 'Forbidden simulated/removed feature: ' + forbidden);
}
assert(!draw.includes('a=((Number(m.charger_position[2])||0)-90)'), 'Dock viewport-fit angle must match rotated dock geometry');
console.log('PASS: shipped renderer +90° robot/dock orientation; unchanged map coordinates; exact pose/no extrapolation; 4 view modes × 3 sizes; no simulated cone/routine code');
