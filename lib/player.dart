import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'audio_bus.dart';
import 'models.dart';
import 'player_save.dart';
import 'stage.dart';
import 'storage.dart';
import 'ui.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.project,
    required this.store,
    required this.settings,
    this.preview = false,
  });
  final ProjectModel project;
  final ProjectStore store;
  final AppSettings settings;
  final bool preview;
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final StorySession session = StorySession(widget.project);
  late final AudioBus audio = AudioBus(
    widget.project,
    widget.store,
    widget.settings,
    onError: (message) {
      if (mounted) notify(context, message);
    },
  );
  late final AnimationController animation = AnimationController(vsync: this);
  List<StageLayer> layers = [];
  String background = '', previousNode = '';
  bool blur = false;
  Timer? textTimer;
  Timer? skipTimer;
  bool skipping = false, busy = false;
  final List<Timer> effects = [];
  int visibleChars = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _enter();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    skipTimer?.cancel();
    textTimer?.cancel();
    for (final t in effects) {
      t.cancel();
    }
    animation.dispose();
    audio.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && skipping) {
      setState(_stopSkipping);
    }
  }

  bool get _canSkip =>
      !busy &&
      !session.isMenu &&
      session.node.type != StoryNodeType.ending &&
      session.options.isEmpty &&
      session.error == null;

  void _stopSkipping() {
    skipTimer?.cancel();
    skipTimer = null;
    skipping = false;
  }

  void _finishLine() {
    textTimer?.cancel();
    for (final timer in effects) {
      timer.cancel();
    }
    effects.clear();
    animation.stop();
    layers = stageAt(layers, double.infinity);
    visibleChars = session.line?.text.characters.length ?? 0;
    audio.stopSpeech();
  }

  void _toggleSkip() {
    if (skipping) {
      setState(_stopSkipping);
      return;
    }
    if (!_canSkip) return;
    setState(() {
      skipping = true;
      _finishLine();
    });
    skipTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (!mounted || !_canSkip || ModalRoute.of(context)?.isCurrent == false) {
        if (mounted)
          setState(_stopSkipping);
        else
          _stopSkipping();
        return;
      }
      _step();
    });
  }

  Future<void> _saveProgress() async {
    if (busy || session.isMenu || session.error != null) return;
    setState(() {
      _stopSkipping();
      busy = true;
    });
    final save = PlayerSave(
      projectId: widget.project.id,
      savedAt: DateTime.now(),
      position: session.checkpoint(),
      layers: stageAt(layers, double.infinity),
      background: background,
      blur: blur,
      bgm: audio.currentBgm,
    );
    try {
      await widget.store.savePlayerProgress(
        widget.project,
        save,
        preview: widget.preview,
      );
      if (mounted) notify(context, widget.preview ? '测试进度已存档' : '进度已存档');
    } catch (_) {
      if (mounted) notify(context, '存档失败，请检查磁盘空间或文件权限后重试。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _loadProgress() async {
    if (busy) return;
    setState(() {
      _stopSkipping();
      busy = true;
    });
    try {
      final save = await widget.store.loadPlayerProgress(
        widget.project,
        preview: widget.preview,
      );
      if (!mounted) return;
      if (save == null) {
        notify(context, '还没有存档，游玩时点击“存档”即可保存。');
        return;
      }
      // loadPlayerProgress validates everything first; a bad save leaves the
      // current position and scene intact.
      session.restore(save.position);
      _finishLine();
      layers = save.layers.map((layer) => layer.copy()).toList();
      background = save.background;
      blur = save.blur;
      previousNode = session.nodeId;
      audio.restore(
        save.bgm,
        voice: session.options.isEmpty ? session.line?.voiceAsset ?? '' : '',
      );
      notify(context, '已读取存档');
    } on FormatException catch (e) {
      if (mounted) notify(context, '无法读档：${e.message}');
    } catch (_) {
      if (mounted) notify(context, '读档失败，存档可能损坏或暂时无法读取。当前进度已保留。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _enter() {
    textTimer?.cancel();
    for (final t in effects) {
      t.cancel();
    }
    effects.clear();
    audio.stopEffects();
    final node = session.node, line = session.line;
    final nodeChanged = previousNode != node.id;
    layers = stageAt(layers, double.infinity);
    if (session.isMenu) {
      layers = [];
      background = '';
      blur = false;
    }
    if (node.backgroundAsset.isNotEmpty) {
      background = node.backgroundAsset;
      blur = node.backgroundBlur;
    }
    if (line?.sceneEnabled == true)
      layers = line!.layers.map((l) => l.copy()).toList();
    final duration = stageDuration(layers);
    animation.duration = Duration(
      milliseconds: math.max(1, (duration * 1000).round()),
    );
    if (skipping) {
      animation.stop();
      layers = stageAt(layers, double.infinity);
    } else {
      animation.forward(from: 0);
    }
    for (final layer in layers) {
      var delay = 0.0;
      for (final motion in layer.motions) {
        if (motion.soundId.isNotEmpty)
          effects.add(
            Timer(
              Duration(milliseconds: (delay * 1000).round()),
              () => audio.effect(motion.soundId),
            ),
          );
        delay += motion.duration;
      }
    }
    audio.enter(
      node,
      line,
      nodeChanged: nodeChanged,
      restart: session.isMenu,
      silent: skipping,
    );
    previousNode = node.id;
    visibleChars = 0;
    if (skipping) {
      visibleChars = line?.text.characters.length ?? 0;
      return;
    }
    if (!session.isMenu && line != null) {
      final speed = line.textSpeed > 0
          ? line.textSpeed
          : widget.settings.textSpeed;
      final count = line.text.characters.length;
      textTimer = Timer.periodic(
        Duration(milliseconds: (1000 / speed.clamp(1, 100)).round()),
        (timer) {
          if (!mounted) {
            timer.cancel();
            return;
          }
          setState(() => visibleChars = math.min(count, visibleChars + 1));
          if (visibleChars >= count) timer.cancel();
        },
      );
    }
  }

  void _advance() {
    if (busy) return;
    if (skipping) {
      setState(_stopSkipping);
      return;
    }
    if (session.options.isNotEmpty || session.error != null) return;
    audio.click(session.node.clickAsset);
    final line = session.line;
    if (!session.isMenu &&
        line != null &&
        visibleChars < line.text.characters.length) {
      textTimer?.cancel();
      setState(() => visibleChars = line.text.characters.length);
      return;
    }
    _step();
  }

  void _step() {
    session.advance();
    if (!_canSkip) _stopSkipping();
    if (session.options.isEmpty && session.error == null)
      _enter();
    else
      _finishLine();
    setState(() {});
  }

  void _choose(StoryNode choice) {
    if (busy) return;
    _stopSkipping();
    audio.click(session.node.clickAsset);
    session.choose(choice);
    _enter();
    setState(() {});
  }

  void _restart() {
    if (busy) return;
    _stopSkipping();
    session.restart();
    _enter();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final line = session.line;
    final choices = session.options;
    final text = choices.isNotEmpty
        ? choices.first.prompt
        : (line?.text.characters.take(visibleChars).toString() ?? '');
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): _advance,
        const SingleActivator(LogicalKeyboardKey.enter): _advance,
        const SingleActivator(LogicalKeyboardKey.f5, includeRepeats: false):
            _saveProgress,
        const SingleActivator(LogicalKeyboardKey.f9, includeRepeats: false):
            _loadProgress,
        const SingleActivator(LogicalKeyboardKey.keyS, includeRepeats: false):
            _toggleSkip,
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.pop(context),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: paper,
          appBar: AppBar(
            title: Text(
              '${widget.project.name}${widget.preview ? ' · 测试运行' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              Tooltip(
                message: '快速存档（F5）· 每部作品一个存档位，再次保存会覆盖',
                child: TextButton.icon(
                  onPressed: busy || session.isMenu || session.error != null
                      ? null
                      : _saveProgress,
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('存档'),
                ),
              ),
              Tooltip(
                message: '快速读档（F9）',
                child: TextButton.icon(
                  onPressed: busy ? null : _loadProgress,
                  icon: const Icon(Icons.restore, size: 18),
                  label: const Text('读档'),
                ),
              ),
              Tooltip(
                message: '跳过对话（S）· 遇到选项或结局自动停止',
                child: TextButton.icon(
                  onPressed: skipping || _canSkip ? _toggleSkip : null,
                  style: TextButton.styleFrom(
                    foregroundColor: skipping ? thought : null,
                  ),
                  icon: Icon(
                    skipping ? Icons.pause : Icons.fast_forward_outlined,
                    size: 18,
                  ),
                  label: Text(skipping ? '停止跳过' : '跳过'),
                ),
              ),
              TextButton.icon(
                onPressed: busy ? null : _restart,
                icon: const Icon(Icons.replay),
                label: const Text('回到开幕'),
              ),
              const SizedBox(width: 12),
            ],
          ),
          body: Center(
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: LayoutBuilder(
                builder: (context, box) => Stack(
                  children: [
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: animation,
                        builder: (context, _) => StageView(
                          project: widget.project,
                          store: widget.store,
                          layers: stageAt(
                            layers,
                            animation.value * stageDuration(layers),
                          ),
                          background: background,
                          blur: blur,
                          onAction: session.isMenu
                              ? (action) {
                                  if (action == 'start') _advance();
                                  if (action == 'exit') Navigator.pop(context);
                                }
                              : null,
                        ),
                      ),
                    ),
                    if (session.isMenu) ...[
                      Positioned(
                        top: box.maxHeight * .14,
                        left: 32,
                        right: 32,
                        child: IgnorePointer(
                          child: Text(
                            widget.project.name,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: math.min(44, box.maxWidth / 20),
                              fontWeight: FontWeight.w300,
                              color: ink,
                              shadows: const [
                                Shadow(color: Color(0x66000000), blurRadius: 8),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (!layers.any(
                        (l) => l.action == 'start' && l.opacity > .01,
                      ))
                        Positioned(
                          bottom: box.maxHeight * .18,
                          left: box.maxWidth * .32,
                          right: box.maxWidth * .32,
                          child: FilledButton.icon(
                            onPressed: _advance,
                            icon: const Icon(Icons.play_arrow),
                            label: const Padding(
                              padding: EdgeInsets.all(14),
                              child: Text(
                                '开始这段回忆',
                                style: TextStyle(fontSize: 18),
                              ),
                            ),
                          ),
                        ),
                    ] else ...[
                      if (choices.isNotEmpty)
                        Positioned(
                          left: box.maxWidth * .25,
                          right: box.maxWidth * .25,
                          top: 24,
                          bottom: box.maxHeight * .33,
                          child: Center(
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: choices
                                    .map(
                                      (choice) => Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 10,
                                        ),
                                        child: _skin(
                                          widget.project.choiceSkin,
                                          InkWell(
                                            onTap: () => _choose(choice),
                                            borderRadius: memoryRadius,
                                            child: SizedBox(
                                              width: double.infinity,
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 14,
                                                      horizontal: 20,
                                                    ),
                                                child: Text(
                                                  choice.title,
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(
                                                    color: ink,
                                                    fontSize: 17,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        left: 28,
                        right: 28,
                        bottom: 22,
                        height: box.maxHeight * .27,
                        child: _skin(
                          widget.project.dialogueSkin,
                          InkWell(
                            onTap: choices.isEmpty ? _advance : null,
                            borderRadius: memoryRadius,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                24,
                                16,
                                24,
                                12,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    choices.isEmpty
                                        ? (line?.speaker ?? session.node.title)
                                        : '请选择',
                                    style: TextStyle(
                                      color: choices.isEmpty
                                          ? memoryColor(
                                              line?.speaker ??
                                                  session.node.title,
                                            )
                                          : thought,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Expanded(
                                    child: SingleChildScrollView(
                                      child: Text(
                                        text.isEmpty &&
                                                line == null &&
                                                choices.isEmpty
                                            ? '点击继续'
                                            : text,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: (line?.textSize ?? 0) > 0
                                              ? line!.textSize
                                              : widget.settings.textSize,
                                          height: 1.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (choices.isEmpty)
                                    const Align(
                                      alignment: Alignment.centerRight,
                                      child: Text(
                                        '点击 / 空格继续  ▸',
                                        style: TextStyle(
                                          color: secondaryInk,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (session.error != null)
                      Center(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(28),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.alt_route,
                                  color: accent,
                                  size: 34,
                                ),
                                const SizedBox(height: 14),
                                Text(session.error!),
                                const SizedBox(height: 18),
                                Wrap(
                                  spacing: 12,
                                  children: [
                                    OutlinedButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: Text(
                                        widget.preview ? '返回编辑' : '返回作品库',
                                      ),
                                    ),
                                    FilledButton(
                                      onPressed: _restart,
                                      child: const Text('回到开幕'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _skin(String id, Widget child) => ClipRRect(
    borderRadius: memoryRadius,
    child: Stack(
      children: [
        Positioned.fill(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: paper.withValues(alpha: .72),
                borderRadius: memoryRadius,
                border: Border.all(color: hairline),
              ),
            ),
          ),
        ),
        if (id.isNotEmpty)
          Positioned.fill(
            child: ProjectImage(
              store: widget.store,
              project: widget.project,
              assetId: id,
              fit: BoxFit.fill,
            ),
          ),
        child,
      ],
    ),
  );
}
