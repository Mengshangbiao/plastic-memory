import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_manager/window_manager.dart';
import 'package:plastic_memory/home_view.dart';
import 'package:plastic_memory/main.dart';
import 'package:plastic_memory/storage.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('live home: two sizes, meteor burst, hover and navigation', (
    tester,
  ) async {
    await windowManager.ensureInitialized();
    await windowManager.setSize(const Size(1360, 860));
    await windowManager.setTitle('可塑性记忆 · 流光验证');
    await windowManager.show();
    await windowManager.focus();
    await binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => binding.setSurfaceSize(null));
    final output = Directory('build/qa/flow');
    await output.create(recursive: true);
    final screen = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: screen,
        child: PlasticMemoryApp(store: ProjectStore.memory()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1600));
    final state = tester.state<MemoryHomeViewState>(
      find.byType(MemoryHomeView),
    );
    expect(state.motionRunning, isTrue);
    expect(find.text('尚未进入'), findsNWidgets(2));

    Future<void> capture(String name) async {
      final boundary =
          screen.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('${output.path}/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    }

    await capture('home-1280x800');
    final frames = <Map<String, Object>>[];
    final clock = Stopwatch()..start();
    final phaseStart = state.flow.phases[0];
    var i = 0;
    while (clock.elapsedMilliseconds < 14000) {
      final name = 'frame-${i.toString().padLeft(3, '0')}';
      final time = clock.elapsedMilliseconds;
      final meteors = state.flow.meteors
          .where((meteor) => meteor.opacity(state.flow.seconds) > 0)
          .length;
      await capture(name);
      frames.add({
        'file': '$name.png',
        'ms': time,
        'flowSeconds': state.flow.seconds,
        'running': state.motionRunning,
        'meteors': meteors,
      });
      await tester.pump(const Duration(milliseconds: 50));
      i++;
    }
    clock.stop();
    final travelled = (state.flow.phases[0] - phaseStart) % 1;
    await File('${output.path}/frames.json').writeAsString(
      jsonEncode({
        'durationMs': clock.elapsedMilliseconds,
        'frames': frames,
        'idleLapFraction': travelled,
      }),
    );
    debugPrint(
      'Flow capture: ${frames.length} frames, ${clock.elapsedMilliseconds}ms, lap $travelled',
    );
    expect(travelled, inInclusiveRange(.45, .65));
    expect(frames.any((frame) => (frame['meteors'] as int) > 0), isTrue);

    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('纷乱回忆')));
    await tester.pump(const Duration(milliseconds: 700));
    expect(state.flow.period(0), closeTo(12, .01));
    await capture('hover-library');
    await mouse.moveTo(tester.getCenter(find.text('创造回忆')));
    await tester.pump(const Duration(milliseconds: 700));
    expect(state.flow.period(1), closeTo(10, .01));
    await capture('hover-creation');
    await mouse.removePointer();
    await tester.pump(const Duration(milliseconds: 700));
    expect(state.flow.period(1), closeTo(28, .01));

    await binding.setSurfaceSize(const Size(1920, 1080));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getSize(find.byKey(screen)), const Size(1920, 1080));
    for (final label in ['纷乱回忆', '创造回忆', '设置', '退出']) {
      expect(find.text(label).hitTestable(), findsOneWidget);
    }
    await capture('home-1920x1080');
    await binding.setSurfaceSize(const Size(1280, 800));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('纷乱回忆'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(state.motionRunning, isFalse);
    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 1600));
    expect(state.motionRunning, isTrue);
    expect(find.text('上次进入 · 刚刚'), findsOneWidget);
    await capture('home-after-visit');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
