#!/usr/bin/env node
/**
 * 把一个草稿项目「发布」到 games 目录——就是编辑器里点「发布」做的事：
 * 把 project.json 复制一份、published 改成 true，放到 MemoryStudio/games/<id>/。
 *
 * 玩法界面（纷乱回忆）只列 games 里的东西，所以作品要先发布才看得到。
 *
 * 用法：
 *   node publish.js docs/example/project.json
 */
const fs = require("fs");
const path = require("path");
const os = require("os");

const ROOT = path.join(
  os.homedir(),
  "AppData/Roaming/com.plasticmemory/plastic_memory/MemoryStudio",
);

const src = process.argv[2];
if (!src) {
  console.log("用法：node publish.js <project.json>");
  process.exit(2);
}

let file = src;
if (fs.existsSync(file) && fs.statSync(file).isDirectory()) file = path.join(file, "project.json");
const p = JSON.parse(fs.readFileSync(file, "utf8"));
if (!/^[a-zA-Z0-9_-]+$/.test(p.id)) {
  console.log(`项目 id 里只能有字母数字下划线和横线：${p.id}`);
  process.exit(1);
}

p.published = true;
const outDir = path.join(ROOT, "games", p.id);
fs.mkdirSync(outDir, { recursive: true });
fs.writeFileSync(path.join(outDir, "project.json"), JSON.stringify(p, null, 2), "utf8");

// 草稿也同步一份，两边一致
const draftDir = path.join(ROOT, "projects", p.id);
fs.mkdirSync(draftDir, { recursive: true });
fs.writeFileSync(path.join(draftDir, "project.json"), JSON.stringify(p, null, 2), "utf8");

console.log(`已发布《${p.name}》→ ${outDir}`);
console.log(`草稿同步 → ${draftDir}`);
console.log(`节点 ${p.nodes.length} 个，结局 ${p.nodes.filter((n) => n.type === "ending").length} 个`);
