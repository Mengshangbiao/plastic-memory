import 'dart:math' as math;

import 'package:flutter/material.dart';

const _pink = Color(0xFFEFA6BE);
const _deepPink = Color(0xFFD96A93);
const _ink = Color(0xFF47323D);
const _paper = Color(0xFFFFF7FA);
const _softPink = Color(0xFFF6DCE5);
const _violet = Color(0xFF8E6BA8);

void main() => runApp(const PlasticMemoryApp());

enum StoryNodeType { start, event, choice, random, ending }

extension StoryNodeTypeLabel on StoryNodeType {
  String get label => switch (this) {
    StoryNodeType.start => '开幕',
    StoryNodeType.event => '事件',
    StoryNodeType.choice => '选项',
    StoryNodeType.random => '乱数选择',
    StoryNodeType.ending => '结局',
  };

  IconData get icon => switch (this) {
    StoryNodeType.start => Icons.play_circle_outline_rounded,
    StoryNodeType.event => Icons.chat_bubble_outline_rounded,
    StoryNodeType.choice => Icons.alt_route_rounded,
    StoryNodeType.random => Icons.shuffle_rounded,
    StoryNodeType.ending => Icons.flag_outlined,
  };
}

class DialogueLine {
  DialogueLine({
    required this.id,
    required this.speaker,
    required this.text,
    this.voiceAsset = '',
    this.textSpeed = 42,
    this.textSize = 22,
    this.bgmMode = 'inherit',
    this.bgmAsset = '',
  });
  final String id;
  String speaker;
  String text;
  String voiceAsset;
  double textSpeed;
  double textSize;
  String bgmMode;
  String bgmAsset;
}

class ChoiceOption {
  ChoiceOption({
    required this.id,
    required this.text,
    this.conditionKey = '',
    this.targetNodeId = '',
  });
  final String id;
  String text;
  String conditionKey;
  String targetNodeId;
}

class StoryNode {
  StoryNode({
    required this.id,
    required this.type,
    required this.title,
    required this.position,
    this.dialogue = const [],
    this.choices = const [],
    this.outgoing = const [],
    this.backgroundAsset = '',
    this.backgroundBlur = false,
    this.bgmAsset = '',
  });
  final String id;
  final StoryNodeType type;
  String title;
  Offset position;
  List<DialogueLine> dialogue;
  List<ChoiceOption> choices;
  List<String> outgoing;
  String backgroundAsset;
  bool backgroundBlur;
  String bgmAsset;

  List<String> get allOutgoing => type == StoryNodeType.choice
      ? choices
            .map((choice) => choice.targetNodeId)
            .where((target) => target.isNotEmpty)
            .toList()
      : outgoing;
}

class ProjectModel {
  ProjectModel({
    required this.id,
    required this.name,
    required this.nodes,
    required this.startNodeId,
    this.characters = const ['旁白', '雨宫澪', '白石遥'],
    this.variables = const {},
  });
  final String id;
  String name;
  List<StoryNode> nodes;
  String startNodeId;
  List<String> characters;
  Map<String, bool> variables;

  StoryNode? nodeById(String id) {
    for (final node in nodes) {
      if (node.id == id) return node;
    }
    return null;
  }

  static ProjectModel demo() {
    final start = StoryNode(
      id: 'start',
      type: StoryNodeType.start,
      title: '开幕',
      position: const Offset(420, 280),
      outgoing: ['intro'],
    );
    final intro = StoryNode(
      id: 'intro',
      type: StoryNodeType.event,
      title: '樱花树下',
      position: const Offset(700, 280),
      backgroundAsset: '背景图 / 校园樱花路',
      dialogue: [
        DialogueLine(
          id: 'line-1',
          speaker: '旁白',
          text: '春天的风吹过校园，记忆像花瓣一样落在掌心。',
        ),
        DialogueLine(id: 'line-2', speaker: '雨宫澪', text: '你还记得我们第一次见面的地方吗？'),
      ],
      outgoing: ['choice'],
    );
    final choice = StoryNode(
      id: 'choice',
      type: StoryNodeType.choice,
      title: '第一次选择',
      position: const Offset(990, 280),
      dialogue: [
        DialogueLine(id: 'choice-line', speaker: '雨宫澪', text: '你想怎样回答？'),
      ],
      choices: [
        ChoiceOption(id: 'choice-a', text: '我记得。', targetNodeId: 'good-end'),
        ChoiceOption(
          id: 'choice-b',
          text: '我想再听你说一次。',
          targetNodeId: 'soft-end',
        ),
      ],
    );
    final good = StoryNode(
      id: 'good-end',
      type: StoryNodeType.ending,
      title: '晴朗结局',
      position: const Offset(1280, 150),
      dialogue: [
        DialogueLine(id: 'end-a', speaker: '旁白', text: '有些回忆不会褪色，它们只是等待再次被想起。'),
      ],
    );
    final soft = StoryNode(
      id: 'soft-end',
      type: StoryNodeType.ending,
      title: '温柔结局',
      position: const Offset(1280, 410),
      dialogue: [
        DialogueLine(id: 'end-b', speaker: '雨宫澪', text: '那就从现在开始，把新的回忆交给我吧。'),
      ],
    );
    return ProjectModel(
      id: 'demo-project',
      name: '樱花树下的约定',
      nodes: [start, intro, choice, good, soft],
      startNodeId: start.id,
    );
  }
}

enum AppScreen { home, library, settings, editor, player }

class PlasticMemoryApp extends StatefulWidget {
  const PlasticMemoryApp({super.key});
  @override
  State<PlasticMemoryApp> createState() => _PlasticMemoryAppState();
}

class _PlasticMemoryAppState extends State<PlasticMemoryApp> {
  final projects = <ProjectModel>[ProjectModel.demo()];
  AppScreen screen = AppScreen.home;
  ProjectModel? activeProject;
  bool editingLibrary = true;

  void openLibrary(bool editing) => setState(() {
    editingLibrary = editing;
    screen = AppScreen.library;
  });
  void openEditor(ProjectModel project) => setState(() {
    activeProject = project;
    screen = AppScreen.editor;
  });
  void openPlayer(ProjectModel project) => setState(() {
    activeProject = project;
    screen = AppScreen.player;
  });
  void home() => setState(() {
    screen = AppScreen.home;
    activeProject = null;
  });

  void createProject(String name) {
    final id = 'project-${DateTime.now().microsecondsSinceEpoch}';
    final startId = 'start-$id';
    final project = ProjectModel(
      id: id,
      name: name,
      startNodeId: startId,
      nodes: [
        StoryNode(
          id: startId,
          type: StoryNodeType.start,
          title: '开幕',
          position: const Offset(420, 300),
        ),
      ],
    );
    projects.add(project);
    openEditor(project);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '可塑性记忆',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: _paper,
        colorScheme: ColorScheme.fromSeed(seedColor: _deepPink).copyWith(
          primary: _deepPink,
          onPrimary: Colors.white,
          surface: Colors.white,
          onSurface: _ink,
        ),
        fontFamily: 'Microsoft YaHei',
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _softPink),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _deepPink, width: 2),
          ),
        ),
      ),
      home: switch (screen) {
        AppScreen.home => HomePage(
          onLibrary: () => openLibrary(false),
          onCreate: () => openLibrary(true),
          onSettings: () => setState(() => screen = AppScreen.settings),
          onExit: () => ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('桌面版将由窗口关闭操作退出。'))),
        ),
        AppScreen.library => LibraryPage(
          projects: projects,
          editing: editingLibrary,
          onBack: home,
          onCreate: _showCreateDialog,
          onOpen: editingLibrary ? openEditor : openPlayer,
        ),
        AppScreen.settings => SettingsPage(onBack: home),
        AppScreen.editor => EditorPage(
          project: activeProject!,
          onBack: home,
          onPlay: () => openPlayer(activeProject!),
        ),
        AppScreen.player => PlayerPage(project: activeProject!, onBack: home),
      },
    );
  }

  void _showCreateDialog() {
    final controller = TextEditingController(text: '未命名回忆');
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('创造一段新回忆'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '项目名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(context);
              createProject(name);
            },
            child: const Text('开始创作'),
          ),
        ],
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.onLibrary,
    required this.onCreate,
    required this.onSettings,
    required this.onExit,
  });
  final VoidCallback onLibrary;
  final VoidCallback onCreate;
  final VoidCallback onSettings;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [_paper, const Color(0xFFFFE8F0), _softPink],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
          Positioned(
            top: -110,
            right: -80,
            child: _FlowerCloud(color: _pink.withOpacity(.36), size: 260),
          ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      '可塑性记忆',
                      style: TextStyle(
                        color: _ink,
                        fontSize: 52,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 8,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '可视化 Galgame 创作工具',
                      style: TextStyle(
                        color: _ink.withOpacity(.72),
                        fontSize: 16,
                        letterSpacing: 3,
                      ),
                    ),
                    const SizedBox(height: 48),
                    _HomeButton(
                      icon: Icons.auto_stories_outlined,
                      label: '纷乱回忆',
                      hint: '打开已经完成的故事',
                      onPressed: onLibrary,
                    ),
                    _HomeButton(
                      icon: Icons.edit_note_rounded,
                      label: '创造回忆',
                      hint: '用流程图编写新的故事',
                      onPressed: onCreate,
                    ),
                    _HomeButton(
                      icon: Icons.tune_rounded,
                      label: '设置',
                      hint: '音量、文字与窗口选项',
                      onPressed: onSettings,
                    ),
                    _HomeButton(
                      icon: Icons.logout_rounded,
                      label: '退出',
                      hint: '结束当前会话',
                      onPressed: onExit,
                      muted: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Positioned(
            bottom: 22,
            left: 0,
            right: 0,
            child: Text(
              '让每一段回忆，都拥有重新塑形的机会',
              textAlign: TextAlign.center,
              style: TextStyle(color: _ink, fontSize: 12, letterSpacing: 2),
            ),
          ),
        ],
      ),
    );
  }
}

class _FlowerCloud extends StatelessWidget {
  const _FlowerCloud({required this.color, required this.size});
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: color,
      boxShadow: [BoxShadow(color: color, blurRadius: 70, spreadRadius: 30)],
    ),
  );
}

class _HomeButton extends StatelessWidget {
  const _HomeButton({
    required this.icon,
    required this.label,
    required this.hint,
    required this.onPressed,
    this.muted = false,
  });
  final IconData icon;
  final String label;
  final String hint;
  final VoidCallback onPressed;
  final bool muted;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: muted
            ? Colors.white.withOpacity(.5)
            : Colors.white.withOpacity(.84),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: muted ? _ink.withOpacity(.55) : _deepPink,
                  size: 28,
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        hint,
                        style: TextStyle(
                          color: _ink.withOpacity(.55),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: _ink.withOpacity(.35)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class LibraryPage extends StatelessWidget {
  const LibraryPage({
    super.key,
    required this.projects,
    required this.editing,
    required this.onBack,
    required this.onCreate,
    required this.onOpen,
  });
  final List<ProjectModel> projects;
  final bool editing;
  final VoidCallback onBack;
  final VoidCallback onCreate;
  final ValueChanged<ProjectModel> onOpen;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        onPressed: onBack,
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      title: Text(editing ? '创造回忆' : '纷乱回忆'),
      actions: [
        if (editing)
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add_rounded),
              label: const Text('新建项目'),
            ),
          ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(28),
      children: [
        Text(
          editing ? '选择一段回忆继续创作' : '选择一段回忆开始游玩',
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          '项目会保存流程、对白、人物与演出设置。',
          style: TextStyle(color: _ink.withOpacity(.62)),
        ),
        const SizedBox(height: 24),
        ...projects.map(
          (project) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _ProjectCard(
              project: project,
              editing: editing,
              onOpen: () => onOpen(project),
            ),
          ),
        ),
      ],
    ),
  );
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    required this.project,
    required this.editing,
    required this.onOpen,
  });
  final ProjectModel project;
  final bool editing;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    color: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            width: 82,
            height: 82,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                colors: [_pink, _deepPink],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Icon(
              Icons.auto_stories_rounded,
              color: Colors.white,
              size: 36,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  project.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${project.nodes.length} 个剧情节点 · ${project.characters.length} 位角色',
                  style: TextStyle(color: _ink.withOpacity(.58)),
                ),
                const SizedBox(height: 8),
                Text(
                  editing ? '最近编辑：当前会话' : '可从上次保存的位置继续游玩',
                  style: TextStyle(color: _ink.withOpacity(.45), fontSize: 12),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: onOpen,
            icon: Icon(editing ? Icons.edit_rounded : Icons.play_arrow_rounded),
            label: Text(editing ? '编辑' : '游玩'),
          ),
        ],
      ),
    ),
  );
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.onBack});
  final VoidCallback onBack;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  double master = .85,
      bgm = .72,
      voice = .9,
      sfx = .75,
      textSpeed = .55,
      fontScale = 1;
  bool fullscreen = false, skipRead = false, autoPlay = false;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: widget.onBack,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('设置'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(28),
        children: [
          _SettingsSection(
            title: '音量',
            icon: Icons.volume_up_outlined,
            children: [
              _SliderRow(
                label: '总音量',
                value: master,
                onChanged: (v) => setState(() => master = v),
              ),
              _SliderRow(
                label: '背景音乐',
                value: bgm,
                onChanged: (v) => setState(() => bgm = v),
              ),
              _SliderRow(
                label: '人物语音',
                value: voice,
                onChanged: (v) => setState(() => voice = v),
              ),
              _SliderRow(
                label: '特殊音效',
                value: sfx,
                onChanged: (v) => setState(() => sfx = v),
              ),
            ],
          ),
          _SettingsSection(
            title: '文字与演出',
            icon: Icons.text_fields_rounded,
            children: [
              _SliderRow(
                label: '文字速度',
                value: textSpeed,
                onChanged: (v) => setState(() => textSpeed = v),
              ),
              _SliderRow(
                label: '文字大小',
                value: fontScale,
                min: .8,
                max: 1.4,
                onChanged: (v) => setState(() => fontScale = v),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('自动播放'),
                value: autoPlay,
                onChanged: (v) => setState(() => autoPlay = v),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('跳过已读文本'),
                value: skipRead,
                onChanged: (v) => setState(() => skipRead = v),
              ),
            ],
          ),
          _SettingsSection(
            title: '显示',
            icon: Icons.desktop_windows_outlined,
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('启动时全屏'),
                value: fullscreen,
                onChanged: (v) => setState(() => fullscreen = v),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.icon,
    required this.children,
  });
  final String title;
  final IconData icon;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 18),
    elevation: 0,
    color: Colors.white,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _deepPink),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                  color: _ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    ),
  );
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
  });
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(width: 90, child: Text(label)),
      Expanded(
        child: Slider(value: value, min: min, max: max, onChanged: onChanged),
      ),
      SizedBox(
        width: 48,
        child: Text('${(value * 100).round()}%', textAlign: TextAlign.right),
      ),
    ],
  );
}

class EditorPage extends StatefulWidget {
  const EditorPage({
    super.key,
    required this.project,
    required this.onBack,
    required this.onPlay,
  });
  final ProjectModel project;
  final VoidCallback onBack;
  final VoidCallback onPlay;
  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  late ProjectModel project;
  String? selectedNodeId;
  String? statusMessage;
  bool showPalette = true;
  @override
  void initState() {
    super.initState();
    project = widget.project;
    selectedNodeId = project.startNodeId;
  }

  StoryNode? get selectedNode =>
      selectedNodeId == null ? null : project.nodeById(selectedNodeId!);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        onPressed: widget.onBack,
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      title: Row(
        children: [
          const Icon(Icons.auto_stories_rounded, color: _deepPink),
          const SizedBox(width: 10),
          Text(project.name),
        ],
      ),
      actions: [
        if (statusMessage != null)
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(
              child: Text(
                statusMessage!,
                style: TextStyle(color: _ink.withOpacity(.55), fontSize: 12),
              ),
            ),
          ),
        IconButton(
          onPressed: _validateGraph,
          tooltip: '检查流程',
          icon: const Icon(Icons.fact_check_outlined),
        ),
        OutlinedButton.icon(
          onPressed: widget.onPlay,
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('测试运行'),
        ),
        const SizedBox(width: 10),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save_outlined),
          label: const Text('保存'),
        ),
        const SizedBox(width: 16),
      ],
    ),
    body: Column(
      children: [
        Expanded(
          child: Row(
            children: [
              if (showPalette)
                SizedBox(width: 170, child: NodePalette(onAdd: _addNode)),
              Expanded(
                child: GraphCanvas(
                  project: project,
                  selectedNodeId: selectedNodeId,
                  onSelect: (id) => setState(() => selectedNodeId = id),
                  onMove: _moveNode,
                  onConnect: _connectNodes,
                  onAdd: _addNodeAt,
                ),
              ),
              SizedBox(
                width: 360,
                child: NodeInspector(
                  project: project,
                  node: selectedNode,
                  onChanged: _refresh,
                  onDelete: _deleteSelected,
                ),
              ),
            ],
          ),
        ),
        Container(
          height: 42,
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              IconButton(
                onPressed: () => setState(() => showPalette = !showPalette),
                icon: Icon(
                  showPalette
                      ? Icons.view_sidebar_rounded
                      : Icons.view_sidebar_outlined,
                ),
              ),
              const Text(
                '拖拽节点右侧圆点连接到其他节点左侧圆点；右侧面板编辑节点内容。',
                style: TextStyle(fontSize: 12, color: _ink),
              ),
              const Spacer(),
              Text(
                '${project.nodes.length} 个节点',
                style: TextStyle(fontSize: 12, color: _ink.withOpacity(.5)),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  void _refresh() => setState(() {});
  void _save() {
    setState(() => statusMessage = '已保存到当前会话');
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => statusMessage = null);
    });
  }

  void _moveNode(String id, Offset delta) {
    final node = project.nodeById(id);
    if (node == null) return;
    setState(() => node.position = node.position + delta);
  }

  void _addNode(StoryNodeType type) => _addNodeAt(type, const Offset(560, 320));
  void _addNodeAt(StoryNodeType type, Offset position) {
    final id = '${type.name}-${DateTime.now().microsecondsSinceEpoch}';
    final node = StoryNode(
      id: id,
      type: type,
      title: type.label,
      position: position,
    );
    if (type == StoryNodeType.event)
      node.dialogue = [
        DialogueLine(id: 'line-$id', speaker: '旁白', text: '在这里写下新的对白。'),
      ];
    if (type == StoryNodeType.choice) {
      node.dialogue = [
        DialogueLine(id: 'line-$id', speaker: '旁白', text: '在这里写下选项前的提示。'),
      ];
      node.choices = [ChoiceOption(id: 'choice-$id', text: '第一个选择')];
    }
    setState(() {
      project.nodes.add(node);
      selectedNodeId = id;
    });
  }

  void _deleteSelected() {
    final node = selectedNode;
    if (node == null || node.type == StoryNodeType.start) return;
    setState(() {
      project.nodes.removeWhere((item) => item.id == node.id);
      for (final other in project.nodes) {
        other.outgoing.remove(node.id);
        for (final choice in other.choices) {
          if (choice.targetNodeId == node.id) choice.targetNodeId = '';
        }
      }
      selectedNodeId = project.startNodeId;
    });
  }

  void _connectNodes(String sourceId, String targetId) {
    final source = project.nodeById(sourceId);
    final target = project.nodeById(targetId);
    if (source == null || target == null || source.id == target.id) return;
    String? error;
    if (target.type == StoryNodeType.start) error = '开幕不能作为其他节点的目标。';
    if (source.type == StoryNodeType.ending) error = '结局节点不能继续连接。';
    if (source.type == StoryNodeType.start &&
        target.type != StoryNodeType.event &&
        target.type != StoryNodeType.random)
      error = '开幕只能连接事件或乱数选择。';
    if (source.type == StoryNodeType.random &&
        target.type != StoryNodeType.event)
      error = '乱数选择首版只连接事件节点。';
    if (source.type == StoryNodeType.event && source.outgoing.isNotEmpty)
      error = '事件节点只能有一个出口。';
    if (error != null) {
      setState(() => statusMessage = error);
      return;
    }
    setState(() {
      if (source.type == StoryNodeType.choice) {
        ChoiceOption? empty;
        for (final choice in source.choices) {
          if (choice.targetNodeId.isEmpty) {
            empty = choice;
            break;
          }
        }
        if (empty != null)
          empty!.targetNodeId = target.id;
        else
          source.choices.add(
            ChoiceOption(
              id: 'choice-${DateTime.now().microsecondsSinceEpoch}',
              text: '新的选择',
              targetNodeId: target.id,
            ),
          );
      } else if (!source.outgoing.contains(target.id))
        source.outgoing.add(target.id);
      statusMessage = '已连接 ${source.title} → ${target.title}';
    });
  }

  void _validateGraph() {
    final errors = <String>[];
    final start = project.nodeById(project.startNodeId);
    if (start == null) errors.add('缺少开幕节点。');
    if (start != null && start.allOutgoing.isEmpty) errors.add('开幕还没有连接下一个节点。');
    for (final node in project.nodes) {
      if (node.type != StoryNodeType.ending && node.allOutgoing.isEmpty)
        errors.add('${node.title} 没有出口。');
      if (node.type == StoryNodeType.event && node.allOutgoing.length > 1)
        errors.add('${node.title} 的出口超过一个。');
      if (node.type == StoryNodeType.random && node.allOutgoing.length < 2)
        errors.add('${node.title} 至少需要两个出口。');
      for (final targetId in node.allOutgoing) {
        if (project.nodeById(targetId) == null)
          errors.add('${node.title} 连接到了不存在的节点。');
      }
    }
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(errors.isEmpty ? '流程检查通过' : '发现 ${errors.length} 个问题'),
        content: SizedBox(
          width: 420,
          child: errors.isEmpty
              ? const Text('当前流程可以进入测试运行。')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: errors
                      .map(
                        (error) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text('• $error'),
                        ),
                      )
                      .toList(),
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
  }
}

class NodePalette extends StatelessWidget {
  const NodePalette({super.key, required this.onAdd});
  final ValueChanged<StoryNodeType> onAdd;
  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xFFFFF0F5),
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '节点工具栏',
          style: TextStyle(color: _ink, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          '拖到画布，或点击添加',
          style: TextStyle(color: _ink.withOpacity(.55), fontSize: 11),
        ),
        const SizedBox(height: 14),
        ...StoryNodeType.values
            .where((type) => type != StoryNodeType.start)
            .map(
              (type) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Draggable<StoryNodeType>(
                  data: type,
                  feedback: Material(
                    color: Colors.transparent,
                    child: _PaletteTile(type: type, compact: true),
                  ),
                  childWhenDragging: Opacity(
                    opacity: .35,
                    child: _PaletteTile(type: type, onTap: () => onAdd(type)),
                  ),
                  child: _PaletteTile(type: type, onTap: () => onAdd(type)),
                ),
              ),
            ),
        const Spacer(),
        const Divider(),
        Text(
          '连接规则',
          style: TextStyle(
            color: _ink,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '开幕 → 事件 / 乱数\n事件 → 一个节点\n选项 → 每个选项一个节点\n结局 → 无出口',
          style: TextStyle(
            color: _ink.withOpacity(.58),
            fontSize: 11,
            height: 1.7,
          ),
        ),
      ],
    ),
  );
}

class _PaletteTile extends StatelessWidget {
  const _PaletteTile({required this.type, this.onTap, this.compact = false});
  final StoryNodeType type;
  final VoidCallback? onTap;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final color = _nodeColor(type);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: compact ? 150 : double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(.45)),
        ),
        child: Row(
          children: [
            Icon(type.icon, color: color, size: 20),
            const SizedBox(width: 9),
            Text(
              type.label,
              style: const TextStyle(
                color: _ink,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GraphCanvas extends StatelessWidget {
  const GraphCanvas({
    super.key,
    required this.project,
    required this.selectedNodeId,
    required this.onSelect,
    required this.onMove,
    required this.onConnect,
    required this.onAdd,
  });
  final ProjectModel project;
  final String? selectedNodeId;
  final ValueChanged<String> onSelect;
  final void Function(String id, Offset delta) onMove;
  final void Function(String sourceId, String targetId) onConnect;
  final void Function(StoryNodeType type, Offset position) onAdd;
  static const nodeSize = Size(184, 96);
  @override
  Widget build(BuildContext context) {
    return DragTarget<StoryNodeType>(
      onAcceptWithDetails: (details) =>
          onAdd(details.data, const Offset(560, 300)),
      builder: (context, candidates, rejected) {
        return Container(
          color: const Color(0xFFF9F4F7),
          child: InteractiveViewer(
            constrained: false,
            boundaryMargin: const EdgeInsets.all(500),
            minScale: .55,
            maxScale: 1.7,
            child: SizedBox(
              width: 1700,
              height: 950,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(painter: GraphPainter(project.nodes)),
                  ),
                  ...project.nodes.map((node) => _nodeCard(context, node)),
                  if (candidates.isNotEmpty)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: ColoredBox(color: _pink.withOpacity(.12)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _nodeCard(BuildContext context, StoryNode node) => Positioned(
    left: node.position.dx,
    top: node.position.dy,
    width: nodeSize.width,
    height: nodeSize.height,
    child: GestureDetector(
      onTap: () => onSelect(node.id),
      onPanUpdate: (details) => onMove(node.id, details.delta),
      child: _GraphNodeCard(
        node: node,
        selected: selectedNodeId == node.id,
        onConnect: onConnect,
      ),
    ),
  );
}

class _GraphNodeCard extends StatelessWidget {
  const _GraphNodeCard({
    required this.node,
    required this.selected,
    required this.onConnect,
  });
  final StoryNode node;
  final bool selected;
  final void Function(String sourceId, String targetId) onConnect;
  @override
  Widget build(BuildContext context) {
    final color = _nodeColor(node.type);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? _deepPink : color.withOpacity(.55),
              width: selected ? 3 : 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(.14),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(node.type.icon, color: color, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      node.type.label,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  if (node.type != StoryNodeType.start &&
                      node.type != StoryNodeType.ending)
                    Text(
                      '${node.allOutgoing.length}',
                      style: TextStyle(
                        color: _ink.withOpacity(.4),
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 9),
              Text(
                node.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _nodeSummary(node),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: _ink.withOpacity(.52), fontSize: 11),
              ),
            ],
          ),
        ),
        Positioned(
          left: -9,
          top: 38,
          child: DragTarget<String>(
            onAccept: (sourceId) => onConnect(sourceId, node.id),
            builder: (context, candidate, rejected) =>
                _ConnectionHandle(color: color, active: candidate.isNotEmpty),
          ),
        ),
        if (node.type != StoryNodeType.ending)
          Positioned(
            right: -9,
            top: 38,
            child: Draggable<String>(
              data: node.id,
              feedback: _ConnectionHandle(color: color, active: true),
              childWhenDragging: _ConnectionHandle(
                color: color.withOpacity(.35),
                active: false,
              ),
              child: _ConnectionHandle(color: color, active: false),
            ),
          ),
      ],
    );
  }
}

class _ConnectionHandle extends StatelessWidget {
  const _ConnectionHandle({required this.color, required this.active});
  final Color color;
  final bool active;
  @override
  Widget build(BuildContext context) => Container(
    width: 18,
    height: 18,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: active ? color : Colors.white,
      border: Border.all(color: color, width: 2),
    ),
  );
}

class GraphPainter extends CustomPainter {
  GraphPainter(this.nodes);
  final List<StoryNode> nodes;
  @override
  void paint(Canvas canvas, Size size) {
    final map = {for (final node in nodes) node.id: node};
    final paint = Paint()
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;
    for (final source in nodes) {
      for (final targetId in source.allOutgoing) {
        final target = map[targetId];
        if (target == null) continue;
        paint.color = _nodeColor(source.type).withOpacity(.65);
        final start = Offset(
          source.position.dx + GraphCanvas.nodeSize.width,
          source.position.dy + 48,
        );
        final end = Offset(target.position.dx, target.position.dy + 48);
        final path = Path()..moveTo(start.dx, start.dy);
        final bend = (end.dx - start.dx).abs() * .45;
        path.cubicTo(
          start.dx + bend,
          start.dy,
          end.dx - bend,
          end.dy,
          end.dx,
          end.dy,
        );
        canvas.drawPath(path, paint);
        final direction = (end - start).direction;
        final tip = end;
        final left =
            tip -
            Offset(
              math.cos(direction - .55) * 10,
              math.sin(direction - .55) * 10,
            );
        final right =
            tip -
            Offset(
              math.cos(direction + .55) * 10,
              math.sin(direction + .55) * 10,
            );
        final arrow = Paint()
          ..color = paint.color
          ..style = PaintingStyle.fill;
        canvas.drawPath(
          Path()
            ..moveTo(tip.dx, tip.dy)
            ..lineTo(left.dx, left.dy)
            ..lineTo(right.dx, right.dy)
            ..close(),
          arrow,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant GraphPainter oldDelegate) => true;
}

class NodeInspector extends StatelessWidget {
  const NodeInspector({
    super.key,
    required this.project,
    required this.node,
    required this.onChanged,
    required this.onDelete,
  });
  final ProjectModel project;
  final StoryNode? node;
  final VoidCallback onChanged;
  final VoidCallback onDelete;
  @override
  Widget build(BuildContext context) {
    if (node == null)
      return Container(
        color: Colors.white,
        padding: const EdgeInsets.all(22),
        child: Center(
          child: Text(
            '选择一个节点开始编辑',
            style: TextStyle(color: _ink.withOpacity(.55)),
          ),
        ),
      );
    return Container(
      color: Colors.white,
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Row(
            children: [
              Icon(node!.type.icon, color: _nodeColor(node!.type)),
              const SizedBox(width: 8),
              Text(
                node!.type.label,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: _ink,
                ),
              ),
              const Spacer(),
              if (node!.type != StoryNodeType.start)
                IconButton(
                  onPressed: onDelete,
                  tooltip: '删除节点',
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
            ],
          ),
          const SizedBox(height: 14),
          TextFormField(
            initialValue: node!.title,
            decoration: const InputDecoration(labelText: '节点名称'),
            onChanged: (value) {
              node!.title = value;
              onChanged();
            },
          ),
          const SizedBox(height: 14),
          if (node!.type == StoryNodeType.event ||
              node!.type == StoryNodeType.ending)
            ..._eventFields(),
          if (node!.type == StoryNodeType.choice) ..._choiceFields(),
          if (node!.type == StoryNodeType.random) ...[
            const _InfoBox(text: '乱数选择会从已连接的事件中随机选择一条路线。'),
            const SizedBox(height: 12),
            _ConnectionsSummary(project: project, node: node!),
          ],
          if (node!.type == StoryNodeType.start)
            const _InfoBox(text: '开幕节点用于进入第一段事件，只能连接事件或乱数选择。'),
        ],
      ),
    );
  }

  List<Widget> _eventFields() => [
    TextFormField(
      initialValue: node!.backgroundAsset,
      decoration: const InputDecoration(
        labelText: '背景图（素材名）',
        prefixIcon: Icon(Icons.image_outlined),
      ),
      onChanged: (value) {
        node!.backgroundAsset = value;
        onChanged();
      },
    ),
    SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      title: const Text('背景模糊'),
      value: node!.backgroundBlur,
      onChanged: (value) {
        node!.backgroundBlur = value;
        onChanged();
      },
    ),
    TextFormField(
      initialValue: node!.bgmAsset,
      decoration: const InputDecoration(
        labelText: '背景音乐（素材名）',
        prefixIcon: Icon(Icons.music_note_outlined),
      ),
      onChanged: (value) {
        node!.bgmAsset = value;
        onChanged();
      },
    ),
    const SizedBox(height: 12),
    Row(
      children: [
        const Text(
          '对白列表',
          style: TextStyle(fontWeight: FontWeight.w800, color: _ink),
        ),
        const Spacer(),
        TextButton.icon(
          onPressed: () {
            node!.dialogue.add(
              DialogueLine(
                id: 'line-${DateTime.now().microsecondsSinceEpoch}',
                speaker: project.characters.first,
                text: '',
              ),
            );
            onChanged();
          },
          icon: const Icon(Icons.add_rounded),
          label: const Text('添加'),
        ),
      ],
    ),
    ...node!.dialogue.asMap().entries.map(
      (entry) => DialogueEditor(
        line: entry.value,
        index: entry.key,
        characters: project.characters,
        onChanged: onChanged,
        onDelete: () {
          node!.dialogue.removeAt(entry.key);
          onChanged();
        },
      ),
    ),
    const SizedBox(height: 12),
    _ConnectionsSummary(project: project, node: node!),
  ];
  List<Widget> _choiceFields() => [
    const _InfoBox(text: '每个选项可以设置出现条件。条件为空时始终显示。'),
    const SizedBox(height: 12),
    Row(
      children: [
        const Text(
          '选项列表',
          style: TextStyle(fontWeight: FontWeight.w800, color: _ink),
        ),
        const Spacer(),
        TextButton.icon(
          onPressed: () {
            node!.choices.add(
              ChoiceOption(
                id: 'choice-${DateTime.now().microsecondsSinceEpoch}',
                text: '新的选择',
              ),
            );
            onChanged();
          },
          icon: const Icon(Icons.add_rounded),
          label: const Text('添加'),
        ),
      ],
    ),
    ...node!.choices.asMap().entries.map(
      (entry) => ChoiceEditor(
        choice: entry.value,
        index: entry.key,
        nodes: project.nodes,
        onChanged: onChanged,
        onDelete: () {
          node!.choices.removeAt(entry.key);
          onChanged();
        },
      ),
    ),
    const SizedBox(height: 12),
    if (node!.dialogue.isNotEmpty)
      DialogueEditor(
        line: node!.dialogue.first,
        index: 0,
        characters: project.characters,
        onChanged: onChanged,
        onDelete: () {},
      ),
  ];
}

class DialogueEditor extends StatelessWidget {
  const DialogueEditor({
    super.key,
    required this.line,
    required this.index,
    required this.characters,
    required this.onChanged,
    required this.onDelete,
  });
  final DialogueLine line;
  final int index;
  final List<String> characters;
  final VoidCallback onChanged;
  final VoidCallback onDelete;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    elevation: 0,
    color: const Color(0xFFFFF8FB),
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                '对白 ${index + 1}',
                style: TextStyle(color: _ink.withOpacity(.58), fontSize: 11),
              ),
              const Spacer(),
              IconButton(
                onPressed: onDelete,
                iconSize: 18,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          DropdownButtonFormField<String>(
            value: line.speaker,
            decoration: const InputDecoration(labelText: '人物'),
            items: characters
                .map(
                  (character) => DropdownMenuItem(
                    value: character,
                    child: Text(character),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              line.speaker = value;
              onChanged();
            },
          ),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: line.text,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(labelText: '文本'),
            onChanged: (value) {
              line.text = value;
              onChanged();
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: line.voiceAsset,
                  decoration: const InputDecoration(labelText: '语音素材'),
                  onChanged: (value) {
                    line.voiceAsset = value;
                    onChanged();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  initialValue: line.bgmAsset,
                  decoration: const InputDecoration(labelText: 'BGM 素材'),
                  onChanged: (value) {
                    line.bgmAsset = value;
                    onChanged();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class ChoiceEditor extends StatelessWidget {
  const ChoiceEditor({
    super.key,
    required this.choice,
    required this.index,
    required this.nodes,
    required this.onChanged,
    required this.onDelete,
  });
  final ChoiceOption choice;
  final int index;
  final List<StoryNode> nodes;
  final VoidCallback onChanged;
  final VoidCallback onDelete;
  @override
  Widget build(BuildContext context) {
    final targets = nodes
        .where(
          (node) =>
              node.type != StoryNodeType.start &&
              node.type != StoryNodeType.choice,
        )
        .toList();
    final targetValue = targets.any((node) => node.id == choice.targetNodeId)
        ? choice.targetNodeId
        : '';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: const Color(0xFFFFF8FB),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Row(
              children: [
                Text(
                  '选项 ${index + 1}',
                  style: TextStyle(color: _ink.withOpacity(.58), fontSize: 11),
                ),
                const Spacer(),
                IconButton(
                  onPressed: onDelete,
                  iconSize: 18,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            TextFormField(
              initialValue: choice.text,
              decoration: const InputDecoration(labelText: '选项文本'),
              onChanged: (value) {
                choice.text = value;
                onChanged();
              },
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: choice.conditionKey,
              decoration: const InputDecoration(labelText: '出现条件变量（可选）'),
              onChanged: (value) {
                choice.conditionKey = value;
                onChanged();
              },
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: targetValue,
              decoration: const InputDecoration(labelText: '连接到'),
              items: [
                const DropdownMenuItem<String>(value: '', child: Text('未连接')),
                ...targets.map(
                  (node) =>
                      DropdownMenuItem(value: node.id, child: Text(node.title)),
                ),
              ],
              onChanged: (value) {
                choice.targetNodeId = value ?? '';
                onChanged();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionsSummary extends StatelessWidget {
  const _ConnectionsSummary({required this.project, required this.node});
  final ProjectModel project;
  final StoryNode node;
  @override
  Widget build(BuildContext context) {
    final targets = node.allOutgoing
        .map((id) => project.nodeById(id)?.title ?? '未知节点')
        .toList();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _softPink.withOpacity(.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.route_outlined, color: _deepPink, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              targets.isEmpty ? '尚未连接后续节点' : '后续：${targets.join('、')}',
              style: TextStyle(color: _ink.withOpacity(.72), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFF5EFF8),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      text,
      style: TextStyle(color: _ink.withOpacity(.7), fontSize: 12, height: 1.5),
    ),
  );
}

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.project, required this.onBack});
  final ProjectModel project;
  final VoidCallback onBack;
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late String currentNodeId;
  int dialogueIndex = 0;
  final variables = <String, bool>{};
  bool reachedEnding = false;
  @override
  void initState() {
    super.initState();
    currentNodeId = widget.project.startNodeId;
    _resolveAutomaticNodes();
  }

  StoryNode? get currentNode => widget.project.nodeById(currentNodeId);
  void _resolveAutomaticNodes() {
    var guard = 0;
    while (guard++ < 30) {
      final node = currentNode;
      if (node == null) return;
      if (node.type == StoryNodeType.start && node.outgoing.isNotEmpty) {
        currentNodeId = node.outgoing.first;
        continue;
      }
      if (node.type == StoryNodeType.random && node.outgoing.isNotEmpty) {
        currentNodeId =
            node.outgoing[math.Random().nextInt(node.outgoing.length)];
        continue;
      }
      break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final node = currentNode;
    if (node == null) return const SizedBox.shrink();
    final line =
        node.dialogue.isNotEmpty && dialogueIndex < node.dialogue.length
        ? node.dialogue[dialogueIndex]
        : null;
    final choices = node.choices
        .where(
          (choice) =>
              choice.conditionKey.isEmpty ||
              variables[choice.conditionKey] == true,
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: widget.onBack,
          icon: const Icon(Icons.close_rounded),
        ),
        title: Text(widget.project.name),
        actions: [
          IconButton(
            onPressed: () => ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('存档系统将在下一阶段接入项目文件。'))),
            icon: const Icon(Icons.save_outlined),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [_violet.withOpacity(.38), _pink.withOpacity(.48), _paper],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Padding(
              padding: const EdgeInsets.all(26),
              child: Column(
                children: [
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(.48),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: Colors.white.withOpacity(.72),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _ink.withOpacity(.12),
                            blurRadius: 24,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Stack(
                        children: [
                          Center(
                            child: Icon(
                              Icons.image_outlined,
                              size: 90,
                              color: Colors.white.withOpacity(.75),
                            ),
                          ),
                          Positioned(
                            top: 20,
                            left: 24,
                            child: Chip(label: Text(node.title)),
                          ),
                          if (node.backgroundAsset.isNotEmpty)
                            Positioned(
                              bottom: 22,
                              left: 24,
                              child: Text(
                                node.backgroundAsset,
                                style: TextStyle(
                                  color: _ink.withOpacity(.5),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (node.type == StoryNodeType.choice) ...[
                    if (line != null) _DialogueBox(line: line),
                    const SizedBox(height: 10),
                    ...choices.map(
                      (choice) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: () => _choose(choice),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(choice.text),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ] else if (reachedEnding ||
                      node.type == StoryNodeType.ending && line == null)
                    _EndingBox(onRestart: _restart)
                  else ...[
                    if (line != null) _DialogueBox(line: line),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: _advance,
                        icon: const Icon(Icons.arrow_forward_rounded),
                        label: Text(line == null ? '继续' : '下一句'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _advance() {
    final node = currentNode;
    if (node == null) return;
    if (dialogueIndex + 1 < node.dialogue.length) {
      setState(() => dialogueIndex++);
      return;
    }
    if (node.type == StoryNodeType.ending) {
      setState(() => reachedEnding = true);
      return;
    }
    if (node.outgoing.isNotEmpty)
      setState(() {
        currentNodeId = node.outgoing.first;
        dialogueIndex = 0;
        _resolveAutomaticNodes();
      });
  }

  void _choose(ChoiceOption choice) {
    variables[choice.id] = true;
    if (choice.conditionKey.isNotEmpty) variables[choice.conditionKey] = true;
    if (choice.targetNodeId.isEmpty) return;
    setState(() {
      currentNodeId = choice.targetNodeId;
      dialogueIndex = 0;
      _resolveAutomaticNodes();
    });
  }

  void _restart() {
    setState(() {
      currentNodeId = widget.project.startNodeId;
      dialogueIndex = 0;
      reachedEnding = false;
      variables.clear();
      _resolveAutomaticNodes();
    });
  }
}

class _DialogueBox extends StatelessWidget {
  const _DialogueBox({required this.line});
  final DialogueLine line;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(20, 15, 20, 18),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(.93),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: _pink.withOpacity(.7)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          line.speaker,
          style: const TextStyle(color: _deepPink, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          line.text.isEmpty ? '（尚未填写文本）' : line.text,
          style: const TextStyle(color: _ink, fontSize: 18, height: 1.55),
        ),
      ],
    ),
  );
}

class _EndingBox extends StatelessWidget {
  const _EndingBox({required this.onRestart});
  final VoidCallback onRestart;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(.93),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      children: [
        const Text(
          '这段回忆暂时走到了尽头。',
          style: TextStyle(
            color: _ink,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: onRestart,
          icon: const Icon(Icons.replay_rounded),
          label: const Text('回到开幕'),
        ),
      ],
    ),
  );
}

Color _nodeColor(StoryNodeType type) => switch (type) {
  StoryNodeType.start => _violet,
  StoryNodeType.event => _deepPink,
  StoryNodeType.choice => const Color(0xFFB77B35),
  StoryNodeType.random => const Color(0xFF5E8E83),
  StoryNodeType.ending => const Color(0xFF6C6D9C),
};

String _nodeSummary(StoryNode node) => switch (node.type) {
  StoryNodeType.start => node.allOutgoing.isEmpty ? '等待连接' : '入口已连接',
  StoryNodeType.event => '${node.dialogue.length} 句对白',
  StoryNodeType.choice => '${node.choices.length} 个选项',
  StoryNodeType.random => '${node.allOutgoing.length} 条随机路线',
  StoryNodeType.ending => '${node.dialogue.length} 句结尾文本',
};
