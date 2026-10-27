import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models.dart';
import 'storage.dart';
import 'stage.dart';
import 'ui.dart';

Future<void> editNodeSettings(
  BuildContext context,
  ProjectModel project,
  StoryNode node,
) async {
  var background = node.backgroundAsset,
      bgm = node.bgmAsset,
      click = node.clickAsset;
  var blur = node.backgroundBlur;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        title: Text('${node.title} · 场景设置'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AssetSelect(
                  project: project,
                  label: '背景图',
                  value: background,
                  category: AssetCategory.background,
                  emptyLabel: '延续上一场景',
                  onChanged: (v) => update(() => background = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('模糊背景图'),
                  value: blur,
                  onChanged: (v) => update(() => blur = v),
                ),
                AssetSelect(
                  project: project,
                  label: '整段背景音乐',
                  value: bgm,
                  category: AssetCategory.bgm,
                  emptyLabel: '延续上一段音乐',
                  onChanged: (v) => update(() => bgm = v),
                ),
                const SizedBox(height: 16),
                AssetSelect(
                  project: project,
                  label: '文本点击音',
                  value: click,
                  category: AssetCategory.click,
                  onChanged: (v) => update(() => click = v),
                ),
                const SizedBox(height: 12),
                const Text(
                  '单句设置的背景音乐优先；单句选择“延续”时，沿用当前正在播放的音乐。',
                  style: TextStyle(fontSize: 12, color: secondaryInk),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              node.backgroundAsset = background;
              node.backgroundBlur = blur;
              node.bgmAsset = bgm;
              node.clickAsset = click;
              Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
}

class DialoguePage extends StatefulWidget {
  const DialoguePage({
    super.key,
    required this.project,
    required this.node,
    required this.store,
  });
  final ProjectModel project;
  final StoryNode node;
  final ProjectStore store;
  @override
  State<DialoguePage> createState() => _DialoguePageState();
}

class _DialoguePageState extends State<DialoguePage> {
  final text = TextEditingController();
  final focus = FocusNode();
  final scroll = ScrollController();
  String? speaker;
  bool composing = true;
  @override
  void dispose() {
    text.dispose();
    focus.dispose();
    scroll.dispose();
    super.dispose();
  }

  void _append() {
    if (speaker == null || text.text.trim().isEmpty) return;
    setState(() {
      widget.node.dialogue.add(
        DialogueLine(
          id: newId('line'),
          speaker: speaker!,
          text: text.text.trim(),
        ),
      );
      text.clear();
      speaker = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && scroll.hasClients)
        scroll.animateTo(
          scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
    });
  }

  Future<void> _leave() async {
    if (text.text.trim().isNotEmpty) {
      if (speaker == null) {
        notify(context, '请先选择人物，再保存当前文本。');
        return;
      }
      _append();
    }
    Navigator.pop(context, true);
  }

  Future<void> _scene(DialogueLine line) async {
    var inherited = <StageLayer>[];
    for (final previous in widget.node.dialogue) {
      if (previous.id == line.id) break;
      if (previous.sceneEnabled)
        inherited = stageAt(previous.layers, double.infinity);
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StageEditor(
          project: widget.project,
          store: widget.store,
          node: widget.node,
          line: line,
          inheritedLayers: inherited,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _lineMenu(DialogueLine line, Offset position) async {
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: const [
        PopupMenuItem(value: 'text', child: Text('编辑人物与文本')),
        PopupMenuItem(value: 'stage', child: Text('编辑演出')),
        PopupMenuItem(value: 'settings', child: Text('音乐 / 语音 / 文字设置')),
        PopupMenuItem(value: 'inherit', child: Text('清除本句演出，延续上一场景')),
        PopupMenuItem(value: 'delete', child: Text('删除这段对白')),
      ],
    );
    if (!mounted) return;
    switch (action) {
      case 'text':
        await _editText(line);
      case 'stage':
        await _scene(line);
      case 'settings':
        await _lineSettings(line);
      case 'inherit':
        line.layers.clear();
        line.sceneEnabled = false;
      case 'delete':
        if (await confirm(context, '删除对白', '删除这段文本及其演出？'))
          widget.node.dialogue.remove(line);
    }
    if (mounted) setState(() {});
  }

  Future<void> _editText(DialogueLine line) async {
    final controller = TextEditingController(text: line.text);
    var character = line.speaker;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('编辑对白'),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: character,
                  decoration: const InputDecoration(labelText: '人物'),
                  items: {...widget.project.characters, character}
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) => update(() => character = v!),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  minLines: 3,
                  maxLines: 7,
                  decoration: const InputDecoration(labelText: '文本'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (controller.text.trim().isEmpty) return;
                line.speaker = character;
                line.text = controller.text.trim();
                Navigator.pop(context);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    controller.dispose();
  }

  Future<void> _lineSettings(DialogueLine line) async {
    var mode = line.bgmMode, bgm = line.bgmAsset, voice = line.voiceAsset;
    var speed = line.textSpeed, size = line.textSize;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('这段文本的声音与显示'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: mode,
                    decoration: const InputDecoration(labelText: '背景音乐'),
                    items: const [
                      DropdownMenuItem(
                        value: 'inherit',
                        child: Text('延续上一段（默认）'),
                      ),
                      DropdownMenuItem(value: 'replace', child: Text('指定背景音乐')),
                      DropdownMenuItem(value: 'stop', child: Text('停止背景音乐')),
                    ],
                    onChanged: (v) => update(() => mode = v!),
                  ),
                  if (mode == 'replace') ...[
                    const SizedBox(height: 14),
                    AssetSelect(
                      project: widget.project,
                      label: '音乐素材',
                      value: bgm,
                      category: AssetCategory.bgm,
                      onChanged: (v) => update(() => bgm = v),
                    ),
                  ],
                  const SizedBox(height: 14),
                  AssetSelect(
                    project: widget.project,
                    label: '人物语音',
                    value: voice,
                    category: AssetCategory.voice,
                    onChanged: (v) => update(() => voice = v),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    speed == 0 ? '文字速度：使用玩家设置' : '文字速度：${speed.round()} 字 / 秒',
                  ),
                  Slider(
                    value: speed.clamp(0, 100),
                    max: 100,
                    divisions: 100,
                    onChanged: (v) => update(() => speed = v),
                  ),
                  Text(size == 0 ? '文字大小：使用玩家设置' : '文字大小：${size.round()}'),
                  Slider(
                    value: size.clamp(0, 36),
                    max: 36,
                    divisions: 36,
                    onChanged: (v) =>
                        update(() => size = v == 0 ? 0 : v.clamp(14, 36)),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (mode == 'replace' && bgm.isEmpty) {
                  notify(context, '请选择音乐素材。');
                  return;
                }
                line.bgmMode = mode;
                line.bgmAsset = bgm;
                line.voiceAsset = voice;
                line.textSpeed = speed;
                line.textSize = size;
                Navigator.pop(context);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _leave();
    },
    child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: _leave,
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text('${widget.node.title} · 剧情与演出'),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await editNodeSettings(context, widget.project, widget.node);
              if (mounted) setState(() {});
            },
            icon: const Icon(Icons.landscape_outlined),
            label: const Text('整段设置'),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton(onPressed: _leave, child: const Text('完成编辑')),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(18),
                child: Text(
                  '选择人物后输入文本，Enter 完成一段，Shift + Enter 换行。双击对白制作演出，右键修改文本与声音。',
                  style: TextStyle(color: secondaryInk),
                ),
              ),
              Expanded(
                child: widget.node.dialogue.isEmpty
                    ? const Center(
                        child: Text(
                          '从第一段对白开始这段回忆。',
                          style: TextStyle(fontSize: 20, color: accent),
                        ),
                      )
                    : ListView.builder(
                        controller: scroll,
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        itemCount: widget.node.dialogue.length,
                        itemBuilder: (context, index) {
                          final line = widget.node.dialogue[index];
                          return GestureDetector(
                            key: ValueKey(line.id),
                            onSecondaryTapUp: (d) =>
                                _lineMenu(line, d.globalPosition),
                            child: Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    CircleAvatar(
                                      backgroundColor: hairline,
                                      child: Text(
                                        '${index + 1}',
                                        style: const TextStyle(color: accent),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onDoubleTap: () => _scene(line),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${line.speaker}：',
                                              style: const TextStyle(
                                                color: accent,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              line.text,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                height: 1.6,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              line.sceneEnabled
                                                  ? '${line.layers.length} 个图层 · ${line.layers.fold<int>(0, (n, l) => n + l.motions.length)} 个动作'
                                                  : '延续上一场景',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: secondaryInk,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: '制作演出',
                                      onPressed: () => _scene(line),
                                      icon: const Icon(
                                        Icons.movie_creation_outlined,
                                        color: accent,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: '上移对白',
                                      onPressed: index == 0
                                          ? null
                                          : () => setState(() {
                                              widget.node.dialogue.removeAt(
                                                index,
                                              );
                                              widget.node.dialogue.insert(
                                                index - 1,
                                                line,
                                              );
                                            }),
                                      icon: const Icon(
                                        Icons.arrow_upward,
                                        size: 18,
                                      ),
                                    ),
                                    Builder(
                                      builder: (buttonContext) => IconButton(
                                        tooltip: '对白设置',
                                        onPressed: () {
                                          final box =
                                              buttonContext.findRenderObject()
                                                  as RenderBox;
                                          _lineMenu(
                                            line,
                                            box.localToGlobal(Offset.zero),
                                          );
                                        },
                                        icon: const Icon(Icons.more_vert),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              if (composing)
                Container(
                  margin: const EdgeInsets.all(24),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: memoryRadius,
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: 190,
                            child: DropdownButtonFormField<String>(
                              key: ValueKey('speaker-$speaker'),
                              initialValue: speaker,
                              decoration: const InputDecoration(
                                labelText: '选择人物',
                              ),
                              items: widget.project.characters
                                  .map(
                                    (c) => DropdownMenuItem(
                                      value: c,
                                      child: Text(c),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) {
                                setState(() => speaker = v);
                                focus.requestFocus();
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              speaker == null ? '先选择这段文本的说话人物' : '$speaker：',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: accent,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              if (text.text.trim().isNotEmpty) _append();
                              if (text.text.trim().isEmpty)
                                setState(() => composing = false);
                            },
                            child: const Text('结束文本编写'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      CallbackShortcuts(
                        bindings: {
                          const SingleActivator(LogicalKeyboardKey.enter):
                              _append,
                        },
                        child: TextField(
                          controller: text,
                          focusNode: focus,
                          enabled: speaker != null,
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            hintText: '在这里写下这段文本…',
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: _append,
                          icon: const Icon(Icons.subdirectory_arrow_left),
                          label: const Text('完成这段 · 选择下个人物'),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: OutlinedButton.icon(
                    onPressed: () => setState(() => composing = true),
                    icon: const Icon(Icons.add),
                    label: const Text('继续编写对白'),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
