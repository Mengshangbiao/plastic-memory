import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'assets_page.dart';
import 'dialogue_page.dart';
import 'graph_canvas.dart';
import 'models.dart';
import 'player.dart';
import 'project_actions.dart';
import 'stage.dart';
import 'storage.dart';
import 'ui.dart';

class EditorPage extends StatefulWidget {
  const EditorPage({
    super.key,
    required this.project,
    required this.store,
    required this.settings,
  });
  final ProjectModel project;
  final ProjectStore store;
  final AppSettings settings;
  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  final canvas = GlobalKey<GraphCanvasState>();
  late String selectedId = widget.project.startNodeId;
  bool toolsOpen = true,
      filesOpen = true,
      peopleOpen = true,
      inspectorOpen = true;
  bool saving = false, dirty = false;
  int revision = 0;
  String status = '双击节点编辑 · 右键节点设置 · 滚轮缩放画布';
  Timer? autosave;
  ProjectModel get project => widget.project;
  StoryNode? get selected => project.nodeById(selectedId);
  @override
  void dispose() {
    autosave?.cancel();
    super.dispose();
  }

  void _changed() {
    setState(() {
      dirty = true;
      revision++;
      project.published = false;
      status = '有未保存的修改';
    });
    autosave?.cancel();
    autosave = Timer(const Duration(seconds: 2), () => _save(quiet: true));
  }

  Future<bool> _save({bool quiet = false}) async {
    autosave?.cancel();
    if (saving) return false;
    final savedRevision = revision;
    setState(() => saving = true);
    try {
      await widget.store.save(project);
      if (mounted)
        setState(() {
          dirty = revision != savedRevision;
          status = dirty
              ? '有未保存的修改'
              : quiet
              ? '已自动保存'
              : '已保存到本地项目文件夹';
        });
      return true;
    } catch (e) {
      if (mounted) {
        setState(() => status = '保存失败，请重试');
        if (!quiet) notify(context, '保存失败：$e');
      }
      return false;
    } finally {
      if (mounted) {
        setState(() => saving = false);
        // Changes made during an in-flight save must be persisted afterwards.
        if (revision != savedRevision) {
          dirty = true;
          autosave = Timer(
            const Duration(seconds: 2),
            () => _save(quiet: true),
          );
        }
      }
    }
  }

  Future<void> _leave() async {
    if (await _save() && mounted) Navigator.pop(context);
  }

  Future<void> _openProject() async {
    if (!await _save() || !mounted) return;
    try {
      final drafts = await widget.store.loadProjects();
      if (!mounted) return;
      final result = await showDialog<ProjectPickerResult>(
        context: context,
        builder: (_) => ProjectPickerDialog(
          store: widget.store,
          drafts: drafts,
          currentId: project.id,
        ),
      );
      if (result == null || !mounted) return;
      autosave?.cancel();
      if (result.deletedCurrent) {
        Navigator.pop(context);
      } else {
        Navigator.pop(context, result.project);
      }
    } catch (e) {
      if (mounted) notify(context, '打开项目失败：$e');
    }
  }

  Future<void> _open(StoryNode node) async {
    if (node.type == StoryNodeType.event || node.type == StoryNodeType.ending) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              DialoguePage(project: project, node: node, store: widget.store),
        ),
      );
    } else if (node.type == StoryNodeType.start) {
      if (node.dialogue.isEmpty)
        node.dialogue.add(DialogueLine(id: newId('menu')));
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => StageEditor(
            project: project,
            store: widget.store,
            line: node.dialogue.first,
            node: node,
          ),
        ),
      );
    } else if (node.type == StoryNodeType.choice) {
      final prompt = await askText(
        context,
        '同级选项的提示文本',
        initial: node.prompt,
        label: '所有同级选项共用这一段提示',
        maxLines: 4,
      );
      if (prompt != null) project.setChoicePrompt(node, prompt);
    } else {
      notify(context, '把乱数选择连接到两个或更多事件，试玩时会随机进入其中一个。');
      return;
    }
    if (mounted) _changed();
  }

  Future<void> _conditions(StoryNode node) async {
    final choices = project.nodes
        .where((n) => n.type == StoryNodeType.choice && n.id != node.id)
        .toList();
    var required = node.requiredChoices.toSet();
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text('选项 #${node.choiceNumber} · 出现条件'),
          content: SizedBox(
            width: 470,
            height: 320,
            child: Column(
              children: [
                const Text('只有勾选的编号都曾被玩家选择，这个选项才会出现。不勾选则始终出现。'),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView(
                    children: [
                      ...choices.map(
                        (choice) => CheckboxListTile(
                          value: required.contains(choice.id),
                          title: Text(
                            '#${choice.choiceNumber}  ${choice.title}',
                          ),
                          onChanged: (v) => update(() {
                            if (v == true)
                              required.add(choice.id);
                            else
                              required.remove(choice.id);
                          }),
                        ),
                      ),
                      ...required
                          .where((id) => project.nodeById(id) == null)
                          .toList()
                          .map(
                            (id) => ListTile(
                              title: const Text(
                                '已删除的条件选项',
                                style: TextStyle(color: anger),
                              ),
                              trailing: IconButton(
                                onPressed: () =>
                                    update(() => required.remove(id)),
                                icon: const Icon(Icons.close),
                              ),
                            ),
                          ),
                    ],
                  ),
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
                node.requiredChoices = required.toList();
                Navigator.pop(context);
                _changed();
              },
              child: const Text('保存条件'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _context(StoryNode node, Offset position) async {
    setState(() => selectedId = node.id);
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        PopupMenuItem(
          value: 'open',
          child: Text(
            node.type == StoryNodeType.start
                ? '编辑开幕画面'
                : node.type == StoryNodeType.choice
                ? '编辑共同提示'
                : '编辑剧情 / 演出',
          ),
        ),
        PopupMenuItem(
          value: 'rename',
          child: Text(node.type == StoryNodeType.choice ? '编辑选项文本' : '重命名'),
        ),
        if (node.type == StoryNodeType.event ||
            node.type == StoryNodeType.ending ||
            node.type == StoryNodeType.start)
          const PopupMenuItem(
            value: 'settings',
            child: Text('背景图 / 背景音乐 / 点击音'),
          ),
        if (node.type == StoryNodeType.choice)
          const PopupMenuItem(value: 'conditions', child: Text('出现条件')),
        if (node.type != StoryNodeType.start)
          const PopupMenuItem(value: 'delete', child: Text('删除节点')),
      ],
    );
    if (!mounted) return;
    switch (action) {
      case 'open':
        await _open(node);
      case 'rename':
        final title = await askText(
          context,
          node.type == StoryNodeType.choice ? '选项文本' : '节点名称',
          initial: node.title,
        );
        if (title != null) {
          node.title = title;
          _changed();
        }
      case 'settings':
        await editNodeSettings(context, project, node);
        if (mounted) _changed();
      case 'conditions':
        await _conditions(node);
      case 'delete':
        if (await confirm(
          context,
          '删除${node.type.label}',
          '将删除“${node.title}”及它的连线、对白和演出。',
        )) {
          project.removeNode(node.id);
          selectedId = project.startNodeId;
          _changed();
        }
    }
  }

  Future<bool> _check() async {
    final issues = project.validate();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(issues.isEmpty ? '流程检查通过' : '发现 ${issues.length} 个问题'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Text(
              issues.isEmpty
                  ? '入口、分支与结局已连接。可以测试运行或创建游戏。'
                  : issues.map((s) => '• $s').join('\n\n'),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
    return issues.isEmpty;
  }

  Future<void> _publish() async {
    if (project.validate().isNotEmpty) {
      await _check();
      return;
    }
    if (!await _save() || !mounted) return;
    setState(() => saving = true);
    try {
      await widget.store.publish(project);
      if (mounted) {
        setState(() => status = '已创建游戏，可在“纷乱回忆”中游玩');
        notify(context, '游戏已创建。返回首页 → 纷乱回忆，即可游玩完成的版本。');
      }
    } catch (e) {
      if (mounted) notify(context, '创建失败：$e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _assets() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AssetsPage(project: project, store: widget.store),
      ),
    );
    if (mounted) _changed();
  }

  Future<void> _person({String? old}) async {
    final name = await askText(
      context,
      old == null ? '创建人物' : '人物重命名',
      initial: old ?? '',
    );
    if (name == null || !mounted || name == old) return;
    if (project.characters.contains(name)) {
      notify(context, '已存在同名人物。');
      return;
    }
    if (old == null)
      project.characters.add(name);
    else {
      project.characters[project.characters.indexOf(old)] = name;
      for (final node in project.nodes) {
        for (final line in node.dialogue) {
          if (line.speaker == old) line.speaker = name;
        }
      }
    }
    _changed();
  }

  Future<void> _skins() async {
    var dialogue = project.dialogueSkin, choice = project.choiceSkin;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('公用界面素材'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AssetSelect(
                  project: project,
                  label: '对话框图片',
                  value: dialogue,
                  imagesOnly: true,
                  emptyLabel: '默认对话框',
                  onChanged: (v) => update(() => dialogue = v),
                ),
                const SizedBox(height: 16),
                AssetSelect(
                  project: project,
                  label: '选项按钮图片',
                  value: choice,
                  imagesOnly: true,
                  emptyLabel: '默认选项按钮',
                  onChanged: (v) => update(() => choice = v),
                ),
                const SizedBox(height: 12),
                const Text(
                  '可将界面图片导入“物品图”后在这里使用。图片将铺满对话框或按钮。',
                  style: TextStyle(fontSize: 12, color: secondaryInk),
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
                project.dialogueSkin = dialogue;
                project.choiceSkin = choice;
                _changed();
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
    child: CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
            _save(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: '保存并退出',
              onPressed: saving ? null : _leave,
              icon: const Icon(Icons.arrow_back),
            ),
            title: InkWell(
              onTap: () async {
                final name = await askText(
                  context,
                  '作品名称',
                  initial: project.name,
                );
                if (name != null) {
                  project.name = name;
                  _changed();
                }
              },
              child: Text(
                '${project.name}${dirty ? ' *' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            actions: [
              IconButton(
                tooltip: '打开 / 新建项目',
                onPressed: saving ? null : _openProject,
                icon: const Icon(Icons.folder_open),
              ),
              IconButton(
                tooltip: '公用界面素材',
                onPressed: _skins,
                icon: const Icon(Icons.palette_outlined),
              ),
              IconButton(
                tooltip: '检查流程',
                onPressed: _check,
                icon: const Icon(Icons.fact_check_outlined),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PlayerPage(
                        project: project.copy(),
                        store: widget.store,
                        settings: widget.settings,
                        preview: true,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.play_arrow),
                label: const Text('测试运行'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: saving ? null : _publish,
                icon: const Icon(Icons.auto_awesome_outlined),
                label: const Text('创建游戏'),
              ),
              const SizedBox(width: 16),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: GraphCanvas(
                        key: canvas,
                        project: project,
                        selectedId: selectedId,
                        onSelect: (id) => setState(() {
                          selectedId = id;
                          inspectorOpen = true;
                        }),
                        onChanged: _changed,
                        onOpen: _open,
                        onContext: _context,
                      ),
                    ),
                    Positioned(
                      top: 16,
                      left: 16,
                      child: toolsOpen
                          ? Panel(
                              title: '节点工具栏',
                              onClose: () => setState(() => toolsOpen = false),
                              child: Column(
                                children: [
                                  for (final type in [
                                    StoryNodeType.event,
                                    StoryNodeType.choice,
                                    StoryNodeType.ending,
                                    StoryNodeType.random,
                                  ])
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: Draggable<StoryNodeType>(
                                        data: type,
                                        feedback: Material(
                                          color: Colors.transparent,
                                          child: Chip(
                                            avatar: Icon(type.icon),
                                            label: Text(type.label),
                                          ),
                                        ),
                                        child: ListTile(
                                          dense: true,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: memoryRadius,
                                          ),
                                          tileColor: surface,
                                          leading: Icon(
                                            type.icon,
                                            color: type.color,
                                            size: 20,
                                          ),
                                          title: Text(type.label),
                                          onTap: () =>
                                              canvas.currentState?.add(type),
                                        ),
                                      ),
                                    ),
                                  const Text(
                                    '拖到画布或点击添加',
                                    style: TextStyle(
                                      color: secondaryInk,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : _restore(
                              '节点工具栏',
                              Icons.widgets_outlined,
                              () => setState(() => toolsOpen = true),
                            ),
                    ),
                    Positioned(
                      left: 16,
                      bottom: 16,
                      child: filesOpen
                          ? Panel(
                              title: '项目操作',
                              onClose: () => setState(() => filesOpen = false),
                              child: Column(
                                children: [
                                  ListTile(
                                    dense: true,
                                    leading: const Icon(
                                      Icons.drive_folder_upload_outlined,
                                      color: accent,
                                    ),
                                    title: Text(
                                      '导入素材 (${project.assets.length})',
                                    ),
                                    onTap: _assets,
                                  ),
                                  ListTile(
                                    dense: true,
                                    leading: const Icon(
                                      Icons.save_outlined,
                                      color: accent,
                                    ),
                                    title: const Text('保存'),
                                    onTap: saving ? null : () => _save(),
                                  ),
                                  ListTile(
                                    dense: true,
                                    leading: const Icon(
                                      Icons.exit_to_app,
                                      color: accent,
                                    ),
                                    title: const Text('保存并退出'),
                                    onTap: saving ? null : _leave,
                                  ),
                                ],
                              ),
                            )
                          : _restore(
                              '项目操作',
                              Icons.folder_outlined,
                              () => setState(() => filesOpen = true),
                            ),
                    ),
                    Positioned(
                      top: 16,
                      right: 16,
                      child: peopleOpen
                          ? Panel(
                              title: '人物',
                              width: 245,
                              onClose: () => setState(() => peopleOpen = false),
                              child: Column(
                                children: [
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxHeight: 150,
                                    ),
                                    child: SingleChildScrollView(
                                      child: Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: project.characters
                                            .map(
                                              (name) => ActionChip(
                                                label: Text(name),
                                                tooltip: '点击重命名',
                                                onPressed: () =>
                                                    _person(old: name),
                                              ),
                                            )
                                            .toList(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      onPressed: _person,
                                      icon: const Icon(
                                        Icons.person_add_alt,
                                        size: 17,
                                      ),
                                      label: const Text('创建人物'),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : _restore(
                              '人物',
                              Icons.people_outline,
                              () => setState(() => peopleOpen = true),
                            ),
                    ),
                    if (inspectorOpen && selected != null)
                      Positioned(right: 16, bottom: 16, child: _inspector()),
                    Positioned(
                      bottom: 16,
                      left: 248,
                      child: Row(
                        children: [
                          _restore(
                            '回到开幕',
                            Icons.home_outlined,
                            () => canvas.currentState?.centerOn(
                              project.nodeById(project.startNodeId)!,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _restore(
                            '查看全图',
                            Icons.fit_screen,
                            () => canvas.currentState?.fit(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                color: surface,
                child: Row(
                  children: [
                    Icon(
                      saving
                          ? Icons.sync
                          : dirty
                          ? Icons.circle_outlined
                          : Icons.check_circle_outline,
                      size: 14,
                      color: accent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        saving ? '正在保存…' : status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                    Text(
                      '${project.nodes.length} 个节点 · ${project.characters.length} 位人物',
                      style: const TextStyle(fontSize: 11, color: secondaryInk),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  Widget _restore(String title, IconData icon, VoidCallback onTap) => Material(
    color: surface,
    elevation: 0,
    shape: const RoundedRectangleBorder(
      borderRadius: memoryRadius,
      side: BorderSide(color: hairline),
    ),
    child: IconButton(
      tooltip: title,
      onPressed: onTap,
      icon: Icon(icon, color: accent),
    ),
  );
  Widget _inspector() {
    final node = selected!;
    return Panel(
      title: node.type == StoryNodeType.choice
          ? '选项 #${node.choiceNumber}'
          : node.type.label,
      width: 265,
      onClose: () => setState(() => inspectorOpen = false),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: (MediaQuery.sizeOf(context).height * .32).clamp(100, 290),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                node.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => _open(node),
                child: Text(
                  node.type == StoryNodeType.start
                      ? '编辑开幕画面'
                      : node.type == StoryNodeType.choice
                      ? '编辑共同提示'
                      : '编辑剧情与演出',
                ),
              ),
              if (node.type == StoryNodeType.choice)
                TextButton(
                  onPressed: () => _conditions(node),
                  child: Text('出现条件：${node.requiredChoices.length} 个编号'),
                ),
              if (node.type != StoryNodeType.ending) ...[
                const Divider(),
                const Text(
                  '后续连线',
                  style: TextStyle(fontSize: 11, color: secondaryInk),
                ),
                if (node.outgoing.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('尚未连接', style: TextStyle(fontSize: 12)),
                  ),
                ...node.outgoing.map(
                  (id) => Row(
                    children: [
                      Expanded(
                        child: Text(
                          '→ ${project.nodeById(id)?.title ?? '目标已删除'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      IconButton(
                        tooltip: '移除连线',
                        onPressed: () {
                          node.outgoing.remove(id);
                          _changed();
                        },
                        icon: const Icon(Icons.close, size: 16),
                      ),
                    ],
                  ),
                ),
                DropdownButton<String>(
                  hint: const Text('选择节点建立连线', style: TextStyle(fontSize: 12)),
                  isExpanded: true,
                  value: null,
                  items: project.nodes
                      .where((n) => project.connectionError(node, n) == null)
                      .map(
                        (n) => DropdownMenuItem(
                          value: n.id,
                          child: Text(
                            '${n.type.label} · ${n.title}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (id) {
                    if (id != null) {
                      project.connect(node.id, id);
                      _changed();
                    }
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
