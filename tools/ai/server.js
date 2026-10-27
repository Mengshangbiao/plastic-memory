#!/usr/bin/env node
/**
 * PlasticMemory 的「AI 通道」——让别的程序（包括 AI）把作品当成一台状态机来玩。
 *
 * 关键设计：**只给当前**。每次请求只返回「现在这句话 + 现在能选什么」，
 * 不返回全图、不返回未来节点的任何内容。所以 AI 想玩只能一步步走，不能翻剧本。
 *
 * 启动：
 *   node server.js                # 默认 127.0.0.1:6130
 *   PORT=7000 node server.js
 *
 * 接口（全部 JSON）：
 *   GET  /api/health                      → {ok, projects: 数量}
 *   GET  /api/projects                    → [{id, name, nodes, published, source}]
 *   POST /api/session   {project}         → {sessionId}            project 可以是 id，也可以是 project.json 的绝对路径
 *   GET  /api/session/:sid                → 当前这一屏（见下方 view）
 *   POST /api/session/:sid/choose {index} → 选第 index 个（从 0 开始），返回下一屏
 *   POST /api/session/:sid/restart        → 回到开幕
 *   GET  /api/session/:sid/log            → 走过的每一步（含选择），给复盘/评分用
 *   DELETE /api/session/:sid              → 销毁
 *
 * view 形状：
 *   {
 *     project, sessionId, turn, node: {id, title, type},
 *     lines: [{speaker, text}],            // 这一屏的台词
 *     choices: [{index, title}],           // 空数组 = 不能再选
 *     ended: bool, ending: {title} | null, // 走到结局
 *     canRestart: bool
 *   }
 *
 * 注意：是「显式推进」的。台词播完不会自动跳，下一次请求要么选选项，要么调 next。
 * 加 POST /api/session/:sid/next 可以手动往唯一的出口走（也给 AI 一个明确的「继续」动作）。
 */

const http = require("http");
const fs = require("fs");
const path = require("path");
const os = require("os");

const PORT = Number(process.env.PORT || 6130);
const HOST = process.env.HOST || "127.0.0.1";
const ROOT = path.join(
  os.homedir(),
  "AppData/Roaming/com.plasticmemory/plastic_memory/MemoryStudio",
);
const DIRS = [
  { kind: "projects", dir: path.join(ROOT, "projects") },
  { kind: "games", dir: path.join(ROOT, "games") },
];

/* ---------------------------------- 项目 ---------------------------------- */

function listProjects() {
  const out = [];
  for (const { kind, dir } of DIRS) {
    if (!fs.existsSync(dir)) continue;
    for (const d of fs.readdirSync(dir)) {
      const file = path.join(dir, d, "project.json");
      if (!fs.existsSync(file)) continue;
      try {
        const j = JSON.parse(fs.readFileSync(file, "utf8"));
        out.push({
          id: j.id,
          name: j.name,
          nodes: (j.nodes || []).length,
          published: !!j.published,
          source: kind,
          path: file,
        });
      } catch {
        /* 坏档跳过 */
      }
    }
  }
  return out;
}

function loadProject(ref) {
  if (!ref) throw new Error("缺少 project 参数");
  if (fs.existsSync(ref)) {
    const file = fs.statSync(ref).isDirectory() ? path.join(ref, "project.json") : ref;
    return { project: JSON.parse(fs.readFileSync(file, "utf8")), path: file };
  }
  for (const { dir } of DIRS) {
    const file = path.join(dir, ref, "project.json");
    if (fs.existsSync(file)) return { project: JSON.parse(fs.readFileSync(file, "utf8")), path: file };
  }
  throw new Error(`找不到项目：${ref}`);
}

/* -------------------------------- 状态机 -------------------------------- */

function createRun(project, projectPath) {
  const nodes = new Map(project.nodes.map((n) => [n.id, n]));
  const run = {
    id: `s${Date.now().toString(36)}${Math.random().toString(36).slice(2, 7)}`,
    project: project.name,
    projectPath,
    nodes,
    startId: project.startNodeId,
    nodeId: null,
    // 已经播过、但玩家还没「继续」的台词队列
    queue: [],
    pendingChoices: null,
    ended: false,
    endingTitle: null,
    turn: 0,
    log: [],
    visited: [],
    taken: new Set(), // 已经选过的「选项」节点 id，给 requiredChoices 判出现条件用
    createdAt: new Date().toISOString(),
  };
  startRun(run);
  return run;
}

function startRun(run) {
  run.nodeId = run.startId;
  run.queue = [];
  run.pendingChoices = null;
  run.ended = false;
  run.endingTitle = null;
  run.turn = 0;
  run.log = [];
  run.visited = [];
  run.taken = new Set();
  enter(run);
  settle(run);
}

/** 进入某个节点：把台词塞进队列，处理好出口/选项/结局。 */
function enter(run) {
  const node = run.nodes.get(run.nodeId);
  if (!node) {
    run.ended = true;
    run.endingTitle = "（节点丢失）";
    return;
  }
  run.turn += 1;
  run.visited.push(node.id);
  run.log.push({ turn: run.turn, kind: "enter", node: node.id, title: node.title, type: node.type });

  const lines = (node.dialogue || [])
    .map((l) => ({ speaker: l.speaker || "旁白", text: (l.text || "").trim() }))
    .filter((l) => l.text);
  run.queue = lines;
  run.pendingChoices = null;

  if (node.type === "ending") {
    // 结局：台词播完后结束
    return;
  }

  const outs = node.outgoing || [];
  if (outs.length === 0) {
    // 断头，当作结束
    return;
  }

  if (outs.length === 1) {
    // 唯一出口：等台词播完、玩家说继续
    return;
  }

  // 多个出口 = 这里是分叉点。出口必须全是选项节点。
  // 选项节点上的 requiredChoices = 出现条件：玩家之前没选过那几个，这个选项就不出现。
  const all = outs.map((id) => {
    const target = run.nodes.get(id);
    const req = (target && target.requiredChoices) || [];
    return {
      nodeId: id,
      title: target ? target.title : id,
      prompt: (target && target.prompt) || (node.prompt ?? ""),
      unlocked: req.every((r) => run.taken.has(r)),
    };
  });
  const visible = all.filter((c) => c.unlocked);
  // 保险：条件全被卡掉的话不要变成死局，退回显示全部
  const shown = visible.length ? visible : all;
  run.pendingChoices = shown.map((c, i) => ({
    index: i,
    nodeId: c.nodeId,
    title: c.title,
    prompt: c.prompt,
  }));
  run.log.push({
    turn: run.turn,
    kind: "offer",
    node: node.id,
    choices: run.pendingChoices.map((c) => c.title),
  });
}

/**
 * 顺着「没有台词、只有一个出口」的节点一路走过去。
 * 这样玩家选完一个选项，不会停在只写着选项名字的空屏上，而是直接落到下一个场景。
 */
function settle(run) {
  for (let guard = 0; guard < 200; guard++) {
    const node = run.nodes.get(run.nodeId);
    if (!node || node.type === "ending") return;
    const hasLines = (node.dialogue || []).some((l) => (l.text || "").trim());
    const outs = node.outgoing || [];
    if (hasLines || outs.length !== 1) return;
    run.nodeId = outs[0];
    enter(run);
  }
}

/** 把队列里的台词取空；返回这一屏该给玩家看的东西。 */
function view(run) {
  const node = run.nodes.get(run.nodeId);
  const lines = run.queue.slice();
  run.queue = []; // 一屏一次，取走即消失（AI 不能反复刷同一句）

  const choices = [];
  if (run.pendingChoices && !run.ended) {
    for (const c of run.pendingChoices) choices.push({ index: c.index, title: c.title });
  }
  const ended = node?.type === "ending" || run.ended;
  if (ended && !run.endingTitle) run.endingTitle = node?.title ?? "结局";
  const canNext = !ended && !run.pendingChoices && (node?.outgoing || []).length === 1;

  return {
    project: run.project,
    sessionId: run.id,
    turn: run.turn,
    node: node ? { id: node.id, title: node.title, type: node.type } : null,
    prompt: node?.prompt || "",
    lines,
    choices,
    canNext,
    ended,
    ending: ended ? { title: run.endingTitle } : null,
    canRestart: ended,
  };
}

function choose(run, index) {
  if (run.ended) throw new Error("已经到结局了，先 restart");
  if (!run.pendingChoices) throw new Error("当前不是选项点");
  const pick = run.pendingChoices[index];
  if (!pick) throw new Error(`没有第 ${index} 个选项`);
  run.log.push({ turn: run.turn, kind: "choose", index, node: pick.nodeId, title: pick.title });
  run.taken.add(pick.nodeId);
  run.pendingChoices = null;
  run.nodeId = pick.nodeId;
  enter(run);
  settle(run);
  // 选完立刻把选项后面的台词给出去
  return view(run);
}

function next(run) {
  if (run.ended) throw new Error("已经到结局了");
  const node = run.nodes.get(run.nodeId);
  const outs = node?.outgoing || [];
  if (outs.length !== 1) throw new Error("当前节点没有唯一出口，无法继续");
  run.nodeId = outs[0];
  enter(run);
  settle(run);
  return view(run);
}

/* --------------------------------- HTTP --------------------------------- */

const runs = new Map();

function json(res, code, body) {
  const s = JSON.stringify(body);
  res.writeHead(code, {
    "content-type": "application/json; charset=utf-8",
    "content-length": Buffer.byteLength(s),
    "access-control-allow-origin": "*",
  });
  res.end(s);
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let buf = "";
    req.on("data", (c) => {
      buf += c;
      if (buf.length > 1e6) reject(new Error("body 太大"));
    });
    req.on("end", () => {
      if (!buf) return resolve({});
      try {
        resolve(JSON.parse(buf));
      } catch {
        reject(new Error("body 不是合法 JSON"));
      }
    });
    req.on("error", reject);
  });
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host || "localhost"}`);
  const parts = url.pathname.split("/").filter(Boolean); // ['api', ...]
  try {
    if (req.method === "OPTIONS") {
      res.writeHead(204, {
        "access-control-allow-origin": "*",
        "access-control-allow-methods": "GET,POST,DELETE,OPTIONS",
        "access-control-allow-headers": "content-type",
      });
      return res.end();
    }
    if (parts[0] !== "api") return json(res, 404, { error: "未知路径" });

    // GET /api/health
    if (req.method === "GET" && parts[1] === "health") {
      return json(res, 200, { ok: true, projects: listProjects().length, sessions: runs.size });
    }

    // GET /api/projects
    if (req.method === "GET" && parts[1] === "projects") {
      return json(res, 200, listProjects());
    }

    // POST /api/session
    if (req.method === "POST" && parts[1] === "session" && parts.length === 2) {
      const body = await readBody(req);
      const { project, path: p } = loadProject(body.project);
      const run = createRun(project, p);
      runs.set(run.id, run);
      const v = view(run);
      return json(res, 200, { sessionId: run.id, ...v });
    }

    if (parts[1] === "session" && parts[2]) {
      const run = runs.get(parts[2]);
      if (!run) return json(res, 404, { error: "会话不存在或已过期" });

      if (req.method === "DELETE" && parts.length === 3) {
        runs.delete(run.id);
        return json(res, 200, { ok: true });
      }
      if (req.method === "GET" && parts.length === 3) return json(res, 200, view(run));
      if (req.method === "GET" && parts[3] === "log") return json(res, 200, { log: run.log });
      if (req.method === "POST" && parts[3] === "restart") {
        startRun(run);
        return json(res, 200, view(run));
      }
      if (req.method === "POST" && parts[3] === "next") {
        return json(res, 200, next(run));
      }
      if (req.method === "POST" && parts[3] === "choose") {
        const body = await readBody(req);
        return json(res, 200, choose(run, Number(body.index)));
      }
    }

    return json(res, 404, { error: "未知路径" });
  } catch (e) {
    return json(res, 400, { error: String(e.message || e) });
  }
});

server.listen(PORT, HOST, () => {
  const ps = listProjects();
  console.log(`AI 通道已开：http://${HOST}:${PORT}`);
  console.log(`读到 ${ps.length} 个项目：`);
  for (const p of ps) console.log(`  ${p.source.padEnd(9)} ${p.id}  《${p.name}》 ${p.nodes} 个节点`);
});
