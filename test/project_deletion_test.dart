import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plastic_memory/editor.dart';
import 'package:plastic_memory/main.dart';
import 'package:plastic_memory/models.dart';
import 'package:plastic_memory/storage.dart';

Future<void> setup(WidgetTester tester, ProjectStore store) async {
  tester.view.physicalSize = const Size(1024, 700);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(PlasticMemoryApp(store: store));
  await tester.pumpAndSettle();
}

class ControlledDeleteStore extends ProjectStore {
  ControlledDeleteStore() : super.memory();
  bool fail = true;
  Completer<void>? gate;
  int calls = 0;

  @override
  Future<void> deleteProject(ProjectModel project) async {
    calls++;
    if (fail) throw const FileSystemException('fixture: access denied');
    if (gate != null) await gate!.future;
    await super.deleteProject(project);
  }
}

void main() {
  testWidgets(
    'library cancellation preserves work; confirmed deletion persists and keeps the draft',
    (tester) async {
      final store = ProjectStore.memory();
      final project = ProjectModel.demo();
      await store.publish(project);
      await setup(tester, store);
      await tester.tap(find.text('纷乱回忆'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('删除作品'));
      await tester.pumpAndSettle();
      expect(find.text('删除作品？'), findsOneWidget);
      expect(find.textContaining('创作草稿和原始素材文件会保留'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(await store.loadProjects(games: true), hasLength(1));
      await tester.tap(find.byTooltip('删除作品'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认删除'));
      await tester.pumpAndSettle();
      expect(find.textContaining('还没有完成的作品'), findsOneWidget);
      expect((await store.loadProjects()).single.id, project.id);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('纷乱回忆'));
      await tester.pumpAndSettle();
      expect(find.textContaining('还没有完成的作品'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'history deletes another draft; deleting the current draft returns home without reseeding',
    (tester) async {
      final store = ProjectStore.memory();
      final old = ProjectModel.empty('历史草稿');
      await store.save(old);
      await setup(tester, store);
      await tester.tap(find.text('创造回忆'));
      await tester.pumpAndSettle();
      final current = tester
          .widget<EditorPage>(find.byType(EditorPage))
          .project;
      await tester.tap(find.byTooltip('打开 / 新建项目'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('delete-draft-${old.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text(old.name), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('delete-draft-${old.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认删除'));
      await tester.pumpAndSettle();
      expect(find.text(old.name), findsNothing);
      expect((await store.loadProjects()).single.id, current.id);
      await tester.tap(find.byKey(ValueKey('delete-draft-${current.id}')));
      await tester.pumpAndSettle();
      expect(find.textContaining('删除后将返回首页'), findsOneWidget);
      await tester.tap(find.text('确认删除'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('可塑性记忆'), findsOneWidget);
      expect(find.textContaining('0 个项目  /  0 个节点'), findsOneWidget);
      expect(await store.loadProjects(), isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(PlasticMemoryApp(store: store));
      await tester.pumpAndSettle();
      expect(find.textContaining('0 个项目  /  0 个节点'), findsOneWidget);
      expect(await store.loadProjects(), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'deletion failure keeps its row and retries; busy deletion cannot repeat or dismiss',
    (tester) async {
      final store = ControlledDeleteStore();
      await store.publish(ProjectModel.demo());
      await setup(tester, store);
      await tester.tap(find.text('纷乱回忆'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('删除作品'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认删除'));
      await tester.pumpAndSettle();
      expect(find.textContaining('删除失败'), findsOneWidget);
      expect(await store.loadProjects(games: true), hasLength(1));
      store.fail = false;
      store.gate = Completer<void>();
      await tester.tap(find.text('确认删除'));
      await tester.pump();
      expect(find.text('正在删除…'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '正在删除…'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '取消'))
            .onPressed,
        isNull,
      );
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('正在删除…'), findsOneWidget);
      expect(store.calls, 2);
      store.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('还没有完成的作品'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
