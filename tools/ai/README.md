# 让 AI 玩你的 galgame（PlasticMemory AI 通道）

编辑器存出来的 `project.json` 本来就是纯粹的 JSON——这意味着除了 exe，任何程序都能读它。
这里做的事只有一件：**把它变成一台状态机**，让别的程序（尤其是 AI）一步一步地玩下去。

## 为什么不是「让 AI 直接读 project.json」

因为那样它会一眼看完整个剧本，包括三个结局和所有分支。
AI 一旦知道自己能翻剧本，它就不是在「玩」，是在「演」。

所以这套接口的核心约束是：

> 每次请求只返回**当前这一屏**（这几句台词 + 现在能选什么），不返回未来节点的任何内容。

想作弊只能靠猜，猜不到。

## 跑起来

```bash
cd D:/大肥鱼/工具/plastic-memory/ai
node server.js                 # 默认 127.0.0.1:6130
PORT=7000 node server.js       # 换端口
```

启动时会列出它读到的所有作品（`MemoryStudio/projects` 和 `MemoryStudio/games` 两个目录）。

## 接口

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | `/api/health` | 活着没、读到几个作品 |
| GET | `/api/projects` | 作品列表（id、名字、节点数、是否已发布） |
| POST | `/api/session` | 开一局。body `{"project":"项目id 或 project.json 绝对路径"}` |
| GET | `/api/session/:sid` | 当前这一屏 |
| POST | `/api/session/:sid/next` | 往唯一的出口走一步 |
| POST | `/api/session/:sid/choose` | 选一个。body `{"index":0}`，下标从 0 开始 |
| POST | `/api/session/:sid/restart` | 回开幕 |
| GET | `/api/session/:sid/log` | 走过的每一步（含每次选择），给复盘/评分用 |
| DELETE | `/api/session/:sid` | 销毁这一局 |

一屏的形状：

```json
{
  "project": "半衰期（样品）",
  "sessionId": "smvm8l339klxx5",
  "turn": 3,
  "node": { "id": "event-demo-2", "title": "凌晨的对话框", "type": "event" },
  "prompt": "你要怎么回答？",
  "lines": [
    { "speaker": "旁白", "text": "凌晨两点十七分，对话框里跳出一行字。" },
    { "speaker": "丧彪", "text": "在吗" }
  ],
  "choices": [{ "index": 0, "title": "在。" }, { "index": 1, "title": "你是谁来着？" }],
  "canNext": false,
  "ended": false,
  "ending": null,
  "canRestart": false
}
```

`choices` 非空 = 轮到玩家做决定；`canNext` 为真 = 只有一条路，调 `next` 继续；
`ended` 为真 = 到结局了，`canRestart` 也随之为真。

## 给 AI 的提示词（可以直接抄）

```
你在玩一部互动小说。你只会看到当前这一屏的台词和可选项，看不到后面会发生什么。

规则：
1. 只看 lines。不要猜测剧情走向，不要假装知道结局。
2. choices 非空时，选一个最符合你此刻想法的，用它的 index 调用 choose。
3. canNext 为真时调用 next 继续，台词不会自己往下走。
4. 每次只做一件事：要么 choose，要么 next。
5. 到 ended 就停，用一段话讲讲你这一路为什么这么选。
```

## 已知限制

- 会话只存在内存里，服务一重启全没了（存档要做成写文件的话另说）。
- 只处理文字。立绘、BGM、场景图层这些在数据结构里有，但 AI 通道故意不返回——文字是模型能读的部分。
- 立绘/背景的「视觉信息」目前是黑的。想让 AI 也"看见"，得在节点上加一段文字描述（比如「樱花树，黄昏，她站在树下」），这是接下来值得做的事。

## 顺手的两个脚本

- `../play.js` —— 人在终端里玩（`--tree` 看全图，`--path 1,2` 复现一条线）
- `../validate.js` —— 离线检查剧本有没有断头路（规则照抄编辑器里的 `validate()`）
