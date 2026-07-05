import { buildPage } from "./harness.mjs";
const [engine, rel] = process.argv.slice(2);
let out = "NO-RESULTS";
try {
  const html = buildPage(rel);
  if (engine === "happydom") {
    const { Window } = await import("happy-dom");
    const win = new Window({ url: "http://localhost/"+rel, settings: { enableJavaScriptEvaluation: true, timer:{maxTimeout:200,maxIntervalTime:10,maxIntervalIterations:2,preventTimerLoops:true}, disableErrorCapturing:true } });
    win.document.write(html);
    await Promise.race([ win.happyDOM.waitUntilComplete().catch(()=>{}), new Promise(r=>setTimeout(r,3500)) ]);
    for (let i=0;i<8 && !win.__wptResults;i++) await new Promise(r=>setTimeout(r,25));
    const res = win.__wptResults;
    if (Array.isArray(res)) out = `${res.filter(r=>r.status===0).length}/${res.length}`;
  } else {
    const { JSDOM, VirtualConsole } = await import("jsdom");
    const dom = new JSDOM(html, { url: "http://localhost/"+rel, runScripts:"dangerously", virtualConsole:new VirtualConsole(), pretendToBeVisual:true });
    const deadline = Date.now()+3500;
    while (Date.now()<deadline && !dom.window.__wptResults) await new Promise(r=>setTimeout(r,25));
    const res = dom.window.__wptResults;
    if (Array.isArray(res)) out = `${res.filter(r=>r.status===0).length}/${res.length}`;
    dom.window.close();
  }
} catch(e) { out = "ERR:" + String(e.message||e).slice(0,40); }
process.stdout.write(rel + "\t" + out + "\n");
process.exit(0);
