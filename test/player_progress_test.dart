import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:plastic_memory/audio_bus.dart';
import 'package:plastic_memory/models.dart';
import 'package:plastic_memory/player.dart';
import 'package:plastic_memory/player_save.dart';
import 'package:plastic_memory/stage.dart';
import 'package:plastic_memory/storage.dart';
import 'package:plastic_memory/ui.dart';

PlayerSave checkpoint(
  StorySession session, {
  List<StageLayer> layers = const [],
  String background = '',
  String bgm = '',
}) => PlayerSave(
  projectId: session.project.id,
  savedAt: DateTime(2026, 10, 27, 12),
  position: session.checkpoint(),
  layers: layers,
  background: background,
  blur: false,
  bgm: bgm,
);

Future<void> mountPlayer(
  WidgetTester tester,
  ProjectStore store,
  ProjectModel project, {
  bool preview = false,
}) async {
  tester.view.physicalSize = const Size(1024, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: memoryTheme(),
      home: PlayerPage(
        project: project,
        store: store,
        settings: AppSettings()..textSpeed = 100,
        preview: preview,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> skipToChoice(WidgetTester tester) async {
  await tester.tap(find.text('开始这段回忆'));
  await tester.pump();
  await tester.tap(find.text('跳过'));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();
  expect(find.text('请选择'), findsOneWidget);
  expect(find.text('停止跳过'), findsNothing);
}

class FailingProgressStore extends ProjectStore {
  FailingProgressStore() : super.memory();
  bool fail = true;
  Completer<void>? writeGate;
  @override
  Future<void> savePlayerProgress(
    ProjectModel project,
    PlayerSave save, {
    bool preview = false,
  }) async {
    if (fail) throw const FileSystemException('fixture: disk full');
    if (writeGate != null) await writeGate!.future;
    await super.savePlayerProgress(project, save, preview: preview);
  }

  @override
  Future<PlayerSave?> loadPlayerProgress(
    ProjectModel project, {
    bool preview = false,
  }) async {
    if (fail) throw const FormatException('fixture: damaged save');
    return super.loadPlayerProgress(project, preview: preview);
  }
}

void main() {
  test('checkpoint restores choices and selected history without advancing or rerolling', () {
    final project = ProjectModel.demo();
    final session = StorySession(project)
      ..advance()
      ..advance()
      ..advance();
    expect(session.options, hasLength(2));
    final savedChoice = jsonDecode(jsonEncode(session.checkpoint())) as Json;
    final choice = session.options.first;
    session.choose(choice);
    final selected = session.checkpoint();
    final restored = StorySession(project)..restore(selected);
    expect(restored.nodeId, session.nodeId);
    expect(restored.selectedChoices, {choice.id});
    restored.restore(savedChoice);
    expect(
      restored.options.map((o) => o.id),
      project.nodes
          .where((n) => n.type == StoryNodeType.choice)
          .map((n) => n.id),
    );
    expect(restored.lineIndex, 1);
    expect(restored.selectedChoices, isEmpty);
    restored.choose(choice);
    expect(restored.nodeId, session.nodeId);
  });

  test('stable dialogue IDs restore after reordering; invalid positions leave the session untouched', () {
    final project = ProjectModel.demo();
    final session = StorySession(project)..advance();
    final saved = session.checkpoint();
    final first = session.line!;
    session.node.dialogue.insert(0, DialogueLine(id: 'inserted', text: '新增对白'));
    session.restore(saved);
    expect(session.line, first);
    expect(session.lineIndex, 1);
    final before = session.checkpoint();
    for (final invalid in [
      {...saved, 'nodeId': 'missing'},
      {...saved, 'lineId': 'deleted-line'},
      {...saved, 'lineId': null},
      {
        ...saved,
        'selectedChoices': ['missing-choice'],
      },
      {...saved, 'waitingForChoice': true},
    ]) {
      expect(() => session.restore(invalid), throwsFormatException);
      expect(session.checkpoint(), before);
    }
  });

  test('checkpoints preserve conditional options, reject other projects and missing scene assets', () {
    final project = ProjectModel.demo();
    final session = StorySession(project)
      ..advance()
      ..advance()
      ..advance();
    final choice = session.options.first;
    session.selectedChoices.add(choice.id);
    session.options.last.requiredChoices = [choice.id];
    final save = checkpoint(session);
    final restored = StorySession(project)..restore(save.position);
    expect(restored.options, hasLength(2));
    expect(restored.selectedChoices, {choice.id});
    expect(() => save.validate(ProjectModel.demo()), throwsFormatException);
    expect(
      () => checkpoint(session, background: 'missing').validate(project),
      throwsFormatException,
    );
    expect(
      () => checkpoint(session, bgm: 'missing').validate(project),
      throwsFormatException,
    );
    expect(
      () => PlayerSave.fromJson({...save.toJson(), 'version': 99}),
      throwsFormatException,
    );
  });

  test('small disk saves survive reopening and publication, remain isolated, and are removed with their copy', () async {
    final temp = await Directory.systemTemp.createTemp('memory_progress_');
    addTearDown(() => temp.delete(recursive: true));
    final store = ProjectStore(temp);
    final draft = ProjectModel.demo();
    await store.publish(draft);
    final game = (await store.loadProjects(games: true)).single;
    final session = StorySession(game)..advance();
    final originalProject = await File(
      p.join(store.projectDirectory(game).path, 'project.json'),
    ).readAsString();
    await store.savePlayerProgress(game, checkpoint(session));
    session.advance();
    await store.savePlayerProgress(game, checkpoint(session));
    final file = File(
      p.join(store.projectDirectory(game).path, 'play-save.json'),
    );
    expect(await file.length(), lessThan(4096));
    expect(await File('${file.path}.bak').exists(), isTrue);
    expect(
      await File(p.join(store.projectDirectory(game).path, 'project.json'))
          .readAsString(),
      originalProject,
    );
    final reopened = ProjectStore(temp);
    expect(
      (await reopened.loadPlayerProgress(game))!.position,
      session.checkpoint(),
    );
    expect(await reopened.loadPlayerProgress(draft, preview: true), isNull);
    expect(await reopened.loadPlayerProgress(ProjectModel.demo()), isNull);
    final preview = StorySession(draft)..advance();
    await store.savePlayerProgress(draft, checkpoint(preview), preview: true);
    await store.publish(draft);
    expect(
      (await store.loadPlayerProgress(game))!.position,
      session.checkpoint(),
    );
    expect(
      (await store.loadPlayerProgress(draft, preview: true))!.position,
      preview.checkpoint(),
    );
    await store.deleteProject(game);
    expect(await file.exists(), isFalse);
    expect(await File('${file.path}.bak').exists(), isFalse);
    expect(await store.loadPlayerProgress(draft, preview: true), isNotNull);
    await expectLater(
      store.savePlayerProgress(game, checkpoint(session)),
      throwsStateError,
    );
    expect(await store.projectDirectory(game).exists(), isFalse);
    await store.deleteProject(draft);
    expect(await store.loadPlayerProgress(draft, preview: true), isNull);
  });

  test('corrupt disk saves are reported without rewriting them', () async {
    final temp = await Directory.systemTemp.createTemp('memory_bad_progress_');
    addTearDown(() => temp.delete(recursive: true));
    final store = ProjectStore(temp);
    final project = ProjectModel.demo();
    await store.save(project);
    final file = File(
      p.join(store.projectDirectory(project).path, 'play-save.json'),
    );
    await file.writeAsString('{broken');
    await expectLater(store.loadPlayerProgress(project), throwsFormatException);
    expect(await file.readAsString(), '{broken');
    final session = StorySession(project)..advance();
    await store.savePlayerProgress(project, checkpoint(session));
    expect(await store.loadPlayerProgress(project), isNotNull);
  });

  test(
    'audio tracks inherited BGM through silent fast-forward and restoration',
    () async {
      final project = ProjectModel.demo();
      final audio = AudioBus(
        project,
        ProjectStore.memory(),
        AppSettings(),
        onError: fail,
      );
      addTearDown(audio.dispose);
      final event = project.nodes.firstWhere(
        (n) => n.type == StoryNodeType.event,
      )..bgmAsset = 'node-music';
      audio.enter(event, event.dialogue.first, nodeChanged: true);
      expect(audio.currentBgm, 'node-music');
      audio.enter(
        event,
        DialogueLine(id: 'replace', bgmMode: 'replace', bgmAsset: 'line-music'),
        nodeChanged: false,
        silent: true,
      );
      audio.enter(
        event,
        DialogueLine(id: 'inherit'),
        nodeChanged: false,
        silent: true,
      );
      expect(audio.currentBgm, 'line-music');
      audio.stopSpeech();
      expect(audio.currentBgm, 'line-music');
      audio.restore('saved-music');
      expect(audio.currentBgm, 'saved-music');
      audio.enter(
        event,
        DialogueLine(id: 'stop', bgmMode: 'stop'),
        nodeChanged: false,
        silent: true,
      );
      expect(audio.currentBgm, '');
    },
  );

  testWidgets(
    'quick save/load works at choices and after reopening; skip never chooses for the player',
    (tester) async {
      final store = ProjectStore.memory();
      final project = ProjectModel.demo()..isBuild = true;
      await mountPlayer(tester, store, project);
      await tester.tap(find.text('读档'));
      await tester.pumpAndSettle();
      expect(find.textContaining('还没有存档'), findsOneWidget);
      await skipToChoice(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      await tester.pumpAndSettle();
      final saved = (await store.loadPlayerProgress(project))!;
      expect(saved.position['waitingForChoice'], isTrue);
      expect(saved.position['selectedChoices'], isEmpty);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('请选择'), findsOneWidget);
      await tester.tap(find.text('我记得。'));
      await tester.pumpAndSettle();
      expect(find.text('请选择'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.f9);
      await tester.pumpAndSettle();
      expect(find.text('请选择'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await mountPlayer(tester, store, project);
      await tester.tap(find.text('读档'));
      await tester.pumpAndSettle();
      expect(find.text('请选择'), findsOneWidget);
      expect(find.text('我记得。'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'loading restores inherited scene and music instead of carrying over the live scene',
    (tester) async {
      final project = ProjectModel.empty('场景存档');
      final a = project.addNode(StoryNodeType.event, Offset.zero);
      final b = project.addNode(StoryNodeType.event, Offset.zero);
      final ending = project.addNode(StoryNodeType.ending, Offset.zero);
      for (final (id, category) in [
        ('image-a', AssetCategory.background),
        ('image-b', AssetCategory.background),
        ('music-a', AssetCategory.bgm),
      ]) {
        project.assets.add(
          AssetEntry(id: id, name: id, category: category, path: id),
        );
      }
      a.backgroundAsset = 'image-a';
      a.bgmAsset = 'music-a';
      a.dialogue.add(
        DialogueLine(
          id: 'a',
          text: '第一句',
          sceneEnabled: true,
          layers: [
            StageLayer(
              id: 'actor',
              assetId: 'image-a',
              motions: [
                StageMotion(type: MotionType.transform, x: .7, duration: 2),
              ],
            ),
          ],
        ),
      );
      b.dialogue.add(DialogueLine(id: 'b', text: '继承上一句的场景'));
      ending.backgroundAsset = 'image-b';
      ending.dialogue.add(
        DialogueLine(id: 'end', text: '结局', sceneEnabled: true),
      );
      project.connect(project.startNodeId, a.id);
      project.connect(a.id, b.id);
      project.connect(b.id, ending.id);
      final store = ProjectStore.memory();
      await mountPlayer(tester, store, project);
      await tester.tap(find.text('开始这段回忆'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.text('继承上一句的场景'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      await tester.pumpAndSettle();
      expect((await store.loadPlayerProgress(project))!.bgm, 'music-a');
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(
        tester.widget<StageView>(find.byType(StageView)).background,
        'image-b',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.f9);
      await tester.pumpAndSettle();
      final stage = tester.widget<StageView>(find.byType(StageView));
      expect(stage.background, 'image-a');
      expect(stage.layers.single.x, closeTo(.7, .001));
      expect(stage.layers.single.motions, isEmpty);
      expect(find.text('继承上一句的场景'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'skip stops on manual input, lost focus, ending, error and disposal',
    (tester) async {
      final project = ProjectModel.empty('跳过测试');
      final event = project.addNode(StoryNodeType.event, Offset.zero);
      final ending = project.addNode(StoryNodeType.ending, Offset.zero);
      event.dialogue.addAll(
        List.generate(8, (i) => DialogueLine(id: 'line-$i', text: '对白 $i')),
      );
      ending.dialogue.add(DialogueLine(id: 'ending', text: '结局保留'));
      project.connect(project.startNodeId, event.id);
      project.connect(event.id, ending.id);
      await mountPlayer(tester, ProjectStore.memory(), project);
      await tester.tap(find.text('开始这段回忆'));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.pump(const Duration(milliseconds: 130));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('对白 1'), findsOneWidget);
      await tester.tap(find.text('跳过'));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('对白 1'), findsOneWidget);
      expect(find.text('停止跳过'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.tap(find.text('跳过'));
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('结局保留'), findsOneWidget);
      expect(find.text('停止跳过'), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('开始这段回忆'), findsNothing);
      await tester.tap(find.text('回到开幕'));
      await tester.pumpAndSettle();
      event.outgoing.clear();
      await tester.tap(find.text('开始这段回忆'));
      await tester.pump();
      await tester.tap(find.text('跳过'));
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.textContaining('还没有连接后续节点'), findsOneWidget);
      expect(find.text('停止跳过'), findsNothing);
      await tester.tap(find.text('回到开幕').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('开始这段回忆'));
      await tester.pump();
      await tester.tap(find.text('跳过'));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'save failures do not report success; loading failures retain progress; saving stops skip',
    (tester) async {
      final project = ProjectModel.demo();
      final store = FailingProgressStore();
      await mountPlayer(tester, store, project);
      await tester.tap(find.text('开始这段回忆'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('存档'));
      await tester.pumpAndSettle();
      expect(find.textContaining('存档失败'), findsOneWidget);
      await tester.tap(find.text('读档'));
      await tester.pumpAndSettle();
      expect(find.textContaining('无法读档'), findsOneWidget);
      expect(find.text('春天的风吹过校园，记忆像花瓣一样落在掌心。'), findsOneWidget);
      store.fail = false;
      store.writeGate = Completer<void>();
      await tester.tap(find.text('跳过'));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('停止跳过'), findsNothing);
      expect(find.text('春天的风吹过校园，记忆像花瓣一样落在掌心。'), findsOneWidget);
      store.writeGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('进度已存档'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
