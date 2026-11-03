const {chromium} = require("playwright");
const fs = require("fs"), path = require("path"), http = require("http");
// Dev-only: npm install playwright outside the wrapper, then set NODE_PATH.
// Pass the installed Kino lib/assets/mermaid/build directory and captured corpus.
const [assetsArg, corpusArg] = process.argv.slice(2);
if (!assetsArg || !corpusArg) {
  console.error("Usage: node scripts/check_mermaid_browser.cjs KINO_ASSETS CORPUS_DIR");
  process.exit(1);
}
const assets = path.resolve(assetsArg), corpus = path.resolve(corpusArg);
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
      const expectedNodes=(source.match(/^    (?:n\d+\[|c\d+_anchor)/gm)||[]).length || 1;
      const expectedEdges=(source.match(/ -->\|/g)||[]).length;
      if(errors.length||actual.nodes!==expectedNodes||actual.edges!==expectedEdges)
        throw new Error(name+": "+JSON.stringify({errors,actual,expectedNodes,expectedEdges}));
      console.log("PASS "+name+": "+actual.nodes+" nodes, "+actual.edges+" edges, Kino's bundled Mermaid rendered SVG");
      ++count;
      await page.close();
    }
    console.log("PASS all "+count+" Mermaid diagrams in Chromium using the supplied Kino assets");
  } finally {
    await browser.close();
    server.close();
  }
})().catch(e=>{console.error(e);server.close();process.exitCode=1;});
