import fs from "node:fs";
function load(f){ const m=new Map(); for(const l of fs.readFileSync(f,"utf8").trim().split("\n")){ const [r,v]=l.split("\t"); m.set(r,v);} return m; }
const d=load("dommy-results.txt"), h=load("happydom-results.txt"), j=load("jsdom-results.txt");
const green = v => /^\d+\/\d+$/.test(v||"") && (()=>{const[p,t]=v.split("/").map(Number);return p===t&&t>0;})();
const jsdomBeatsDommy=[], happyBeatsDommy=[];
for(const [rel,dv] of d){
  if(!green(dv) && green(j.get(rel))) jsdomBeatsDommy.push(`${rel}  (dommy ${dv} | jsdom ${j.get(rel)})`);
  if(!green(dv) && green(h.get(rel))) happyBeatsDommy.push(`${rel}  (dommy ${dv} | happy ${h.get(rel)})`);
}
console.log(`=== Files jsdom green but Dommy NOT (${jsdomBeatsDommy.length}) — Dommy's real gaps vs jsdom ===`);
jsdomBeatsDommy.forEach(x=>console.log("  "+x));
console.log(`\n=== Files happy-dom green but Dommy NOT (${happyBeatsDommy.length}) ===`);
happyBeatsDommy.forEach(x=>console.log("  "+x));
