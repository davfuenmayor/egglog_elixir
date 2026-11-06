const {chromium} = require("playwright");
const {execFileSync} = require("child_process");
const fs = require("fs"), path = require("path"), http = require("http");
// Dev-only: npm install playwright outside the wrapper, then set NODE_PATH.
// Pass the installed Kino lib/assets/mermaid/build directory and captured corpus.
const [assetsArg, corpusArg] = process.argv.slice(2);
if (!assetsArg || !corpusArg) {
  console.error("Usage: node scripts/check_mermaid_browser.cjs KINO_ASSETS CORPUS_DIR");
  process.exit(1);
}
const assets = path.resolve(assetsArg), corpus = path.resolve(corpusArg);
async function verifyParity(page, source, base) {
  const native=JSON.parse(fs.readFileSync(base+".json","utf8"));
  const decode=value=>JSON.parse(Buffer.from(value,"base64url").toString());
  const names=Object.fromEntries([...source.matchAll(/^    %% node (n\d+) (\S+)$/gm)].map(m=>[m[1],decode(m[2])]));
  const classes=Object.fromEntries([...source.matchAll(/^  %% class (c\d+) (\S+)$/gm)].map(m=>[m[1],decode(m[2])]));
  const equal=(a,b,what)=>{
    const canon=items=>items.map(x=>JSON.stringify(x)).sort(),aa=canon(a),bb=canon(b);
    if(JSON.stringify(aa)!==JSON.stringify(bb))
      throw new Error(path.basename(base)+": "+what+" mismatch: "+JSON.stringify({a:aa.slice(0,5),b:bb.slice(0,5),counts:[a.length,b.length]}));
  };
  const dot=JSON.parse(execFileSync("dot",["-Tjson",base+".dot"],{encoding:"utf8",stdio:["ignore","pipe","pipe"]}));
  const objects=Object.fromEntries((dot.objects||[]).map(obj=>[obj._gvid,obj]));
  const expectedEdges=Object.entries(native.nodes).flatMap(([id,n])=>n.children.map((child,i)=>[id,i,child]));
  const savedEdges=[...source.matchAll(/^  %% edge (n\d+) (\d+) (n\d+)$/gm)].map(m=>[names[m[1]],Number(m[2]),names[m[3]]]);
  equal(savedEdges,expectedEdges,"retained native child references");
  equal((dot.edges||[]).map(e=>[objects[e.tail].name,parseInt(e.tailport),objects[e.head].name]),expectedEdges,"DOT tail ports and child references");
  const expectedVisual=expectedEdges.map(([from,i,to])=>[from,i,native.nodes[from].eclass===native.nodes[to].eclass?"node:"+to:"class:"+native.nodes[to].eclass]);
  const targetKey=id=>classes[id]?"class:"+classes[id].id:"node:"+names[id];
  const drawn=[...source.matchAll(/^  (n\d+) -->(?:\|(\d+)\|)? ([nc]\d+)$/gm)].map(([,from,i,to])=>{
    if(i===undefined && native.nodes[names[from]].children.length!==1)throw new Error("Missing multi-argument position");
    return [names[from],Number(i??0),targetKey(to)];
  });
  equal(drawn,expectedVisual,"visible DOT lhead targets and argument order");
  equal((dot.objects||[]).filter(o=>o.name.startsWith("cluster_")).flatMap(o=>(o.nodes||[]).map(id=>[objects[id].name,o.name.slice(8)])),Object.entries(native.nodes).map(([id,n])=>[id,n.eclass]),"class membership");
  const actual=await page.evaluate(()=>{
    const nodeId=el=>el.id.match(/flowchart-(n\d+)-/)[1];
    const text=el=>{
      if(!el)return "";
      el=el.querySelector("span.nodeLabel,span.edgeLabel")||el;
      return (el.innerText??el.textContent??"").replace(/\u00a0/g," ").trim();
    };
    const nodes=[...document.querySelectorAll("#root svg g.node")];
    const classData=[...document.querySelectorAll("#root svg g.cluster")].map(el=>({id:el.id.match(/-(c\d+)$/)[1],label:text(el.querySelector(".cluster-label")),fill:getComputedStyle(el.querySelector("rect")).fill,bounds:el.querySelector("rect").getBoundingClientRect().toJSON()}));
    const edges=[...document.querySelectorAll("#root svg .flowchart-link")].map(el=>{
      const length=el.getTotalLength(),end=el.getPointAtLength(length),before=el.getPointAtLength(Math.max(0,length-.1));
      const markerId=el.getAttribute("marker-end")?.match(/#([^)]*)\)/)?.[1];
      const marker=markerId&&document.getElementById(markerId);
      let offset=0;
      if(marker){
        const box=marker.querySelector("path").getBBox();
        const units=marker.getAttribute("markerUnits")||"strokeWidth";
        offset=(box.x+box.width-marker.refX.baseVal.value)*(marker.markerWidth.baseVal.value/marker.viewBox.baseVal.width)*(units==="strokeWidth"?parseFloat(getComputedStyle(el).strokeWidth):1);
      }
      const dx=end.x-before.x,dy=end.y-before.y,norm=Math.hypot(dx,dy)||1;
      const tip=new DOMPoint(end.x+dx/norm*offset,end.y+dy/norm*offset).matrixTransform(el.getScreenCTM());
      return {id:el.getAttribute("data-id"),tip:{x:tip.x,y:tip.y},marked:!!marker};
    });
    return {nodes:nodes.map(el=>({id:nodeId(el),label:text(el.querySelector(".nodeLabel")),bounds:el.getBoundingClientRect().toJSON()})),classes:classData,edges,
      labels:[...document.querySelectorAll("#root svg g.edgeLabel")].map(el=>({id:el.querySelector("[data-id]")?.getAttribute("data-id"),label:text(el.querySelector(".edgeLabel"))})).filter(x=>x.label)};
  });
  const graphvizText=s=>s.replace(/\\\\/g,"\\");
  equal(actual.nodes.map(n=>[names[n.id],n.label]),Object.entries(native.nodes).map(([id,n])=>[id,graphvizText(n.op)]),"visible constructor labels");
  const expectedLabels=Object.entries(classes).map(([id,{data}])=>[id,Object.entries(data).filter(([k,v])=>k!=="type"&&v!==null).sort().map(([k,v])=>k+" "+v).join("\n")]);
  equal(actual.classes.map(c=>[c.id,c.label]),expectedLabels,"visible class labels");
  const parseEdge=id=>{const m=id.match(/^L_(n\d+)_([nc]\d+)_\d+$/);if(!m)throw new Error("Unknown edge ID: "+id);return [m[1],m[2]]};
  equal(actual.edges.map(e=>{const [from,to]=parseEdge(e.id);return [names[from],targetKey(to)]}),expectedVisual.map(([s,_,t])=>[s,t]),"rendered edge destinations");
  const multi=expectedVisual.filter(([from])=>native.nodes[from].children.length>1);
  equal(actual.labels.map(({id,label})=>{const [from,to]=parseEdge(id);return [names[from],Number(label),targetKey(to)]}),multi,"rendered multi-argument labels");
  const reports=[];
  for(const edge of actual.edges){
    if(!edge.marked)throw new Error("Missing arrowhead");
    const [,to]=parseEdge(edge.id),key=targetKey(to);
    const bounds=key.startsWith("class:")?actual.classes.find(c=>classes[c.id].id===key.slice(6)).bounds:actual.nodes.find(n=>names[n.id]===key.slice(5)).bounds;
    const p=edge.tip,b=bounds;
    const distance=Math.min(Math.abs(p.x-b.x),Math.abs(p.x-b.right),Math.abs(p.y-b.y),Math.abs(p.y-b.bottom));
    if(distance>3 || p.x<b.x-3||p.x>b.right+3||p.y<b.y-3||p.y>b.bottom+3)
      throw new Error("Arrowhead misses DOT target boundary: "+JSON.stringify({edge,key,bounds,distance}));
    reports.push({edge:edge.id,target:key,boundaryDistance:distance});
  }
  const rgb=hex=>"rgb("+hex.slice(1).match(/../g).map(x=>parseInt(x,16)).join(", ")+")";
  for(const c of actual.classes){
    const nc=(dot.objects||[]).find(o=>o.name==="cluster_"+classes[c.id].id);
    if(c.fill!==rgb(nc._draw_.find(cmd=>cmd.op==="C").color))throw new Error("Class color mismatch");
    const members=actual.nodes.filter(n=>native.nodes[names[n.id]].eclass===classes[c.id].id);
    for(const n of members){const a=n.bounds,b=c.bounds;if(a.x<b.x-1||a.y<b.y-1||a.right>b.right+1||a.bottom>b.bottom+1)throw new Error("Member outside class");}
  }
  fs.writeFileSync(base+".render-report.txt",JSON.stringify({edges:reports,classes:actual.classes,nodes:actual.nodes},null,2));
  const svg=execFileSync("dot",["-Tsvg",base+".dot"],{encoding:"utf8",stdio:["ignore","pipe","pipe"]});
  fs.writeFileSync(base+".graphviz.svg",svg);
  await page.evaluate(svg=>{const div=document.createElement("div");div.id="native-dot";div.innerHTML=svg;document.body.append(div);},svg);
  const nativeLabels=await page.evaluate(()=>[...document.querySelectorAll("#native-dot g.node")].map(el=>[el.querySelector("title").textContent,[...el.querySelectorAll("text")].map(t=>t.textContent).join("\n")]));
  equal(nativeLabels,Object.entries(native.nodes).map(([id,n])=>[id,graphvizText(n.op)]),"Graphviz labels");
  const nativeClassLabels=await page.evaluate(()=>[...document.querySelectorAll("#native-dot g.cluster")].filter(el=>el.querySelector("title")?.textContent.startsWith("cluster_")).map(el=>[el.querySelector("title").textContent.slice(8),[...el.querySelectorAll("text")].map(t=>t.textContent).join(" ").replace(/\s+/g," ").trim()]));
  equal(nativeClassLabels,expectedLabels.map(([id,label])=>[classes[id].id,graphvizText(label).replace(/\s+/g," ").trim()]),"Graphviz class labels");
  if(process.env.EGGLOG_MERMAID_SCREENSHOTS){
    const destination=path.resolve(process.env.EGGLOG_MERMAID_SCREENSHOTS);
    await page.evaluate(()=>{
      const native=document.querySelector("#native-dot"),mermaid=document.querySelector("#root");document.body.innerHTML="";
      document.body.style.cssText="margin:0;background:white;font:14px Arial;width:max-content";
      const header=document.createElement("h2");header.textContent="Graphviz and Mermaid — the same native snapshot";document.body.append(header);
      const grid=document.createElement("div");grid.id="comparison";grid.style.cssText="display:flex;gap:24px;align-items:flex-start;padding:12px;width:max-content";document.body.append(grid);
      for(const [label,view] of [["Graphviz",native],["Mermaid",mermaid]]){
        const section=document.createElement("section"),heading=document.createElement("h3");heading.textContent=label;section.append(heading,view);grid.append(section);
        const svg=view.querySelector("svg");svg.style.maxWidth="none";svg.style.width=svg.viewBox.baseVal.width+"px";svg.style.height=svg.viewBox.baseVal.height+"px";
      }
    });
    const box=await page.locator("#comparison").boundingBox();await page.setViewportSize({width:Math.max(1100,Math.ceil(box.width+24)),height:900});
    const content=await page.locator("#comparison").boundingBox();
    await page.screenshot({path:path.join(destination,path.basename(base)+".comparison.png"),clip:{x:0,y:0,width:Math.max(800,Math.ceil(content.width+12)),height:Math.ceil(content.y+content.height+12)}});
  }
  await page.locator("#native-dot").evaluate(el=>el.remove());
  return "DOT class-boundary arrowheads, labels, and grouping verified";
}

const server = http.createServer((req,res)=>{
  const pathname = decodeURIComponent(new URL(req.url,"http://localhost").pathname);
  if(pathname==="/") {
    res.setHeader("Content-Type","text/html");
    return res.end('<html><head><link rel="stylesheet" href="/main.css"></head><body><div id="root"></div><script type="module">import {init} from "/main.js"; window.kinoInit=init;</script></body></html>');
  }
  const file=path.resolve(assets,"."+pathname);
  if(!file.startsWith(assets+path.sep)||!fs.existsSync(file)){res.statusCode=404;return res.end();}
  res.setHeader("Content-Type",file.endsWith(".js")?"text/javascript":file.endsWith(".css")?"text/css":"application/octet-stream");
  fs.createReadStream(file).pipe(res);
});
(async()=>{
  await new Promise(resolve=>server.listen(0,"127.0.0.1",resolve));
  const browser=await chromium.launch({headless:true,args:["--no-sandbox"]});
  let count=0;
  try {
    const files=fs.readdirSync(corpus).filter(n=>n.endsWith(".mmd"));
    if (!files.length) throw new Error("No captured Mermaid diagrams");
    for(const name of files) {
      const page=await browser.newPage();
      const errors=[];
      page.on("pageerror",e=>errors.push(e.message));
      await page.goto("http://127.0.0.1:"+server.address().port);
      await page.waitForFunction(()=>!!window.kinoInit);
      const source=fs.readFileSync(path.join(corpus,name),"utf8");
      await page.evaluate(source=>window.kinoInit(
        {root:document.querySelector("#root"),importCSS:()=>{}},
        {diagram:source,caption:null,download:true}),source);
      try {
        await page.waitForFunction(()=>document.querySelector("#root figure svg"),null,{timeout:30000});
      } catch(e) {
        throw new Error(name+": "+JSON.stringify(errors)+" "+e.message);
      }
      const actual=await page.evaluate(()=>({
        nodes:document.querySelectorAll("#root svg g.node").length,
        edges:document.querySelectorAll("#root svg .flowchart-link").length,
        text:document.querySelector("#root").textContent
      }));
      if(name==="fixture-escaped.mmd" &&
        (!actual.text.includes("<script>") || !actual.text.includes("%%{init:{}}%%")))
        throw new Error("Escaped labels were not preserved as literal text: "+actual.text);
      const expectedNodes=(source.match(/^    (?:n\d+\[|c\d+_anchor)/gm)||[]).length;
      const expectedEdges=(source.match(/^  n\d+ -->/gm)||[]).length;
      if(errors.length||actual.nodes!==expectedNodes||actual.edges!==expectedEdges)
        throw new Error(name+": "+JSON.stringify({errors,actual,expectedNodes,expectedEdges}));
      const base=path.join(corpus,name.slice(0,-4));
      const paired=fs.existsSync(base+".json")&&fs.existsSync(base+".dot");
      if(process.env.EGGLOG_REQUIRE_DOT_PARITY && !paired)
        throw new Error(name+": missing paired native JSON/DOT");
      let parity="";
      // Save the standalone SVG before building the comparison page.
      if(process.env.EGGLOG_MERMAID_SCREENSHOTS){
        fs.mkdirSync(process.env.EGGLOG_MERMAID_SCREENSHOTS,{recursive:true});
        fs.writeFileSync(path.join(process.env.EGGLOG_MERMAID_SCREENSHOTS,name+".svg"),await page.locator("#root figure svg.flowchart").evaluate(el=>el.outerHTML));
      }
      if(paired) parity=await verifyParity(page,source,base);
      const screenshotDir=process.env.EGGLOG_MERMAID_SCREENSHOTS;
      if(screenshotDir && !paired) {
        fs.mkdirSync(screenshotDir,{recursive:true});
        await page.screenshot({path:path.join(screenshotDir,name+".png"),fullPage:true});
        fs.writeFileSync(path.join(screenshotDir,name+".svg"),await page.locator("#root figure svg.flowchart").evaluate(el=>el.outerHTML));
      }
      console.log("PASS "+name+": "+actual.nodes+" nodes, "+actual.edges+" edges, Kino's bundled Mermaid rendered SVG "+parity);
      ++count;
      await page.close();
    }
    console.log("PASS all "+count+" Mermaid diagrams in Chromium using the supplied Kino assets");
  } finally {
    await browser.close();
    server.close();
  }
})().catch(e=>{console.error(e);server.close();process.exitCode=1;});
