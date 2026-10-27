#!/usr/bin/env node
/**
 * 离线检查 PlasticMemory 作品能不能跑通——规则照抄 lib/models.dart 的 validate()。
 *
 * 用法：
 *   node validate.js <project.json | 项目目录> [...更多]
 *   node validate.js --all              # 检查 MemoryStudio 里所有作品
 *
 * 退出码：0 全部通过；1 有问题。
 */

const fs = require("fs");
const path = require("path");
const os = require("os");

const ROOT = path.join(
  os.homedir(),
  "AppData/Roaming/com.plasticmemory/plastic_memory/MemoryStudio",
);

function load(ref) {
  let file = ref;
  if (!fs.existsSync(file)) throw new Error(`不存在：${file}`);
  if (fs.statSync(file).isDirectory()) file = path.join(file, "project.json");
  if (!fs.existsSync(file)) throw new Error(`找不到 project.json：${file}`);
  return JSON.parse(fs.readFileSync(file, "utf8"));
}

function check(p) {
  const issues = [];
  const nodes = p.nodes || [];
  const byId = new Map(nodes.map((n) => [n.id, n]));
  const start = byId.get(p.startNodeId);
  const label = (n) => (n.type === "choice" ? `#${n.choiceNumber} ${n.title}` : n.title);

  if (p.schemaVersion !== 1) issues.push(`schemaVersion 是 ${p.schemaVersion}，只支持 1`);
  if (start?.type !== "start" || nodes.filter((n) => n.type === "start").length !== 1)
    issues.push("需要且只能有一个有效开幕节点。");
  if (byId.size !== nodes.length) issues.push("存在重复节点编号。");
  if (!nodes.some((n) => n.type === "ending")) issues.push("请添加一个结局。");

  const reachable = new Set();
  const visit = (id) => {
    if (reachable.has(id)) return;
    reachable.add(id);
    for (const next of byId.get(id)?.outgoing || []) visit(next);
  };
  if (start) visit(start.id);

  for (const n of nodes) {
    const name = label(n);
    if (!reachable.has(n.id)) issues.push(`${name} 无法从开幕到达。`);
    if (n.type !== "ending" && (n.outgoing || []).length === 0) issues.push(`${name} 没有后续节点。`);
    if (n.type === "ending" && (n.outgoing || []).length > 0) issues.push(`${name} 不能有出口。`);
    if ((n.type === "start" || n.type === "choice") && (n.outgoing || []).length > 1)
      issues.push(`${name} 只能有一个出口。`);
    if (n.type === "random" && (n.outgoing || []).length < 2) issues.push(`${name} 至少需要连接两个事件。`);
    if (n.type === "event" && (n.outgoing || []).length > 1 &&
        n.outgoing.some((id) => byId.get(id)?.type !== "choice"))
      issues.push(`${name} 的多个出口必须全部是选项。`);

    for (const id of n.outgoing || []) {
      const t = byId.get(id);
      if (!t) { issues.push(`${name} 连接到了已删除的节点。`); continue; }
      if ((t.type === "start" && n.type !== "event") || id === n.id) issues.push(`${name} 包含无效连线。`);
      if (n.type === "start" && t.type !== "event" && t.type !== "random")
        issues.push("开幕只能连接事件或乱数选择。");
      if (n.type === "random" && t.type !== "event") issues.push(`${name} 只能连接事件。`);
    }
    for (const id of n.requiredChoices || []) {
      if (byId.get(id)?.type !== "choice" || id === n.id) issues.push(`${name} 的出现条件包含无效选项。`);
    }
  }

  // 每条路线都必须能走到结局
  const canFinish = new Set(nodes.filter((n) => n.type === "ending").map((n) => n.id));
  let changed = true;
  while (changed) {
    changed = false;
    for (const n of nodes) {
      if ((n.outgoing || []).some((id) => canFinish.has(id)) && !canFinish.has(n.id)) {
        canFinish.add(n.id);
        changed = true;
      }
    }
  }
  const deadEnd = [...reachable].filter((id) => !canFinish.has(id));
  if (deadEnd.length)
    issues.push(`存在无法到达结局的路线，请检查循环或断开的出口。`);

  return { issues: [...new Set(issues)], nodes: nodes.length, deadEnd };
}

function summary(p, r) {
  const ok = r.issues.length === 0;
  console.log(`${ok ? "✓" : "✗"} 《${p.name}》 ${r.nodes} 个节点`);
  for (const i of r.issues) console.log(`    - ${i}`);
  return ok;
}

const args = process.argv.slice(2);
const targets = [];

if (args.includes("--all")) {
  for (const kind of ["projects", "games"]) {
    const dir = path.join(ROOT, kind);
    if (!fs.existsSync(dir)) continue;
    for (const d of fs.readdirSync(dir)) {
      const f = path.join(dir, d, "project.json");
      if (fs.existsSync(f)) targets.push(f);
    }
  }
} else {
  targets.push(...args.filter((a) => !a.startsWith("--")));
}

if (!targets.length) {
  console.log("用法：node validate.js <project.json|目录>... 或 --all");
  process.exit(2);
}

let allOk = true;
for (const t of targets) {
  try {
    const p = load(t);
    if (!summary(p, check(p))) allOk = false;
  } catch (e) {
    allOk = false;
    console.log(`✗ ${t}：${e.message}`);
  }
}
process.exit(allOk ? 0 : 1);
