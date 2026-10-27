import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plastic_memory/dialogue_page.dart';
import 'package:plastic_memory/editor.dart';
import 'package:plastic_memory/graph_canvas.dart';
import 'package:plastic_memory/main.dart';
import 'package:plastic_memory/models.dart';
import 'package:plastic_memory/player.dart';
import 'package:plastic_memory/storage.dart';
import 'package:plastic_memory/ui.dart';

Future<void> desktop(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1360, 820);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('dark home keeps all entries visible at desktop sizes', (
    tester,
  ) async {
    await desktop(tester);
    await tester.pumpWidget(const PlasticMemoryApp());
    for (final size in [
      const Size(1280, 800),
      const Size(1920, 1080),
      const Size(1024, 700),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.text('可塑性记忆'))).brightness,
        Brightness.dark,
      );
      for (final label in ['纷乱回忆', '创造回忆', '设置', '退出']) {
        expect(find.text(label).hitTestable(), findsOneWidget);
      }
      expect(find.text('MEMORY STUDIO / 0.2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets(
    'home exposes exactly the four main entries and creation opens centered canvas',
    (tester) async {
      await desktop(tester);
      final store = ProjectStore.memory();
      await tester.pumpWidget(PlasticMemoryApp(store: store));
      await tester.pumpAndSettle();
      for (final text in ['纷乱回忆', '创造回忆', '设置', '退出']) {
        expect(find.text(text), findsOneWidget);
      }
      await tester.tap(find.text('创造回忆'));
      await tester.pumpAndSettle();
      final editor = tester.widget<EditorPage>(find.byType(EditorPage));
      expect(editor.project.nodes, hasLength(1));
      final nodeCenter = tester.getCenter(
        find.byKey(ValueKey('node-${editor.project.startNodeId}')),
      );
      expect(nodeCenter.dx, closeTo(680, 2));
      expect(find.text('节点工具栏'), findsOneWidget);
      expect(find.text('人物'), findsOneWidget);
      expect(find.text('保存并退出'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('保存并退出'));
      await tester.pumpAndSettle();
      expect(find.text('可塑性记忆'), findsOneWidget);
      expect((await store.loadProjects()).length, 2);
      expect(find.textContaining('2 个项目'), findsOneWidget);
    },
  );
  testWidgets('node dragging uses scene coordinates after zoom', (
    tester,
  ) async {
    await desktop(tester);
    final project = ProjectModel.empty('拖动');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GraphCanvas(
            project: project,
            selectedId: project.startNodeId,
            onSelect: (_) {},
            onChanged: () {},
            onOpen: (_) {},
            onContext: (_, _) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final state = tester.state<GraphCanvasState>(find.byType(GraphCanvas));
    state.transform.value = Matrix4.identity()
      ..translateByDouble(-400, -270, 0, 1)
      ..scaleByDouble(1.5, 1.5, 1, 1);
    await tester.pump();
    final start = project.nodes.single.position;
    await tester.drag(
      find.byKey(ValueKey('node-${project.startNodeId}')),
      const Offset(90, 45),
    );
    await tester.pump(const Duration(milliseconds: 400));
    final moved = project.nodes.single.position - start;
    expect(moved.dx, closeTo(60, .1));
    expect(moved.dy, closeTo(30, .1));
    expect(tester.takeException(), isNull);
  });
  testWidgets('Enter commits one dialogue and resets character selection', (
    tester,
  ) async {
    await desktop(tester);
    final project = ProjectModel.empty('文本');
    final node = project.addNode(StoryNodeType.event, Offset.zero);
    await tester.pumpWidget(
      MaterialApp(
        theme: memoryTheme(),
        home: DialoguePage(
          project: project,
          node: node,
          store: ProjectStore.memory(),
        ),
      ),
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('旁白').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '春天的风吹过校园。');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(node.dialogue, hasLength(1));
    expect(node.dialogue.single.text, '春天的风吹过校园。');
    expect(node.dialogue.single.speaker, '旁白');
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'demo plays through a branch and automatically returns to opening',
    (tester) async {
      await desktop(tester);
      final project = ProjectModel.demo();
      await tester.pumpWidget(
        MaterialApp(
          theme: memoryTheme(),
          home: PlayerPage(
            project: project,
            store: ProjectStore.memory(),
            settings: AppSettings()..textSpeed = 100,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('开始这段回忆'));
      await tester.pump(const Duration(seconds: 1));
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump(const Duration(seconds: 1));
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.text('我记得。'), findsOneWidget);
      expect(find.text('我想再听你说一次。'), findsOneWidget);
      await tester.tap(find.text('我记得。'));
      await tester.pump(const Duration(seconds: 1));
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.text('开始这段回忆'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
  testWidgets('settings survive navigation and save to the store', (
    tester,
  ) async {
    await desktop(tester);
    final store = ProjectStore.memory();
    await tester.pumpWidget(PlasticMemoryApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.tapAt(
      tester.getTopLeft(find.byType(Slider).first) + const Offset(70, 24),
    );
    await tester.pump();
    final volume = tester.widget<Slider>(find.byType(Slider).first).value;
    await tester.tap(find.text('保存并返回'));
    await tester.pumpAndSettle();
    expect((await store.loadSettings()).master, volume);
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(find.byType(Slider).first).value, volume);
    expect(tester.takeException(), isNull);
  });
}
