#!/usr/bin/env node
/**
 * 在终端里玩 PlasticMemory 做出来的 galgame。
 *
 * 用法：
 *   node play.js <project.json 路径>                  # 交互式，选项按数字选
 *   node play.js <project.json> --path 1,2            # 按顺序自动选，可复现一条路线
 *   node play.js <project.json> --tree                 # 只打印剧情树，不玩
 *
 * 也可以直接指向项目目录，脚本会自己找里面的 project.json。
 */

const fs = require("fs");
const path = require("path");
const readline = require("readline");

function loadProject(target) {
  let file = target;
  if (fs.existsSync(file) && fs.statSync(file).isDirectory()) file = path.join(file, "project.json");
  if (!fs.existsSync(file)) throw new Error(`找不到 project.json：${file}`);
  return JSON.parse(fs.readFileSync(file, "utf8"));
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  const args = process.argv.slice(2);
  const target = args.find((a) => !a.startsWith("--"));
  const pathArg = (() => {
    const i = args.indexOf("--path");
    return i >= 0 ? args[i + 1].split(",").map((s) => Number(s.trim())) : null;
  })();
  const asTree = args.includes("--tree");
  const fast = args.includes("--fast");

  const project = loadProject(target);
  const nodes = new Map(project.nodes.map((n) => [n.id, n]));
  const start = nodes.get(project.startNodeId);

  console.log(`《${project.name}》`);
  if (project.characters?.length) console.log(`角色：${project.characters.join("、")}`);
  console.log("—".repeat(40));

  if (asTree) {
    const seen = new Set();
    const walk = (id, depth) => {
      const n = nodes.get(id);
      if (!n || seen.has(id)) return;
      seen.add(id);
      console.log(`${"  ".repeat(depth)}[${n.type}] ${n.title}`);
      for (const l of n.dialogue || []) console.log(`${"  ".repeat(depth)}    ${l.speaker}：${l.text}`);
      for (const o of n.outgoing || []) walk(o, depth + 1);
    };
    walk(start.id, 0);
    return;
  }

  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  const ask = (q) => new Promise((res) => rl.question(q, res));

  let current = start;
  let pickIndex = 0;
  let steps = 0;

  while (current) {
    if (steps++ > 2000) {
      console.log("\n[脚本] 走太久了，可能是循环，先停。");
      break;
    }

    if (current.type !== "start") {
      console.log(`\n· ${current.title} ·`);
    }
    for (const l of current.dialogue || []) {
      const t = (l.text || "").trim();
      if (!t) continue;
      console.log(`\n${l.speaker}：${t}`);
      if (!fast) await sleep(320);
    }

    if (current.type === "ending") {
      console.log("\n— 完 —");
      const back = nodes.get(project.startNodeId);
      console.log(`（结局：${current.title}；点击会回到开幕「${back?.title ?? "?"}」）`);
      break;
    }

    const outs = current.outgoing || [];
    if (!outs.length) {
      console.log("\n[脚本] 这里没有出口了。");
      break;
    }

    let nextId;
    if (outs.length === 1) {
      nextId = outs[0];
    } else {
      const choices = outs.map((id) => nodes.get(id));
      let choice = null;

      if (current.type === "random") {
        choice = Math.floor(Math.random() * choices.length);
        console.log(`\n（乱数选择 → 抽到第 ${choice + 1} 个）`);
      } else if (pathArg) {
        choice = (pathArg[pickIndex++] ?? 1) - 1;
        if (choice < 0 || choice >= choices.length) choice = 0;
      } else {
        if (current.prompt) console.log(`\n${current.prompt}`);
        choices.forEach((c, i) => console.log(`  ${i + 1}. ${c.title}`));
        const ans = await ask("> ");
        choice = Number(ans.trim()) - 1;
        if (Number.isNaN(choice) || choice < 0 || choice >= choices.length) choice = 0;
      }

      nextId = choices[choice].id;
      if (!pathArg && current.type !== "random") console.log(`→ ${choices[choice].title}`);
    }

    current = nodes.get(nextId);
  }

  rl.close();
}

main().catch((e) => {
  console.error("出错了：" + e.message);
  process.exit(1);
});
