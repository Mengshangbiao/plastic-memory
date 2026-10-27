import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'models.dart';
import 'storage.dart';
import 'ui.dart';

List<StageLayer> stageAt(List<StageLayer> source, double seconds) =>
    source.map((original) {
      final layer = original.copy();
      var remaining = seconds;
      for (final motion in original.motions) {
        if (remaining < 0) break;
        final t = (remaining / motion.duration).clamp(0.0, 1.0);
        switch (motion.type) {
          case MotionType.transform:
            layer.x += (motion.x - layer.x) * t;
            layer.y += (motion.y - layer.y) * t;
            layer.width += (motion.width - layer.width) * t;
            layer.height += (motion.height - layer.height) * t;
          case MotionType.fade:
            layer.opacity += (motion.opacity - layer.opacity) * t;
          case MotionType.swap:
            if (motion.assetId.isNotEmpty) layer.assetId = motion.assetId;
        }
        remaining -= motion.duration;
        if (t < 1) break;
      }
      layer.motions = [];
      return layer;
    }).toList();
double stageDuration(List<StageLayer> layers) => layers.fold<double>(
  0,
  (maxTime, layer) => math.max(
    maxTime,
    layer.motions.fold<double>(0, (sum, m) => sum + m.duration),
  ),
);

class StageView extends StatelessWidget {
  const StageView({
    super.key,
    required this.project,
    required this.store,
    required this.layers,
    this.background = '',
    this.blur = false,
    this.onAction,
  });
  final ProjectModel project;
  final ProjectStore store;
  final List<StageLayer> layers;
  final String background;
  final bool blur;
  final ValueChanged<String>? onAction;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const MemoryAtmosphere(child: SizedBox.expand()),
          if (background.isNotEmpty)
            ImageFiltered(
              imageFilter: ui.ImageFilter.blur(
                sigmaX: blur ? 7 : 0,
                sigmaY: blur ? 7 : 0,
              ),
              child: ProjectImage(
                store: store,
                project: project,
                assetId: background,
                fit: BoxFit.cover,
              ),
            ),
          ...layers.map(
            (l) => Positioned(
              left: l.x * box.maxWidth,
              top: l.y * box.maxHeight,
              width: math.max(1, l.width * box.maxWidth),
              height: math.max(1, l.height * box.maxHeight),
              child: IgnorePointer(
                ignoring:
                    l.action.isEmpty || l.opacity <= .01 || onAction == null,
                child: MouseRegion(
                  cursor: l.action.isEmpty
                      ? SystemMouseCursors.basic
                      : SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: l.action.isEmpty
                        ? null
                        : () => onAction?.call(l.action),
                    child: Opacity(
                      opacity: l.opacity.clamp(0, 1),
                      child: ProjectImage(
                        store: store,
                        project: project,
                        assetId: l.assetId,
                        fit: BoxFit.fill,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class StageEditor extends StatefulWidget {
  const StageEditor({
    super.key,
    required this.project,
    required this.store,
    required this.line,
    required this.node,
    this.inheritedLayers = const [],
  });
  final ProjectModel project;
  final ProjectStore store;
  final DialogueLine line;
  final StoryNode node;
  final List<StageLayer> inheritedLayers;
  @override
  State<StageEditor> createState() => _StageEditorState();
}

class _StageEditorState extends State<StageEditor>
    with SingleTickerProviderStateMixin {
  late List<StageLayer> layers =
      (widget.line.sceneEnabled ? widget.line.layers : widget.inheritedLayers)
          .map((l) => l.copy())
          .toList();
  String? selected;
  StageLayer? transformDraft;
  StageLayer? anchor;
  final sceneKey = GlobalKey();
  Size sceneSize = const Size(960, 540);
  late final AnimationController preview = AnimationController(vsync: this);
  bool previewing = false;
  StageLayer? get active {
    for (final l in layers) {
      if (l.id == selected) return l;
    }
    return null;
  }

  @override
  void dispose() {
    preview.dispose();
    super.dispose();
  }

  void _stopPreview() {
    preview.stop();
    setState(() => previewing = false);
  }

  void _add(AssetEntry asset, [Offset? global]) {
    _stopPreview();
    final point = global == null
        ? const Offset(.35, .08)
        : (sceneKey.currentContext!.findRenderObject() as RenderBox)
              .globalToLocal(global);
    final layer = StageLayer(id: newId('layer'), assetId: asset.id);
    if (asset.category == AssetCategory.background) {
      layer.x = 0;
      layer.y = 0;
      layer.width = 1;
      layer.height = 1;
      layers.insert(0, layer);
    } else {
      if (global != null) {
        layer.x = (point.dx / sceneSize.width).clamp(-.5, 1);
        layer.y = (point.dy / sceneSize.height).clamp(-.5, 1);
      }
      layers.add(layer);
    }
    setState(() => selected = layer.id);
  }

  Future<void> _motionDialog(MotionType type, {StageLayer? target}) async {
    final layer = active;
    if (layer == null) return;
    final end = stageAt([layer], double.infinity).single;
    var duration = 1.0, opacity = 0.0;
    var sound = '', asset = '';
    final motion = await showDialog<StageMotion>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text('添加${type.label}动作'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    initialValue: '1',
                    decoration: const InputDecoration(
                      labelText: '动作时间（秒，0.05～120）',
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => duration = double.tryParse(v) ?? 0,
                  ),
                  const SizedBox(height: 14),
                  if (type == MotionType.fade) ...[
                    Text('结束透明度 ${(opacity * 100).round()}%'),
                    Slider(
                      value: opacity,
                      onChanged: (v) => update(() => opacity = v),
                    ),
                  ],
                  if (type == MotionType.swap) ...[
                    AssetSelect(
                      project: widget.project,
                      label: '替换为',
                      value: asset,
                      imagesOnly: true,
                      onChanged: (v) => update(() => asset = v),
                    ),
                    const SizedBox(height: 14),
                  ],
                  AssetSelect(
                    project: widget.project,
                    label: '同步音效',
                    value: sound,
                    category: AssetCategory.sound,
                    onChanged: (v) => update(() => sound = v),
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
                if (!duration.isFinite || duration < .05 || duration > 120) {
                  notify(context, '动作时间应为 0.05～120 秒。');
                  return;
                }
                if (type == MotionType.swap && asset.isEmpty) {
                  notify(context, '请选择差分图片。');
                  return;
                }
                Navigator.pop(
                  context,
                  StageMotion(
                    type: type,
                    duration: duration,
                    x: target?.x ?? end.x,
                    y: target?.y ?? end.y,
                    width: target?.width ?? end.width,
                    height: target?.height ?? end.height,
                    opacity: opacity,
                    assetId: asset,
                    soundId: sound,
                  ),
                );
              },
              child: const Text('加入动作列表'),
            ),
          ],
        ),
      ),
    );
    if (motion != null && mounted)
      setState(() {
        layer.motions.add(motion);
        transformDraft = null;
        anchor = null;
      });
  }

  Future<void> _context(StageLayer layer, Offset position) async {
    _stopPreview();
    setState(() => selected = layer.id);
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        const PopupMenuItem(value: 'fade', child: Text('隐藏 / 渐变透明度')),
        const PopupMenuItem(value: 'transform', child: Text('变化（移动 / 缩放）')),
        const PopupMenuItem(value: 'opacity', child: Text('初始透明度')),
        const PopupMenuItem(value: 'swap', child: Text('差分（替换图片）')),
        if (widget.node.type == StoryNodeType.start)
          const PopupMenuItem(value: 'action', child: Text('点击事件')),
        const PopupMenuItem(value: 'front', child: Text('移到最上层')),
        const PopupMenuItem(value: 'delete', child: Text('移除图片')),
      ],
    );
    if (!mounted) return;
    switch (result) {
      case 'fade':
        await _motionDialog(MotionType.fade);
      case 'swap':
        await _motionDialog(MotionType.swap);
      case 'transform':
        setState(() {
          anchor = stageAt([layer], double.infinity).single;
          transformDraft = anchor!.copy();
        });
      case 'opacity':
        var value = layer.opacity;
        final result = await showDialog<double>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, update) => AlertDialog(
              title: const Text('初始透明度'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${(value * 100).round()}%'),
                  Slider(
                    value: value,
                    onChanged: (v) => update(() => value = v),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, value),
                  child: const Text('保存'),
                ),
              ],
            ),
          ),
        );
        if (result != null && mounted) setState(() => layer.opacity = result);
      case 'action':
        final result = await showDialog<String>(
          context: context,
          builder: (context) => SimpleDialog(
            title: const Text('点击图片时'),
            children: [
              for (final entry in {
                '': '无事件',
                'start': '开始故事',
                'exit': '退出作品',
              }.entries)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, entry.key),
                  child: Text(entry.value),
                ),
            ],
          ),
        );
        if (result != null && mounted) setState(() => layer.action = result);
      case 'front':
        setState(() {
          layers.remove(layer);
          layers.add(layer);
        });
      case 'delete':
        setState(() {
          layers.remove(layer);
          selected = null;
        });
    }
  }

  void _preview() {
    if (layers.isEmpty) return;
    preview.duration = Duration(
      milliseconds: math.max(1, (stageDuration(layers) * 1000).round()),
    );
    setState(() => previewing = true);
    preview.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.close),
      ),
      title: Text(
        transformDraft != null
            ? '变化终态 · 拖动图片或四角控制点'
            : widget.node.type == StoryNodeType.start
            ? '开幕画面与图片事件'
            : '演出制作 · ${widget.line.speaker}',
      ),
      actions: transformDraft != null
          ? [
              TextButton(
                onPressed: () => setState(() {
                  transformDraft = null;
                  anchor = null;
                }),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () =>
                    _motionDialog(MotionType.transform, target: transformDraft),
                child: const Text('保存终态'),
              ),
              const SizedBox(width: 16),
            ]
          : [
              TextButton.icon(
                onPressed: previewing ? _stopPreview : _preview,
                icon: Icon(previewing ? Icons.stop : Icons.play_arrow),
                label: Text(previewing ? '停止预览' : '预览动作'),
              ),
              FilledButton(
                onPressed: () {
                  widget.line.layers = layers;
                  widget.line.sceneEnabled = true;
                  Navigator.pop(context, true);
                },
                child: const Text('保存并退出'),
              ),
              const SizedBox(width: 16),
            ],
    ),
    body: Row(
      children: [
        if (transformDraft == null)
          SizedBox(width: 195, child: _assetPalette()),
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: LayoutBuilder(
                      builder: (context, box) {
                        sceneSize = box.biggest;
                        return DragTarget<AssetEntry>(
                          onAcceptWithDetails: (d) => _add(d.data, d.offset),
                          builder: (context, candidates, rejected) => Container(
                            key: sceneKey,
                            decoration: BoxDecoration(
                              border: Border.all(color: accent),
                            ),
                            child: AnimatedBuilder(
                              animation: preview,
                              builder: (context, _) {
                                final visible = previewing
                                    ? stageAt(
                                        layers,
                                        preview.value * stageDuration(layers),
                                      )
                                    : layers;
                                return Stack(
                                  children: [
                                    Positioned.fill(
                                      child: StageView(
                                        project: widget.project,
                                        store: widget.store,
                                        layers: const [],
                                        background: widget.node.backgroundAsset,
                                        blur: widget.node.backgroundBlur,
                                      ),
                                    ),
                                    ...visible.map(
                                      (layer) => _layer(
                                        transformDraft?.id == layer.id
                                            ? transformDraft!
                                            : layer,
                                      ),
                                    ),
                                    if (anchor != null)
                                      Positioned(
                                        left: anchor!.x * sceneSize.width,
                                        top: anchor!.y * sceneSize.height,
                                        width: anchor!.width * sceneSize.width,
                                        height:
                                            anchor!.height * sceneSize.height,
                                        child: IgnorePointer(
                                          child: Container(
                                            decoration: BoxDecoration(
                                              border: Border.all(
                                                color: sorrow,
                                                width: 2,
                                              ),
                                            ),
                                            child: const Align(
                                              alignment: Alignment.topLeft,
                                              child: Text(
                                                '起点',
                                                style: TextStyle(color: sorrow),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              Container(
                width: double.infinity,
                margin: const EdgeInsets.all(18),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: memoryRadius,
                  border: Border.all(color: hairline),
                ),
                child: Text(
                  widget.node.type == StoryNodeType.start
                      ? '右键图片 → 点击事件，可将素材设为开始或退出按钮。'
                      : '${widget.line.speaker}：${widget.line.text}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        if (transformDraft == null) SizedBox(width: 265, child: _motions()),
      ],
    ),
  );
  Widget _layer(StageLayer layer) {
    final editable =
        !previewing &&
        (transformDraft == null || transformDraft!.id == layer.id);
    return Positioned(
      left: layer.x * sceneSize.width,
      top: layer.y * sceneSize.height,
      width: math.max(12, layer.width * sceneSize.width),
      height: math.max(12, layer.height * sceneSize.height),
      child: GestureDetector(
        key: ValueKey('stage-layer-${layer.id}'),
        onTap: editable ? () => setState(() => selected = layer.id) : null,
        onSecondaryTapUp: editable && transformDraft == null
            ? (d) => _context(layer, d.globalPosition)
            : null,
        onPanUpdate: editable
            ? (d) => setState(() {
                selected = layer.id;
                layer.x = (layer.x + d.delta.dx / sceneSize.width).clamp(
                  -1,
                  1.5,
                );
                layer.y = (layer.y + d.delta.dy / sceneSize.height).clamp(
                  -1,
                  1.5,
                );
              })
            : null,
        child: Stack(
          clipBehavior: Clip.none,
          fit: StackFit.expand,
          children: [
            Opacity(
              opacity: layer.opacity,
              child: ProjectImage(
                store: widget.store,
                project: widget.project,
                assetId: layer.assetId,
                fit: BoxFit.fill,
              ),
            ),
            if (selected == layer.id && editable) ...[
              IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: accent, width: 2),
                  ),
                ),
              ),
              ...[
                const Alignment(-1, -1),
                const Alignment(1, -1),
                const Alignment(-1, 1),
                const Alignment(1, 1),
              ].map(
                (corner) => Align(
                  alignment: corner,
                  child: MouseRegion(
                    cursor: corner.x == corner.y
                        ? SystemMouseCursors.resizeUpLeftDownRight
                        : SystemMouseCursors.resizeUpRightDownLeft,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanUpdate: (d) => setState(() {
                        final dx = d.delta.dx / sceneSize.width,
                            dy = d.delta.dy / sceneSize.height;
                        final width = (layer.width + dx * corner.x).clamp(
                              .02,
                              3.0,
                            ),
                            height = (layer.height + dy * corner.y).clamp(
                              .02,
                              3.0,
                            );
                        if (corner.x < 0) layer.x += layer.width - width;
                        if (corner.y < 0) layer.y += layer.height - height;
                        layer.width = width;
                        layer.height = height;
                      }),
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: surface,
                          border: Border.all(color: accent, width: 2),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _assetPalette() => DefaultTabController(
    length: 3,
    child: Column(
      children: [
        const TabBar(
          isScrollable: true,
          tabs: [
            Tab(text: '人物图'),
            Tab(text: '背景图'),
            Tab(text: '物品图'),
          ],
        ),
        const Padding(
          padding: EdgeInsets.all(10),
          child: Text(
            '拖入场景，也可点击添加',
            style: TextStyle(fontSize: 11, color: secondaryInk),
          ),
        ),
        Expanded(
          child: TabBarView(
            children:
                [
                  AssetCategory.character,
                  AssetCategory.background,
                  AssetCategory.item,
                ].map((category) {
                  final assets = widget.project.assets
                      .where((a) => a.category == category)
                      .toList();
                  return assets.isEmpty
                      ? const Center(
                          child: Text(
                            '请先在画布中导入素材',
                            style: TextStyle(fontSize: 11),
                          ),
                        )
                      : ListView(
                          children: assets
                              .map(
                                (asset) => Draggable<AssetEntry>(
                                  data: asset,
                                  feedback: Material(
                                    child: SizedBox(
                                      width: 100,
                                      height: 100,
                                      child: ProjectImage(
                                        store: widget.store,
                                        project: widget.project,
                                        assetId: asset.id,
                                      ),
                                    ),
                                  ),
                                  child: InkWell(
                                    onTap: () => _add(asset),
                                    child: Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Column(
                                        children: [
                                          SizedBox(
                                            height: 90,
                                            child: ProjectImage(
                                              store: widget.store,
                                              project: widget.project,
                                              assetId: asset.id,
                                            ),
                                          ),
                                          Text(
                                            asset.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        );
                }).toList(),
          ),
        ),
      ],
    ),
  );
  Widget _motions() {
    final layer = active;
    return Material(
      color: surface,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '图层与动作',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
          const SizedBox(height: 12),
          ...layers.reversed.map(
            (l) => ListTile(
              dense: true,
              selected: selected == l.id,
              title: Text(
                widget.project.assetById(l.assetId)?.name ?? '图片缺失',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${l.motions.length} 个动作${l.action.isEmpty ? '' : ' · 点击事件'}',
              ),
              onTap: () {
                _stopPreview();
                setState(() => selected = l.id);
              },
            ),
          ),
          const Divider(),
          if (layer == null)
            const Text('选择一张图片，右键设置动作。')
          else ...[
            const Text(
              '按列表顺序执行；各图层同时开始',
              style: TextStyle(fontSize: 11, color: secondaryInk),
            ),
            const SizedBox(height: 8),
            ...layer.motions.asMap().entries.map(
              (entry) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${entry.key + 1}. ${entry.value.type.label} · ${entry.value.duration}s',
                            ),
                          ),
                          IconButton(
                            tooltip: '删除动作',
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () => setState(
                              () => layer.motions.removeAt(entry.key),
                            ),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            tooltip: '上移',
                            onPressed: entry.key == 0
                                ? null
                                : () => setState(() {
                                    final m = layer.motions.removeAt(entry.key);
                                    layer.motions.insert(entry.key - 1, m);
                                  }),
                            icon: const Icon(Icons.arrow_upward, size: 16),
                          ),
                          IconButton(
                            tooltip: '下移',
                            onPressed: entry.key == layer.motions.length - 1
                                ? null
                                : () => setState(() {
                                    final m = layer.motions.removeAt(entry.key);
                                    layer.motions.insert(entry.key + 1, m);
                                  }),
                            icon: const Icon(Icons.arrow_downward, size: 16),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            OutlinedButton(
              onPressed: () {
                final box = context.findRenderObject() as RenderBox;
                _context(layer, box.localToGlobal(const Offset(600, 160)));
              },
              child: const Text('添加动作 / 图片设置'),
            ),
          ],
        ],
      ),
    );
  }
}
