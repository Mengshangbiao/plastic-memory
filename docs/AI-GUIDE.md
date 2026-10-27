# 给 AI 的教程：用可塑性记忆写一部作品，再把它玩一遍

这份文档写给**模型**，不是写给人的。人可以去看 [README](../README.md)。

可塑性记忆把一张「剧情图」渲染成 galgame。整部作品就是一个 JSON 文件，所以你不需要鼠标、不需要窗口——
写文件、跑一条命令校验、丢进存档目录，一部能玩的作品就成了。

---

## 一分钟版本

```bash
# 1. 写一个 project.json（结构见第 2 节）
# 2. 校验
node tools/ai/validate.js my-project.json      # 打印 ✓ 就说明能跑
# 3. 在终端里玩一遍
node tools/ai/play.js my-project.json --fast
# 4. 放进 MemoryStudio，用户在「纷乱回忆」里就能看到
node tools/ai/publish.js my-project.json
```

---

## 2. 数据结构

### 2.1 顶层 `project`

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `schemaVersion` | number | **必须是 `1`**，别的值直接判错 |
| `id` | string | 项目编号，只允许 `A-Za-z0-9_-`；决定存档目录名 |
| `name` | string | 作品名，显示在首页和列表里 |
| `startNodeId` | string | 必须指向**唯一**那个 `start` 节点 |
| `characters` | string[] | 说话人名单。`speaker` 用这里面的名字，编辑器才好统一改 |
| `assets` | object[] | 素材清单。纯文字作品给 `[]` |
| `published` | boolean | 由发布流程改写，AI 写草稿时给 `false` |
| `nextChoiceNumber` | number | 选项编号计数器，必须大于所有 `choiceNumber` |
| `updatedAt` | string | ISO 时间，例如 `2026-10-27T20:00:00.000` |
| `dialogueSkin` / `choiceSkin` | string | 对话框/选项按钮的替换图，可留空 |
| `nodes` | StoryNode[] | 剧情图本体 |

### 2.2 `StoryNode`

| 字段 | 说明 |
| --- | --- |
| `id` | 节点编号，全局唯一 |
| `type` | `start` / `event` / `choice` / `random` / `ending` |
| `title` | 标题。对 `choice` 来说**这就是玩家看到的选项文本** |
| `x` `y` | 画布坐标。**只影响编辑器布局，不影响播放**，随便给 |
| `dialogue` | `DialogueLine[]`，这一屏要说的话 |
| `outgoing` | 后续节点 id 数组 |
| `requiredChoices` | 见第 4 节：出现条件 |
| `choiceNumber` | 仅 `choice` 用，永久编号，从 1 开始递增 |
| `prompt` | 仅「多出口的事件」用：选项上方那句提示，如「你要怎么回答？」 |
| `backgroundAsset` `backgroundBlur` `bgmAsset` `clickAsset` | 这一屏的背景/模糊/音乐/点击音 |

### 2.3 `DialogueLine`

| 字段 | 说明 |
| --- | --- |
| `id` | 台词编号，同一项目内唯一；顺序编号 `d1`、`d2`… 最省事 |
| `speaker` | 说话人。`旁白` 是约定俗成的叙述者 |
| `text` | 台词正文 |
| `voiceAsset` | 配音素材，可留空 |
| `textSpeed` `textSize` | `0` 表示跟随全局设置 |
| `bgmMode` | `inherit`（延续上一屏）/ `play` / `stop` |
| `bgmAsset` | 配 `bgmMode: "play"` 时用 |
| `sceneEnabled` | `false` 表示沿用上一屏的演出 |
| `layers` | 演出层。纯文字作品给 `[]`，需要立绘动作时在编辑器里做 |

---

## 3. 六种节点，各自能连什么

| type | 中文 | 出口规则 | 说明 |
| --- | --- | --- | --- |
| `start` | 开幕 | **恰好 1 个** | 只能连 `event` 或 `random`；全项目**必须且只能有一个** |
| `event` | 事件 | 1 个，或多个 | 多个出口时**必须全部是 `choice`**，这时把提示语写在 `prompt` 里 |
| `choice` | 选项 | **恰好 1 个** | 一个选项连一个后续；`title` 就是选项文字 |
| `random` | 乱数选择 | **≥ 2 个** | 只能连 `event`；每次经过等概率抽一个 |
| `ending` | 结局 | **必须 0 个** | 只能被连；对白放完自动回开幕 |

一条常见骨架：

```
start → event ─┬→ choice A → event → … → ending
               └→ choice B → event → … → ending
```

---

## 4. 选项的出现条件（`requiredChoices`）

`requiredChoices` 是一个 `choice` 节点 id 数组，含义是：

> **这些选项都已经被选过，我才会出现。**

它是一层「记得你做过什么」的机关，两种用法：

1. **条件分支**：第 3 屏的选项要等第 1 屏选过「承认」才出现。
2. **隐藏结局**：给最后那个选项挂上前面某个不起眼的选项编号，只有走过那条路的人看得见。

注意：

- `requiredChoices` 只能指向 `type: "choice"` 的节点，否则校验报错。
- 如果所有选项的条件都不满足，播放器不会卡死，它会给出「返回编辑器 / 回开幕」的出口。
- 条件记录在**本次游玩会话**里；`restart` 或重新进入会清空。

---

## 5. 校验的九条（`tools/ai/validate.js`，与 App 内一致）

1. `schemaVersion` 必须是 `1`
2. 有且仅有一个有效开幕，且 `startNodeId` 指向它
3. 节点 id 不重复
4. 至少有一个结局
5. 每个节点都能从开幕到达
6. 除结局外，每个节点至少有一个出口
7. 结局不能有出口；开幕和选项最多一个出口
8. 乱数选择至少两个出口且只连事件；事件的多个出口必须全是选项
9. 每条路线都能走到结局（没有死循环、没有断头路）

跑一遍就知道哪条不满足，报错会直接点名节点标题。

---

## 6. 最小可玩示例

[`docs/example/project.json`](example/project.json) 是一个 6 节点、2 结局的完整作品，可以直接复制来改：

```bash
node tools/ai/validate.js docs/example/project.json   # ✓ 6 个节点
node tools/ai/play.js    docs/example/project.json --path 2 --fast
```

---

## 7. 在终端里把它玩一遍

```bash
node tools/ai/play.js <project.json | 项目目录> [选项]

--path 1,2,1    按顺序自动选第 n 个选项（从 1 开始），用来复现某条路线
--tree          只打印剧情树，不播台词
--fast          关掉打字机延迟
```

`play.js` 是给 AI 用的**极简播放器**，只做文本、选项、结局三件事。
它**不处理 `requiredChoices`**——隐藏选项在它这儿会照常显示。App 里的播放器才是准的。

`--path` 里写错序号会按第一个选项走，不会崩。

---

## 8. 落盘：放进 MemoryStudio

```text
%APPDATA%\com.plasticmemory\plastic_memory\MemoryStudio\
  projects\<项目编号>\project.json   ← 草稿（「创造回忆」里能继续编辑）
  games\<项目编号>\project.json      ← 已发布（「纷乱回忆」里能玩）
```

- 只想让用户在编辑器里打开：写进 `projects/`
- 想让它出现在游玩列表：写进 `games/`，并把 `published` 设为 `true`
- 最省事的办法是 `node tools/ai/publish.js <project.json>`，它一次写两份

---

## 9. 用 HTTP 让 AI 自己玩

`tools/ai/server.js` 是一个零依赖的状态机服务，把作品变成一个可供程序推进的会话。

```bash
node tools/ai/server.js          # 默认 http://127.0.0.1:6130
PORT=7000 node tools/ai/server.js
```

| 方法 | 路径 | 作用 |
| --- | --- | --- |
| GET | `/api/health` | `{ok, projects}` |
| GET | `/api/projects` | 列出 MemoryStudio 里的作品 |
| POST | `/api/session` | `{project}` → `{sessionId}`（`project` 可以是 id 或 json 绝对路径） |
| GET | `/api/session/:sid` | 取当前这一屏 |
| POST | `/api/session/:sid/next` | 往唯一出口走一步 |
| POST | `/api/session/:sid/choose` | `{index}` 选第 index 个（**从 0 开始**） |
| POST | `/api/session/:sid/restart` | 回到开幕 |
| GET | `/api/session/:sid/log` | 走过的每一步和每次选择，用来复盘或评分 |
| DELETE | `/api/session/:sid` | 销毁会话 |

```bash
SID=$(curl -s -X POST localhost:6130/api/session \
       -H 'content-type: application/json' \
       -d '{"project":"docs/example/project.json"}' | node -pe 'JSON.parse(require("fs").readFileSync(0)).sessionId')

curl -s localhost:6130/api/session/$SID          # 看这一屏
curl -s -X POST localhost:6130/api/session/$SID/choose \
     -H 'content-type: application/json' -d '{"index":0}'
```

**两个设计决定，别改：**

1. **只返回当前这一屏**，不把完整剧情图发给玩家方。否则 AI 可以提前读到所有结局，玩起来就是作弊。
2. **`choose` 的 `index` 是从 0 开始的数组下标**，不是 `choiceNumber`。`choiceNumber` 是编辑器里给人看的永久编号，两套编号不要混。

服务会自动穿过「没有台词、只有一个出口」的节点（比如连续的选项、乱数），所以你拿到的一屏一定是有字或有选项的那一屏。

---

## 10. 常见错误对照

| 症状 | 原因 | 改法 |
| --- | --- | --- |
| 校验说「没有后续节点」 | 某个 `event` 的 `outgoing` 是空的 | 补出口，或把它的 type 改成 `ending` |
| 「多个出口必须全部是选项」 | 事件连了两个事件 | 中间插入一层 `choice` 节点 |
| 「无法从开幕到达」 | 线索断了，或 `startNodeId` 写错 | 检查 `outgoing` 链 |
| 「存在无法到达结局的路线」 | 有环但环里没有结局 | 在环的某处接一个结局 |
| 选项不出现 | `requiredChoices` 指向的选项没被选过 | 要么检查编号，要么去掉条件 |
| App 里看不到作品 | 只写了 `projects/` | 用 `publish.js` 发布到 `games/` |
| 玩家看到「#3 你现在怎么办」这种文字 | 把 `choiceNumber` 当标题写了 | `title` 是选项文字，编号交给 `choiceNumber` |

---

## 11. 写给 AI 的写作建议

- **先画树，再写词**。先把 20–60 个节点和它们的连线定下来，确认校验能过，再往 `dialogue` 里填句子。反过来做会在改结构时把台词改散。
- **一个节点 3–8 句**。超过十句，玩家会开始跳过；少于三句，情绪立不起来。
- **全篇 3000–6000 字**是舒服的体量。一万字以上，选项就必须足够密，否则后半程全是点击。
- **选项要有代价**。三个选项都通向同一个结局，前面的分叉就白做了。至少让玩家在最后一屏之前，为前面的选择付一次账。
- **结局要回答「为什么停在这里」**。一个好的结局是：事情没有全部解决，但叙述者已经没有话要说了。
- **别写这种旁白**：「以目前的情报看来」「看来事情并不简单」。换成具体的动作和物体：删错别字、置顶对话框、说面有点咸。
- **台词 id 顺序编号**，`d1`…`dN`，重建时重编一遍最省心。

---

许可：MIT，同[仓库根目录](../LICENSE)。
