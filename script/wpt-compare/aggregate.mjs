import fs from "node:fs";
function load(f){ const m=new Map(); for(const line of fs.readFileSync(f,"utf8").trim().split("\n")){ const [rel,val]=line.split("\t"); m.set(rel,val); } return m; }
const dommy=load("dommy-results.txt"), happy=load("happydom-results.txt"), jsd=load("jsdom-results.txt");
const dir = r => r.split("/")[0];
function parse(v){ if(!v||!/^\d+\/\d+$/.test(v)) return null; const [p,t]=v.split("/").map(Number); return {p,t}; }
// Per-engine: files-with-results, fully-green, and per-dir subtest sums (over files the engine ran)
const engines = { dommy, happydom:happy, jsdom:jsd };
const dirs = [...new Set([...dommy.keys()].map(dir))].sort();
console.log("=== Files each engine ran to completion (got a results array) / total 245 ===");
for(const [name,m] of Object.entries(engines)){
  let ran=0, green=0;
  for(const [rel,v] of m){ const pr=parse(v); if(pr){ ran++; if(pr.p===pr.t && pr.t>0) green++; } }
  console.log(`  ${name.padEnd(9)} ran ${String(ran).padStart(3)}/245   fully-green ${green}`);
}
console.log("\n=== happy-dom couldn't-run breakdown ===");
const cnt={};
for(const [rel,v] of happy){ if(!parse(v)){ const k=v.startsWith("ERR")?"ERR":v; cnt[k]=(cnt[k]||0)+1; } }
console.log("  "+JSON.stringify(cnt));
console.log("\n=== Per-directory: files fully green (green/total-files) ===");
console.log("  dir".padEnd(14)+"dommy    happydom  jsdom");
for(const d of dirs){
  const files=[...dommy.keys()].filter(r=>dir(r)===d);
  const g = m => files.filter(r=>{const pr=parse(m.get(r)); return pr&&pr.p===pr.t&&pr.t>0;}).length;
  console.log("  "+d.padEnd(12)+`${g(dommy)}/${files.length}`.padEnd(9)+`${g(happy)}/${files.length}`.padEnd(10)+`${g(jsd)}/${files.length}`);
}
