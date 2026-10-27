import 'package:audioplayers/audioplayers.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'models.dart';
import 'storage.dart';
import 'ui.dart';

class AssetsPage extends StatefulWidget {
  const AssetsPage({super.key, required this.project, required this.store});
  final ProjectModel project;
  final ProjectStore store;
  @override
  State<AssetsPage> createState() => _AssetsPageState();
}

class _AssetsPageState extends State<AssetsPage>
    with SingleTickerProviderStateMixin {
  late final TabController tabs = TabController(length: 7, vsync: this);
  final AudioPlayer audio = AudioPlayer()..positionUpdater = null;
  bool dragging = false, busy = false;
  String? playing;
  @override
  void initState() {
    super.initState();
    tabs.addListener(_tabChanged);
  }

  void _tabChanged() {
    audio.stop();
    if (mounted) setState(() => playing = null);
  }

  @override
  void dispose() {
    tabs.removeListener(_tabChanged);
    tabs.dispose();
    audio.dispose();
    super.dispose();
  }

  Future<void> _import(List<String> paths, AssetCategory category) async {
    if (busy || paths.isEmpty) return;
    setState(() => busy = true);
    try {
      final result = await widget.store.importAssets(
        widget.project,
        category,
        paths,
      );
      if (!mounted) return;
      notify(
        context,
        '已导入 ${result.imported.length} 个${category.label}素材${result.errors.isEmpty ? '' : '；${result.errors.join('；')}'}',
      );
    } catch (e) {
      if (mounted) notify(context, '导入失败：$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _pick() async {
    final category = AssetCategory.values[tabs.index];
    try {
      final files = await openFiles(
        acceptedTypeGroups: [
          XTypeGroup(label: category.label, extensions: category.extensions),
        ],
      );
      await _import(files.map((f) => f.path).toList(), category);
    } catch (e) {
      if (mounted) notify(context, '无法打开文件：$e');
    }
  }

  Future<void> _preview(AssetEntry asset) async {
    if (asset.category.isImage) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(asset.name),
          content: SizedBox(
            width: 700,
            height: 460,
            child: ProjectImage(
              store: widget.store,
              project: widget.project,
              assetId: asset.id,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
      return;
    }
    try {
      if (playing == asset.id) {
        await audio.stop();
        setState(() => playing = null);
        return;
      }
      final file = widget.store.assetFile(widget.project, asset.id);
      if (file == null) return;
      await audio.play(DeviceFileSource(file.path));
      if (mounted) setState(() => playing = asset.id);
    } catch (e) {
      if (mounted) notify(context, '此音频无法播放，请检查文件或尝试 WAV / MP3 格式。');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('导入素材'),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 18),
          child: FilledButton.icon(
            onPressed: busy ? null : _pick,
            icon: const Icon(Icons.file_open_outlined),
            label: const Text('选择文件'),
          ),
        ),
      ],
      bottom: TabBar(
        controller: tabs,
        isScrollable: true,
        tabs: AssetCategory.values.map((c) => Tab(text: c.label)).toList(),
      ),
    ),
    body: Column(
      children: [
        if (busy) const LinearProgressIndicator(),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Text(
            '将文件拖入对应分类，或点击“选择文件”。素材会复制到项目文件夹，原文件保持原样。',
            style: TextStyle(color: ink.withValues(alpha: .7)),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: tabs,
            children: AssetCategory.values.map((category) {
              final assets = widget.project.assets
                  .where((a) => a.category == category)
                  .toList();
              return DropTarget(
                enable:
                    !busy &&
                    tabs.index == category.index &&
                    (ModalRoute.of(context)?.isCurrent ?? true),
                onDragEntered: (_) => setState(() => dragging = true),
                onDragExited: (_) => setState(() => dragging = false),
                onDragDone: (details) {
                  setState(() => dragging = false);
                  _import(details.files.map((f) => f.path).toList(), category);
                },
                child: Container(
                  margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  decoration: BoxDecoration(
                    color: dragging ? raisedSurface : surface,
                    borderRadius: memoryRadius,
                    border: Border.all(
                      color: dragging ? accent : hairline,
                      width: 1,
                    ),
                  ),
                  child: assets.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                category.isImage
                                    ? Icons.add_photo_alternate_outlined
                                    : Icons.audio_file_outlined,
                                size: 54,
                                color: accent,
                              ),
                              const SizedBox(height: 18),
                              Text(
                                '拖入${category.label}素材',
                                style: const TextStyle(fontSize: 20),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                category.extensions.join(' · ').toUpperCase(),
                                style: const TextStyle(color: secondaryInk),
                              ),
                            ],
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.all(18),
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 220,
                                mainAxisExtent: 180,
                                crossAxisSpacing: 14,
                                mainAxisSpacing: 14,
                              ),
                          itemCount: assets.length,
                          itemBuilder: (context, index) {
                            final asset = assets[index];
                            return Card(
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () => _preview(asset),
                                child: Column(
                                  children: [
                                    Expanded(
                                      child: category.isImage
                                          ? ProjectImage(
                                              store: widget.store,
                                              project: widget.project,
                                              assetId: asset.id,
                                            )
                                          : Icon(
                                              playing == asset.id
                                                  ? Icons.stop_circle_outlined
                                                  : Icons.play_circle_outline,
                                              size: 48,
                                              color: accent,
                                            ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: Text(
                                        asset.name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    ),
  );
}
