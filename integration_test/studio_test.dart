import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';
import 'package:plastic_memory/assets_page.dart';
import 'package:plastic_memory/dialogue_page.dart';
import 'package:plastic_memory/editor.dart';
import 'package:plastic_memory/graph_canvas.dart';
import 'package:plastic_memory/main.dart';
import 'package:plastic_memory/models.dart';
import 'package:plastic_memory/stage.dart';
import 'package:plastic_memory/storage.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Windows authoring, native media, publication and visual smoke test',
    (tester) async {
      // Continuous home motion has its own native test. Keep authoring checks
      // deterministic and exercise the system's reduced-motion preference here.
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await windowManager.ensureInitialized();
      await windowManager.setSize(const Size(1360, 860));
      await windowManager.setTitle('可塑性记忆 · 界面验证');
      final qa = Directory(p.join(Directory.current.path, 'build', 'qa'));
      await qa.create(recursive: true);
      final work = await Directory(p.join(qa.path, 'sessions'))
          .create(recursive: true);
      final temp = await work.createTemp('session-');
      final store = ProjectStore(Directory(p.join(temp.path, 'data')));
      final project = ProjectModel.demo();

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 320, 500),
        Paint()..color = const Color(0xFFB78BA7),
      );
      canvas.drawCircle(
        const Offset(160, 140),
        70,
        Paint()..color = const Color(0xFFFFE7D8),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(65, 225, 190, 275),
          const Radius.circular(70),
        ),
        Paint()..color = const Color(0xFF676897),
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(320, 500);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final portrait = File(p.join(temp.path, '人物测试.png'));
      await portrait.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
      picture.dispose();
      final actor = (await store.importAssets(
        project,
        AssetCategory.character,
        [portrait.path],
      )).imported.single;
      final event = project.nodes.firstWhere(
        (n) => n.type == StoryNodeType.event,
      );
      event.dialogue.first
        ..sceneEnabled = true
        ..layers = [
          StageLayer(
            id: 'qa-layer',
            assetId: actor.id,
            motions: [
              StageMotion(
                type: MotionType.transform,
                duration: .3,
                x: .55,
                y: .08,
                width: .3,
                height: .75,
              ),
            ],
          ),
        ];

      final samples = 8000;
      final wave = ByteData(44 + samples * 2);
      void ascii(int offset, String text) {
        for (var i = 0; i < text.length; i++) {
          wave.setUint8(offset + i, text.codeUnitAt(i));
        }
      }

      ascii(0, 'RIFF');
      wave.setUint32(4, 36 + samples * 2, Endian.little);
      ascii(8, 'WAVE');
      ascii(12, 'fmt ');
      wave.setUint32(16, 16, Endian.little);
      wave.setUint16(20, 1, Endian.little);
      wave.setUint16(22, 1, Endian.little);
      wave.setUint32(24, 8000, Endian.little);
      wave.setUint32(28, 16000, Endian.little);
      wave.setUint16(32, 2, Endian.little);
      wave.setUint16(34, 16, Endian.little);
      ascii(36, 'data');
      wave.setUint32(40, samples * 2, Endian.little);
      final audioFile = File(p.join(temp.path, '静音测试.wav'));
      await audioFile.writeAsBytes(wave.buffer.asUint8List());
      final music = (await store.importAssets(project, AssetCategory.bgm, [
        audioFile.path,
      ])).imported.single;
      event.bgmAsset = music.id;
      await store.save(project);
      await store.publish(project);

      final screen = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: screen,
          child: PlasticMemoryApp(
            store: store,
            settings: AppSettings()..master = 0,
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> capture(String name) async {
        debugPrint('QA capture: $name');
        tester
            .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
            .hideCurrentSnackBar();
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 10),
        );
        final boundary =
            screen.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(p.join(qa.path, '$name.png'))
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      }

      await capture('01-home');
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final size in [const Size(1280, 800), const Size(1920, 1080)]) {
        // Use exact client dimensions even when the monitor is narrower than 1920.
        await tester.binding.setSurfaceSize(size);
        await tester.pumpAndSettle();
        expect(tester.getSize(find.byKey(screen)), size);
        for (final label in ['纷乱回忆', '创造回忆', '设置', '退出']) {
          expect(find.text(label).hitTestable(), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await capture('home-${size.width.toInt()}x${size.height.toInt()}');
      }
      await windowManager.setSize(const Size(1280, 800));
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      await tester.pumpAndSettle();
      final mouse = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: const Offset(0, 0));
      await mouse.moveTo(tester.getCenter(find.text('纷乱回忆')));
      await tester.pumpAndSettle();
      await capture('home-hover');
      await mouse.removePointer();
      await tester.binding.setSurfaceSize(null);
      await windowManager.setSize(const Size(1360, 860));
      await tester.pumpAndSettle();
      await tester.tap(find.text('纷乱回忆'));
      await tester.pumpAndSettle();
      await capture('08-library');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      await capture('09-settings');
      await tester.tap(find.text('保存并返回'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('创造回忆'));
      await tester.pumpAndSettle();
      expect(find.byType(EditorPage), findsOneWidget);
      await capture('02-new-canvas');
      await tester.tap(find.byTooltip('打开 / 新建项目'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(project.name));
      await tester.pumpAndSettle();
      final edited = tester.widget<EditorPage>(find.byType(EditorPage)).project;
      final graph = tester.state<GraphCanvasState>(find.byType(GraphCanvas));
      graph.fit();
      await tester.pumpAndSettle();
      await capture('03-story-graph');
      await tester.tap(find.text('导入素材 (${edited.assets.length})'));
      await tester.pumpAndSettle();
      expect(find.byType(AssetsPage), findsOneWidget);
      await tester.tap(find.text('背景图'));
      await tester.pumpAndSettle();
      final drop = tester
          .widgetList<DropTarget>(find.byType(DropTarget))
          .firstWhere((d) => d.enable);
      drop.onDragDone!(
        DropDoneDetails(
          files: [DropItemFile(portrait.path)],
          localPosition: Offset.zero,
          globalPosition: Offset.zero,
        ),
      );
      await tester.pumpAndSettle();
      for (var i = 0; i < 30 && edited.assets.length < 3; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        edited.assets.where((a) => a.category == AssetCategory.background),
        hasLength(1),
      );
      await capture('04-assets');
      await tester.pageBack();
      await tester.pumpAndSettle();
      final editedEvent = edited.nodeById(event.id)!;
      graph.centerOn(editedEvent);
      await tester.pumpAndSettle();
      final nodeFinder = find.byKey(ValueKey('node-${event.id}'));
      await tester.tap(nodeFinder);
      await tester.pump(const Duration(milliseconds: 70));
      await tester.tap(nodeFinder);
      await tester.pumpAndSettle();
      expect(find.byType(DialoguePage), findsOneWidget);
      await capture('05-dialogue');
      await tester.tap(find.byTooltip('制作演出').first);
      await tester.pumpAndSettle();
      expect(find.byType(StageEditor), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture('06-stage');
      final layer = find.byKey(const ValueKey('stage-layer-qa-layer'));
      await tester.tap(layer, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('变化（移动 / 缩放）'));
      await tester.pumpAndSettle();
      await tester.drag(layer, const Offset(50, 15));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存终态'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('加入动作列表'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存并退出'));
      await tester.pumpAndSettle();
      debugPrint('QA stage saved');
      expect(editedEvent.dialogue.first.layers.single.motions, hasLength(2));
      await tester.tap(find.text('完成编辑'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('测试运行'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('开始这段回忆'));
      await tester.pump(const Duration(seconds: 2));
      await capture('07-player');
      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      for (var i = 0; i < 50 && find.text('测试进度已存档').evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('测试进度已存档'), findsOneWidget);
      final previewSave = (await store.loadPlayerProgress(
        edited,
        preview: true,
      ))!;
      expect(previewSave.layers.single.motions, isEmpty);
      expect(previewSave.bgm, music.id);
      expect(await store.loadPlayerProgress(edited), isNull);
      await tester.tap(find.text('跳过'));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(find.text('请选择'), findsOneWidget);
      expect(find.text('停止跳过'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.f9);
      for (var i = 0; i < 50 && find.text('已读取存档').evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('已读取存档'), findsOneWidget);
      expect(find.text('请选择'), findsNothing);
      expect(
        tester.widget<StageView>(find.byType(StageView)).layers.single.toJson(),
        previewSave.layers.single.toJson(),
      );
      await tester.binding.setSurfaceSize(const Size(1024, 700));
      await tester.pumpAndSettle();
      await capture('14-player-quick-controls');
      await tester.binding.setSurfaceSize(null);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存并退出'));
      await tester.pumpAndSettle();
      final reopened = (await ProjectStore(
        store.root,
      ).loadProjects()).firstWhere((p) => p.id == edited.id);
      expect(
        reopened.nodeById(event.id)!.dialogue.first.layers.single.motions,
        hasLength(2),
      );

      await windowManager.setFullScreen(true);
      expect(await windowManager.isFullScreen(), isTrue);
      await windowManager.setFullScreen(false);
      final audio = AudioPlayer();
      await audio.play(DeviceFileSource(audioFile.path), volume: 0);
      expect((await audio.getDuration())!.inMilliseconds, greaterThan(0));
      await audio.dispose();

      // Delete only this test session's copies. Cover native filesystem writes,
      // both entry points, and reopening an intentionally empty library.
      Future<void> waitFor(Finder finder) async {
        for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pumpAndSettle();
        expect(finder, findsOneWidget);
      }

      Future<void> waitGone(Finder finder) async {
        for (var i = 0; i < 100 && finder.evaluate().isNotEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pumpAndSettle();
        expect(finder, findsNothing);
      }

      await tester.binding.setSurfaceSize(const Size(1024, 700));
      await tester.pumpAndSettle();
      await tester.tap(find.text('纷乱回忆'));
      await waitFor(find.text('游玩'));
      await tester.tap(find.text('游玩'));
      await waitFor(find.text('开始这段回忆'));
      await tester.tap(find.text('开始这段回忆'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('跳过'));
      await waitFor(find.text('请选择'));
      await tester.tap(find.text('存档'));
      await waitFor(find.text('进度已存档'));
      final game = (await store.loadProjects(games: true)).single;
      final gameSave = (await store.loadPlayerProgress(game))!;
      expect(gameSave.position['waitingForChoice'], isTrue);
      final saveFile = File(
        p.join(store.projectDirectory(game).path, 'play-save.json'),
      );
      expect(await saveFile.length(), lessThan(8192));
      debugPrint('Player save size: ${await saveFile.length()} bytes');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('游玩'));
      await waitFor(find.text('开始这段回忆'));
      await tester.tap(find.text('读档'));
      await waitFor(find.text('请选择'));
      expect(
        (await ProjectStore(store.root).loadPlayerProgress(game))!.position,
        gameSave.position,
      );
      await capture('15-player-restored-choice');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await waitFor(find.byTooltip('删除作品'));
      await tester.tap(find.byTooltip('删除作品'));
      await tester.pumpAndSettle();
      await capture('10-delete-game');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(await store.loadProjects(games: true), hasLength(1));
      await tester.tap(find.byTooltip('删除作品'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认删除'));
      await waitFor(find.textContaining('还没有完成的作品'));
      expect(await saveFile.exists(), isFalse);
      expect(await store.loadProjects(games: true), isEmpty);
      expect(await store.projectDirectory(edited).exists(), isTrue);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('创造回忆'));
      await tester.pumpAndSettle();
      final current = tester
          .widget<EditorPage>(find.byType(EditorPage))
          .project;
      await tester.tap(find.byTooltip('打开 / 新建项目'));
      await waitFor(find.text('打开创作项目'));
      await capture('11-project-history');
      final drafts = await store.loadProjects();
      for (final draft in drafts.where((draft) => draft.id != current.id)) {
        final button = find.byKey(ValueKey('delete-draft-${draft.id}'));
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        await tester.tap(find.text('确认删除'));
        await waitGone(button);
        expect(await store.projectDirectory(draft).exists(), isFalse);
      }
      await tester.tap(find.byKey(ValueKey('delete-draft-${current.id}')));
      await tester.pumpAndSettle();
      await capture('12-delete-current-project');
      await tester.tap(find.text('确认删除'));
      await waitFor(find.textContaining('0 个项目  /  0 个节点'));
      await tester.pump(const Duration(seconds: 3));
      expect(await store.loadProjects(), isEmpty);
      expect(await portrait.exists(), isTrue);
      expect(await audioFile.exists(), isTrue);
      await tester.pumpWidget(const SizedBox());
      final emptyStore = ProjectStore(store.root);
      await tester.pumpWidget(
        RepaintBoundary(
          key: screen,
          child: PlasticMemoryApp(store: emptyStore),
        ),
      );
      await waitFor(find.textContaining('0 个项目  /  0 个节点'));
      expect(await emptyStore.loadProjects(), isEmpty);
      expect(await emptyStore.loadProjects(games: true), isEmpty);
      await capture('13-home-after-deletion');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
