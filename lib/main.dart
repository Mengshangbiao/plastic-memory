import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'editor.dart';
import 'home_view.dart';
import 'models.dart';
import 'player.dart';
import 'project_actions.dart';
import 'storage.dart';
import 'ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(1360, 820),
      minimumSize: Size(1024, 700),
      center: true,
      title: '可塑性记忆',
      backgroundColor: paper,
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );
  try {
    final store = await ProjectStore.open();
    final settings = await store.loadSettings();
    await windowManager.setFullScreen(settings.fullscreen);
    await windowManager.setPreventClose(true);
    runApp(PlasticMemoryApp(store: store, settings: settings, desktop: true));
  } catch (e) {
    runApp(
      MaterialApp(
        theme: memoryTheme(),
        home: Scaffold(
          body: Center(child: SelectableText('无法打开本地项目目录，请检查磁盘或文件权限后重试。\n$e')),
        ),
      ),
    );
  }
}

class PlasticMemoryApp extends StatelessWidget {
  const PlasticMemoryApp({
    super.key,
    this.store,
    this.settings,
    this.desktop = false,
  });
  final ProjectStore? store;
  final AppSettings? settings;
  final bool desktop;
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: '可塑性记忆',
    theme: memoryTheme(),
    home: MemoryHome(
      store: store ?? ProjectStore.memory(),
      settings: settings ?? AppSettings(),
      desktop: desktop,
    ),
  );
}

class MemoryHome extends StatefulWidget {
  const MemoryHome({
    super.key,
    required this.store,
    required this.settings,
    required this.desktop,
  });
  final ProjectStore store;
  final AppSettings settings;
  final bool desktop;
  @override
  State<MemoryHome> createState() => _MemoryHomeState();
}

class _MemoryHomeState extends State<MemoryHome> with WindowListener {
  bool loading = true, closing = false;
  ProjectModel? activeDraft;
  String? error;
  List<ProjectModel> overview = [];
  DateTime? libraryVisited, creationVisited;
  bool minimized = false;
  @override
  void initState() {
    super.initState();
    if (widget.desktop) windowManager.addListener(this);
    _load();
  }

  @override
  void dispose() {
    if (widget.desktop) windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final projects = await widget.store.loadProjects();
      if (projects.isEmpty &&
          widget.store.warnings.isEmpty &&
          !await widget.store.hasProjectHistory()) {
        final demo = ProjectModel.demo();
        await widget.store.save(demo);
        await widget.store.publish(demo);
        projects.add(demo);
      }
      overview = projects;
      libraryVisited = await widget.store.lastVisit(HomeEntrance.library);
      creationVisited = await widget.store.lastVisit(HomeEntrance.creation);
      if (mounted && widget.store.warnings.isNotEmpty)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) notify(context, widget.store.warnings.join('\n'));
        });
    } catch (e) {
      error = '项目读取失败：$e';
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  void onWindowMinimize() {
    if (mounted) setState(() => minimized = true);
  }

  @override
  void onWindowRestore() {
    if (mounted) setState(() => minimized = false);
  }

  Future<void> _recordVisit(HomeEntrance entrance) async {
    try {
      final time = await widget.store.recordVisit(entrance);
      if (!mounted) return;
      setState(() {
        if (entrance == HomeEntrance.library)
          libraryVisited = time;
        else
          creationVisited = time;
      });
    } catch (_) {
      if (mounted) notify(context, '最近进入时间未能保存，仍可正常使用。');
    }
  }

  @override
  void onWindowClose() async {
    if (closing) return;
    closing = true;
    try {
      if (activeDraft != null) await widget.store.save(activeDraft!);
      await windowManager.destroy();
    } catch (e) {
      if (mounted) notify(context, '关闭前保存失败，请先保存项目：$e');
      closing = false;
    }
  }

  Future<void> _create() async {
    await _recordVisit(HomeEntrance.creation);
    if (!mounted) return;
    await _edit(ProjectModel.empty('未命名回忆'));
  }

  Future<void> _edit(ProjectModel project) async {
    ProjectModel? next = project;
    while (next != null && mounted) {
      final current = next;
      activeDraft = current;
      final result = await Navigator.push<ProjectModel>(
        context,
        MaterialPageRoute(
          builder: (_) => EditorPage(
            project: current,
            store: widget.store,
            settings: widget.settings,
          ),
        ),
      );
      next = result;
    }
    activeDraft = null;
    await _load();
  }

  Future<void> _library() async {
    await _recordVisit(HomeEntrance.library);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            LibraryPage(store: widget.store, settings: widget.settings),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _settings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsPage(
          store: widget.store,
          settings: widget.settings,
          desktop: widget.desktop,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MemoryHomeView(
    libraryVisited: libraryVisited,
    creationVisited: creationVisited,
    motionEnabled: !minimized,
    loading: loading,
    error: error,
    projectCount: overview.length,
    nodeCount: overview.fold(
      0,
      (total, project) => total + project.nodes.length,
    ),
    lastModified: overview.isEmpty ? null : overview.first.updatedAt,
    onLibrary: _library,
    onCreate: _create,
    onSettings: _settings,
    onExit: () {
      if (widget.desktop) windowManager.close();
    },
    onRetry: () {
      setState(() {
        loading = true;
        error = null;
      });
      _load();
    },
  );
}

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, required this.store, required this.settings});
  final ProjectStore store;
  final AppSettings settings;
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  late final games = widget.store.loadProjects(games: true);
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('纷乱回忆')),
    body: FutureBuilder<List<ProjectModel>>(
      future: games,
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return const Center(child: Text('作品读取失败，请检查项目文件夹。'));
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final projects = snapshot.data!;
        if (projects.isEmpty)
          return const Center(
            child: Text(
              '还没有完成的作品。\n在“创造回忆”中连接剧情后，点击“创建游戏”。',
              textAlign: TextAlign.center,
            ),
          );
        return ListView(
          padding: const EdgeInsets.all(32),
          children: [
            const Text(
              '选择一段回忆，重新走进那个世界。',
              style: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w300,
                color: ink,
              ),
            ),
            const SizedBox(height: 24),
            ...projects.map(
              (project) => Card(
                margin: const EdgeInsets.only(bottom: 16),
                clipBehavior: Clip.antiAlias,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: memoryColor(project.id),
                        width: 3,
                      ),
                    ),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 24,
                      horizontal: 24,
                    ),
                    leading: Icon(
                      Icons.auto_stories_outlined,
                      color: memoryColor(project.id),
                    ),
                    title: Text(
                      project.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w400,
                        fontSize: 19,
                      ),
                    ),
                    subtitle: Text(
                      '${project.nodes.length} 个剧情节点 · ${project.characters.length} 位人物',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PlayerPage(
                                project: project,
                                store: widget.store,
                                settings: widget.settings,
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('游玩'),
                        ),
                        const SizedBox(width: 12),
                        ProjectDeleteButton(
                          key: ValueKey('delete-game-${project.id}'),
                          project: project,
                          store: widget.store,
                          onDeleted: () => setState(() {
                            projects.removeWhere(
                              (item) => item.id == project.id,
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.store,
    required this.settings,
    required this.desktop,
  });
  final ProjectStore store;
  final AppSettings settings;
  final bool desktop;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final AppSettings draft = AppSettings.fromJson(widget.settings.toJson());
  bool busy = false;
  Future<void> _save() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      if (widget.desktop) await windowManager.setFullScreen(draft.fullscreen);
      await widget.store.saveSettings(draft);
      final target = widget.settings;
      target.master = draft.master;
      target.bgm = draft.bgm;
      target.voice = draft.voice;
      target.sound = draft.sound;
      target.textSpeed = draft.textSpeed;
      target.textSize = draft.textSize;
      target.fullscreen = draft.fullscreen;
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        notify(context, '设置保存失败：$e');
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _save();
    },
    child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: busy ? null : _save,
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('设置'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 18),
            child: FilledButton(
              onPressed: busy ? null : _save,
              child: const Text('保存并返回'),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 850),
          child: ListView(
            padding: const EdgeInsets.all(28),
            children: [
              _section('声音', Icons.volume_up_outlined, [
                _slider(
                  '游戏总音量',
                  draft.master,
                  0,
                  1,
                  (v) => draft.master = v,
                  percent: true,
                ),
                _slider(
                  '人物音量',
                  draft.voice,
                  0,
                  1,
                  (v) => draft.voice = v,
                  percent: true,
                ),
                _slider(
                  '背景音量',
                  draft.bgm,
                  0,
                  1,
                  (v) => draft.bgm = v,
                  percent: true,
                ),
                _slider(
                  '点击音与音效',
                  draft.sound,
                  0,
                  1,
                  (v) => draft.sound = v,
                  percent: true,
                ),
              ]),
              _section('文字', Icons.text_fields, [
                _slider(
                  '文字速度',
                  draft.textSpeed,
                  5,
                  100,
                  (v) => draft.textSpeed = v,
                  suffix: '字/秒',
                ),
                _slider(
                  '文字大小',
                  draft.textSize,
                  14,
                  36,
                  (v) => draft.textSize = v,
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: paper,
                    borderRadius: memoryRadius,
                  ),
                  child: Text(
                    '每一段回忆，都值得被温柔地讲述。',
                    style: TextStyle(fontSize: draft.textSize, color: ink),
                  ),
                ),
              ]),
              _section('显示', Icons.desktop_windows_outlined, [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('全屏显示'),
                  subtitle: const Text('保存后生效，下次启动时保持'),
                  value: draft.fullscreen,
                  onChanged: (v) => setState(() => draft.fullscreen = v),
                ),
              ]),
              _section('项目存放位置', Icons.folder_outlined, [
                SelectableText(
                  widget.store.location,
                  style: const TextStyle(fontSize: 12, color: secondaryInk),
                ),
                TextButton.icon(
                  onPressed: () => Clipboard.setData(
                    ClipboardData(text: widget.store.location),
                  ),
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('复制路径'),
                ),
              ]),
            ],
          ),
        ),
      ),
    ),
  );
  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> changed, {
    bool percent = false,
    String suffix = '',
  }) => Row(
    children: [
      SizedBox(width: 110, child: Text(label)),
      Expanded(
        child: Slider(
          value: value,
          min: min,
          max: max,
          onChanged: (v) => setState(() => changed(v)),
        ),
      ),
      SizedBox(
        width: 80,
        child: Text(
          percent ? '${(value * 100).round()}%' : '${value.round()} $suffix',
          textAlign: TextAlign.right,
        ),
      ),
    ],
  );
  Widget _section(String label, IconData icon, List<Widget> children) => Card(
    margin: const EdgeInsets.only(bottom: 18),
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accent),
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    ),
  );
}
