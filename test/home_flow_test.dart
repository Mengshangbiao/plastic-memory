import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:plastic_memory/home_flow.dart';
import 'package:plastic_memory/home_view.dart';
import 'package:plastic_memory/main.dart';
import 'package:plastic_memory/storage.dart';
import 'package:plastic_memory/ui.dart';

void advance(HomeFlow flow, double seconds) {
  for (var i = 0; i < (seconds * 30).round(); i++) {
    flow.advance(const Duration(microseconds: 33333));
  }
}

void main() {
  test('a departing hover keeps its own tip through colour recovery', () {
    final flow = HomeFlow();
    addTearDown(flow.dispose);
    advance(flow, 20);
    flow.setHovered(0, true);
    advance(flow, .6);
    flow.setHovered(0, false);
    advance(flow, .3);
    expect(flow.highlightStrength(0), greaterThan(0));
    expect(flow.highlightStrength(1), 0);
    expect(flow.period(0), greaterThan(12));
    expect(flow.period(0), lessThan(28));
    advance(flow, 1);
    expect(flow.period(0), 28);
    expect(flow.highlightStrength(1), greaterThan(0));
  });
  test('one lap takes 28 seconds; hover preserves phase and eases speed', () {
    final flow = HomeFlow();
    addTearDown(flow.dispose);
    advance(flow, 10);
    expect(flow.phases.first, closeTo(10 / 28, .001));
    final before = flow.phases.first;
    flow.setHovered(0, true);
    expect(flow.phases.first, before);
    advance(flow, .3);
    expect(flow.period(0), closeTo(12, .001));
    expect(flow.tipColor(0).toARGB32(), sorrow.toARGB32());
    flow.setHovered(0, false);
    advance(flow, .6);
    expect(flow.period(0), closeTo(28, .001));
    expect(HSVColor.fromColor(flow.tipColor(0)).saturation, closeTo(.2, .01));
    flow.setFocused(1, true);
    advance(flow, .3);
    expect(flow.period(1), closeTo(10, .001));
    expect(flow.highlightedCard, 1);
    expect(flow.tipColor(1).toARGB32(), joy.toARGB32());
  });

  test('one highlighted card and at most one visible dust particle over two minutes', () {
    final flow = HomeFlow();
    addTearDown(flow.dispose);
    final births = <double>{};
    var previousVisible = 0;
    for (var i = 0; i < 3600; i++) {
      flow.advance(const Duration(microseconds: 33333));
      expect(
        [0, 1].where((n) => flow.highlightStrength(n) > 0).length,
        lessThanOrEqualTo(1),
      );
      expect(flow.particles.length, lessThanOrEqualTo(12));
      for (final particle in flow.particles) {
        births.add(particle.born);
        expect(particle.life, inInclusiveRange(8, 12));
        expect(particle.rise, inInclusiveRange(40, 60));
        expect(particle.drift.abs(), lessThanOrEqualTo(8));
        expect(particle.diameter, inInclusiveRange(1, 2));
        expect(particle.opacity(flow.seconds), inInclusiveRange(0, .3));
      }
      if (flow.visibleParticle != null) previousVisible++;
    }
    expect(previousVisible, greaterThan(100));
    final ordered = births.toList()..sort();
    for (var i = 1; i < ordered.length; i++) {
      expect(ordered[i] - ordered[i - 1], inInclusiveRange(4, 6));
    }
    flow.setReducedMotion(true);
    final paused = flow.seconds;
    flow.advance(const Duration(seconds: 30));
    expect(flow.seconds, paused);
    expect(flow.visibleParticle, isNull);
    expect(flow.arrival(0), 1);
  });

  test(
    'meteors use 1/3/5/8 per batch, emotion colours and 8/12 second gaps',
    () {
      final flow = HomeFlow(seed: 42);
      addTearDown(flow.dispose);
      final batches = <double, int>{};
      final colors = <Color>{};
      for (var i = 0; i < 12000; i++) {
        flow.advance(const Duration(milliseconds: 100));
        expect(flow.meteors.length, lessThanOrEqualTo(8));
        for (final meteor in flow.meteors) {
          batches.putIfAbsent(meteor.born, () => flow.meteors.length);
          colors.add(meteor.color);
          expect(emotionSpectrum, contains(meteor.color));
          expect(meteor.endsAt, greaterThan(flow.seconds));
          expect(meteor.endsAt - meteor.born, lessThan(1.3));
        }
      }
      expect(batches.values.toSet(), {1, 3, 5, 8});
      expect(colors, emotionSpectrum.toSet());
      final times = [0.0, ...batches.keys];
      final intervals = <double>{};
      for (var i = 1; i < times.length; i++) {
        intervals.add(times[i] - times[i - 1]);
      }
      expect(intervals, {8.0, 12.0});
    },
  );

  test('meteors fade, travel, expire and never replay missed batches', () {
    final flow = HomeFlow(seed: 7);
    addTearDown(flow.dispose);
    while (flow.meteors.isEmpty) {
      flow.advance(const Duration(milliseconds: 100));
    }
    final meteor = flow.meteors.first;
    final start = meteor.born + meteor.delay;
    final middle = start + meteor.life / 2;
    expect(meteor.opacity(start - .1), 0);
    expect(meteor.opacity(start), 0);
    expect(meteor.opacity(middle), greaterThan(.5));
    expect(meteor.opacity(meteor.endsAt), 0);
    const size = Size(1280, 800);
    final a = meteor.position(size, start);
    final b = meteor.position(size, middle);
    expect(b.dx, lessThan(a.dx));
    expect(b.dy, greaterThan(a.dy));
    flow.setReducedMotion(true);
    expect(flow.meteors, isEmpty);
    final paused = flow.seconds;
    flow.advance(const Duration(seconds: 60));
    expect(flow.seconds, paused);
    expect(flow.meteors, isEmpty);
    flow.setReducedMotion(false);
    flow.advance(const Duration(milliseconds: 100));
    expect(flow.meteors, isEmpty);
    // All batch starts are multiples of four; at 1003s every old streak is dead.
    flow.advance(
      Duration(microseconds: ((1003 - flow.seconds) * 1000000).round()),
    );
    expect(flow.meteors, isEmpty);
    while (flow.meteors.isEmpty) {
      flow.advance(const Duration(milliseconds: 100));
    }
    expect(flow.meteors.map((m) => m.born).toSet().length, 1);
    flow.advance(const Duration(seconds: 2));
    expect(flow.meteors, isEmpty);
  });

  test('meteor trails paint even when the dust pool is empty', () async {
    final flow = HomeFlow(seed: 1);
    addTearDown(flow.dispose);
    flow.advance(const Duration(milliseconds: 500));
    flow.meteors.add(
      const FlowMeteor(
        born: 0,
        delay: .1,
        life: .8,
        origin: Offset(.8, .1),
        angle: 2.6,
        distance: 320,
        tail: 100,
        color: love,
      ),
    );
    expect(flow.particles, isEmpty);
    final recorder = ui.PictureRecorder();
    FlowAtmospherePainter(flow).paint(Canvas(recorder), const Size(320, 200));
    final picture = recorder.endRecording();
    final image = await picture.toImage(320, 200);
    final data = await image.toByteData();
    var visible = 0;
    for (var i = 3; i < data!.lengthInBytes; i += 4) {
      if (data.getUint8(i) > 0) visible++;
    }
    expect(visible, inInclusiveRange(50, 300));
    image.dispose();
    picture.dispose();
  });

  test(
    'entry traces use real marker mtimes, without inventing first visits',
    () async {
      final temp = await Directory.systemTemp.createTemp('memory_flow_');
      addTearDown(() => temp.delete(recursive: true));
      final store = ProjectStore(temp);
      expect(await store.lastVisit(HomeEntrance.library), isNull);
      expect(entryTrace(null), '尚未进入');
      await store.recordVisit(HomeEntrance.library);
      final time = DateTime(2026, 10, 22, 12);
      final file = File(p.join(temp.path, 'entry-visits', 'library.json'));
      await file.setLastModified(time);
      final reopened = ProjectStore(temp);
      expect(await reopened.lastVisit(HomeEntrance.library), time);
      expect(await reopened.lastVisit(HomeEntrance.creation), isNull);
      expect(
        entryTrace(
          await reopened.lastVisit(HomeEntrance.library),
          now: DateTime(2026, 10, 25, 12),
        ),
        '上次进入 · 3 天前',
      );
      expect(await Directory(p.join(temp.path, 'projects')).exists(), isFalse);
    },
  );

  test('wrapped border paths paint before and after the seam', () async {
    final flow = HomeFlow();
    addTearDown(flow.dispose);
    advance(flow, 2);
    flow.setHovered(0, true);
    advance(flow, .4);
    for (final phase in [.999, .001]) {
      flow.phases[0] = phase;
      final recorder = ui.PictureRecorder();
      FlowBorderPainter(flow, 0).paint(Canvas(recorder), const Size(560, 96));
      final picture = recorder.endRecording();
      final image = await picture.toImage(560, 96);
      final data = await image.toByteData();
      var visible = 0;
      for (var i = 3; i < data!.lengthInBytes; i += 4) {
        if (data.getUint8(i) > 0) visible++;
      }
      expect(visible, greaterThan(100));
      expect(visible, lessThan(560 * 96 * .05));
      image.dispose();
      picture.dispose();
    }
  });

  testWidgets(
    'live flow pauses on another route, resumes, and respects reduced motion',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pumpWidget(const PlasticMemoryApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1600));
      final state = tester.state<MemoryHomeViewState>(
        find.byType(MemoryHomeView),
      );
      expect(state.motionRunning, isTrue);
      expect(find.text('尚未进入'), findsNWidgets(2));
      state.didChangeAppLifecycleState(AppLifecycleState.inactive);
      expect(state.motionRunning, isTrue);
      state.didChangeAppLifecycleState(AppLifecycleState.hidden);
      expect(state.motionRunning, isFalse);
      state.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(state.motionRunning, isTrue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.tap(find.text('纷乱回忆'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(state.motionRunning, isFalse);
      final paused = state.flow.seconds;
      await tester.pump(const Duration(seconds: 5));
      expect(state.flow.seconds, paused);
      await tester.pageBack();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1600));
      expect(state.motionRunning, isTrue);
      expect(find.text('上次进入 · 刚刚'), findsOneWidget);
      expect(find.text('尚未进入'), findsOneWidget);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: true);
      await tester.pumpAndSettle();
      expect(state.motionRunning, isFalse);
      for (final label in ['纷乱回忆', '创造回忆', '设置', '退出']) {
        expect(find.text(label).hitTestable(), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
