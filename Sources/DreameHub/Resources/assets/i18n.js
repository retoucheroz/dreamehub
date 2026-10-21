/* UI translation. Dictionaries are keyed by the original Turkish text, so Turkish needs none.
   Static markup, toasts, dialogs and backend messages are translated as they enter the DOM;
   canvas labels and composed sentences call t()/tf() directly. */
(function(){
  const SUPPORTED=['tr','en','it','sv'],LOCALES={tr:'tr-TR',en:'en-GB',it:'it-IT',sv:'sv-SE'};
  // Templates whose placeholder may hold any text (it is translated in turn); all others match numbers only.
  const FREE_TEMPLATES=new Set(['Harita verisi geçersiz: {0}','Son cihaz verisi gösteriliyor: {0}','Harita güncellenemedi. {0}']);
  const ATTRIBUTES=['title','aria-label','placeholder','alt'];
  const dictionaries={},cache=new Map();
  let templates=null;
  const stored=key=>{try{return localStorage.getItem(key)}catch(_e){return null}};
  const saved=window.dreameSavedLanguage??stored('dreame-language');
  const choice=SUPPORTED.includes(saved)?saved:'auto';
  let lang=choice,locale=LOCALES[choice];
  if(choice==='auto'){
    const preferred=[...(window.dreameSystemLanguages||[]),...(navigator.languages||[navigator.language||''])].map(String);
    const tag=preferred.find(tag=>SUPPORTED.includes(tag.slice(0,2).toLowerCase()));
    lang=tag?tag.slice(0,2).toLowerCase():'en';locale=tag||LOCALES[lang];
  }
  document.documentElement.lang=lang;

  function compileTemplates(){
    templates=[];
    for(const [key,value] of Object.entries(dictionaries[lang]||{})){
      if(!/\{\d\}/.test(key))continue;
      const order=[],source=key.replace(/[.*+?^$()|[\]\\]/g,'\\$&').replace(/\{(\d)\}/g,(_,i)=>{order.push(Number(i));return '(.+?)'});
      templates.push({key,value,order,pattern:new RegExp('^'+source+'$')});
    }
  }
  function fromTemplate(text){
    if(!templates)compileTemplates();
    for(const template of templates){
      const match=template.pattern.exec(text);if(!match)continue;
      const args=[];template.order.forEach((index,i)=>{args[index]=match[i+1]});
      if(!FREE_TEMPLATES.has(template.key)&&!args.every(arg=>/^[-+\d.,:%\s]+$/.test(arg)))continue;
      return template.value.replace(/\{(\d)\}/g,(_,i)=>FREE_TEMPLATES.has(template.key)?t(args[i]):args[i]);
    }
    return null;
  }
  function t(text){
    if(lang==='tr'||typeof text!=='string'||!text.trim())return text;
    if(cache.has(text))return cache.get(text);
    const dictionary=dictionaries[lang]||{},core=text.trim();
    let result=dictionary[core]??fromTemplate(core);
    result=result===null?text:text.slice(0,text.indexOf(core))+result+text.slice(text.indexOf(core)+core.length);
    if(cache.size>4000)cache.clear();
    cache.set(text,result);return result;
  }
  function tf(key,...args){
    const template=lang==='tr'?key:(dictionaries[lang]||{})[key]??key;
    return template.replace(/\{(\d)\}/g,(_,i)=>String(args[i]??''));
  }

  const skipped=element=>!element||!!element.closest('script,style,[translate="no"]');
  function translateText(node){const value=node.nodeValue,next=t(value);if(next!==value)node.nodeValue=next}
  function translateAttributes(element){for(const name of ATTRIBUTES){const value=element.getAttribute(name);if(value){const next=t(value);if(next!==value)element.setAttribute(name,next)}}}
  function translateTree(root){
    if(root.nodeType===3){if(!skipped(root.parentElement))translateText(root);return}
    if(root.nodeType!==1||skipped(root))return;
    translateAttributes(root);
    const walker=document.createTreeWalker(root,NodeFilter.SHOW_ELEMENT|NodeFilter.SHOW_TEXT,{acceptNode:node=>node.nodeType===1&&node.matches('script,style,[translate="no"]')?NodeFilter.FILTER_REJECT:NodeFilter.FILTER_ACCEPT});
    for(let node=walker.nextNode();node;node=walker.nextNode())node.nodeType===3?translateText(node):translateAttributes(node);
  }
  if(lang!=='tr'){
    new MutationObserver(records=>{for(const record of records){
      if(record.type==='characterData'){if(!skipped(record.target.parentElement))translateText(record.target)}
      else if(record.type==='attributes'){if(!skipped(record.target))translateAttributes(record.target)}
      else for(const node of record.addedNodes)translateTree(node);
    }}).observe(document.documentElement,{subtree:true,childList:true,characterData:true,attributes:true,attributeFilter:ATTRIBUTES});
  }

  function setLanguage(code){
    if(code!=='auto'&&!SUPPORTED.includes(code))return;
    try{localStorage.setItem('dreame-language',code)}catch(_e){}
    // The native host saves the choice for its own menus and reloads once the page preference is in place.
    const native=window.webkit?.messageHandlers?.dreameNative;
    if(native)native.postMessage({action:'language',language:code});else location.reload();
  }
  window.DreameI18n={SUPPORTED,choice,lang,locale,t,tf,setLanguage,add(code,dictionary){dictionaries[code]=dictionary;cache.clear();templates=null}};
})();
