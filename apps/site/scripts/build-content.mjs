import { readFile, readdir, mkdir, writeFile } from "node:fs/promises";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const escape = (s) => String(s).replaceAll("&","&amp;").replaceAll("<","&lt;").replaceAll(">","&gt;").replaceAll('"',"&quot;");
const slugOk = (s) => /^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(s);
const metadata = (source) => {
  const match = source.match(/^---\n([\s\S]*?)\n---\n/);
  if (!match) throw new Error("Missing front matter");
  const data = Object.fromEntries(match[1].split("\n").filter(Boolean).map(line => {
    const i = line.indexOf(":"); if (i < 1) throw new Error("Invalid metadata");
    return [line.slice(0,i).trim(),line.slice(i+1).trim().replace(/^["']|["']$/g,"")];
  }));
  if (!data.title || !data.description || !/^\d{4}-\d{2}-\d{2}$/.test(data.date ?? "")) throw new Error("Missing title, description or date");
  return {data, body:source.slice(match[0].length)};
};
const inline = (s) => escape(s).replace(/`([^`]+)`/g,"<code>$1</code>").replace(/\[([^\]]+)\]\((https:\/\/[^\s)]+)\)/g,(_,label,url)=>'<a rel="noopener noreferrer" href="'+url+'">'+label+"</a>");
function render(md) {
  const out=[];let code=[];let lang="";
  const flush=()=>{if(code.length){out.push('<pre><code class="language-'+escape(lang)+'">'+escape(code.join("\n"))+'</code></pre>');code=[];lang="";}};
  for(const line of md.split(/\r?\n/)){
    if(line.startsWith("```")){if(lang || code.length)flush();else lang=line.slice(3).trim() || "text";continue;}
    if(lang){code.push(line);continue;}
    if(!line.trim())continue;
    const h=line.match(/^(#{1,3})\s+(.+)$/);
    if(h){out.push('<h'+h[1].length+'>'+inline(h[2])+'</h'+h[1].length+'>');continue;}
    if(line.startsWith("- "))out.push('<p>• '+inline(line.slice(2))+'</p>');
    else out.push('<p>'+inline(line)+'</p>');
  }flush();return out.join("\n");
}
const shell=(title,desc,body)=>`<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="description" content="${escape(desc)}"><title>${escape(title)} · 技术与项目</title><style>body{font:16px/1.85 system-ui,sans-serif;max-width:760px;margin:60px auto;padding:0 20px;color:#172033;background:#fafbfc}a{color:#245bd0}nav{margin-bottom:45px}article{overflow-wrap:anywhere}pre{background:#192235;color:#e4eaf6;padding:20px;overflow:auto;border-radius:10px}code{font-family:ui-monospace,monospace}h1{line-height:1.3}@media(prefers-color-scheme:dark){body{background:#101722;color:#e5eaf5}a{color:#91b4ff}}</style></head><body><nav><a href="/">首页</a> · <a href="/projects/">项目</a> · <a href="/posts/">文章</a></nav><article>${body}</article><footer><p><a href="mailto:gongshuiwen@gmail.com">gongshuiwen@gmail.com</a></p></footer></body></html>`;
const urls=["https://gongshuiwen.com/"];
for(const type of ["projects","posts"]){
  const dir=join(root,"content",type);
  const names=(await readdir(dir)).filter(n=>n.endsWith(".md")).sort();
  const entries=[];
  for(const name of names){
    const slug=name.slice(0,-3);if(!slugOk(slug))throw new Error("Invalid slug: "+slug);
    const {data,body}=metadata(await readFile(join(dir,name),"utf8"));
    const url="/"+type+"/"+slug+"/";
    const output=join(root,"public",type,slug,"index.html");
    await mkdir(dirname(output),{recursive:true});
    await writeFile(output,shell(data.title,data.description,'<h1>'+escape(data.title)+'</h1><p>'+escape(data.date)+'</p>'+render(body)));
    entries.push({url,...data});urls.push("https://gongshuiwen.com"+url);
  }
  const heading=type==="projects"?"项目":"文章";
  const list=entries.map(e=>'<li><a href="'+e.url+'">'+escape(e.title)+'</a> — '+escape(e.description)+'</li>').join("");
  const output=join(root,"public",type,"index.html");
  await mkdir(dirname(output),{recursive:true});
  await writeFile(output,shell(heading,heading+'列表','<h1>'+heading+'</h1>'+(list?'<ul>'+list+'</ul>':'<p>内容持续更新中。</p>')));
  urls.push("https://gongshuiwen.com/"+type+"/");
}
await writeFile(join(root,"public","sitemap.xml"),'<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">'+urls.map(u=>'<url><loc>'+escape(u)+'</loc></url>').join("")+'</urlset>\n');
console.log("Generated "+urls.length+" sitemap URLs");
