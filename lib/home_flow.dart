import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'palette.dart';

/// One timeline for the borders, background, dust, meteors and entrance. The view owns
/// the sole ticker; painters listen directly without rebuilding text each frame.
class HomeFlow extends ChangeNotifier {
  HomeFlow({int? seed})
    : _random = math.Random(seed ?? 20261025),
      _meteorRandom = math.Random(seed) {
    _nextBirth = 4 + _random.nextDouble() * 2;
    _nextMeteor = _meteorInterval();
  }

  final math.Random _random;
  final math.Random _meteorRandom;
  final entrance = ValueNotifier<double>(0);
  final background = ValueNotifier<Color>(paper);
  final List<FlowParticle> particles = [];
  final List<FlowMeteor> meteors = [];
  final phases = <double>[0, .5];
  final _hovered = [false, false], _focused = [false, false];
  final _mix = [0.0, 0.0], _from = [0.0, 0.0];
  final _transitionStart = [0.0, 0.0];
  double seconds = 0, _entryStart = 0, _nextBirth = 0;
  double _nextMeteor = 0;
  int _lightOwner = 0;
  double _lightStrength = 0;
  bool reducedMotion = false;
  static const hoverCurve = Cubic(.4, 0, .2, 1);

  int get highlightedCard {
    for (var i = 0; i < 2; i++) {
      if (_hovered[i]) return i;
    }
    for (var i = 0; i < 2; i++) {
      if (_focused[i]) return i;
    }
    // Keep the departing tip visible for its complete 600ms colour recovery.
    for (var i = 0; i < 2; i++) {
      if (_mix[i] > .0001) return i;
    }
    return (seconds / 14).floor() % 2;
  }

  bool active(int index) => _hovered[index] || _focused[index];
  double hoverMix(int index) => _mix[index];
  // 12 seconds for recalling; creation takes the requested faster step (10s).
  double period(int index) => 28 + ((index == 0 ? 12 : 10) - 28) * _mix[index];
  Color tipColor(int index) {
    final resting = HSVColor.fromColor(index == 0 ? calm : thought)
        .withSaturation(.2)
        .toColor();
    return Color.lerp(resting, index == 0 ? sorrow : joy, _mix[index])!;
  }

  double reveal(int index) => reducedMotion
      ? 1
      : Curves.easeOut.transform(
          ((seconds - _entryStart - index * .08) / 1.2).clamp(0.0, 1.0),
        );
  double arrival(int index) => reducedMotion
      ? 1
      : Curves.easeOut.transform(
          ((seconds - _entryStart - index * .08) / .4).clamp(0.0, 1.0),
        );

  double highlightStrength(int index) {
    return reducedMotion || _lightOwner != index ? 0 : _lightStrength;
  }

  FlowParticle? get visibleParticle =>
      reducedMotion || particles.isEmpty ? null : particles.first;

  void setHovered(int index, bool value) => _interaction(index, value, false);
  void setFocused(int index, bool value) => _interaction(index, value, true);
  void _interaction(int index, bool value, bool focus) {
    final wasActive = active(index);
    (focus ? _focused : _hovered)[index] = value;
    if (active(index) != wasActive) {
      _from[index] = _mix[index];
      _transitionStart[index] = seconds;
    }
    notifyListeners();
  }

  void setReducedMotion(bool value) {
    if (reducedMotion == value) return;
    reducedMotion = value;
    if (value) {
      particles.clear();
      meteors.clear();
      background.value = paper;
    }
    entrance.value = value ? 1 : 0;
    notifyListeners();
  }

  void enter() {
    _entryStart = seconds;
    entrance.value = reducedMotion ? 1 : 0;
    notifyListeners();
  }

  void clearInteraction() {
    for (var i = 0; i < 2; i++) {
      setHovered(i, false);
      setFocused(i, false);
    }
  }

  void advance(Duration elapsed) {
    if (reducedMotion) return;
    final dt = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    if (dt <= 0) return;
    seconds += dt;
    for (var i = 0; i < 2; i++) {
      final oldSpeed = 1 / period(i);
      final target = active(i) ? 1.0 : 0.0;
      final duration = active(i) ? .3 : .6;
      final t = hoverCurve.transform(
        ((seconds - _transitionStart[i]) / duration).clamp(0.0, 1.0),
      );
      _mix[i] = _from[i] + (target - _from[i]) * t;
      // Integrating speed preserves position when a pointer enters or leaves.
      phases[i] = (phases[i] + dt * (oldSpeed + 1 / period(i)) / 2) % 1;
    }
    // A sequential fade keeps hand-offs soft without ever lighting both tips.
    final targetOwner = highlightedCard;
    if (targetOwner == _lightOwner) {
      _lightStrength = math.min(1, _lightStrength + dt / .3);
    } else {
      _lightStrength = math.max(0, _lightStrength - dt / .15);
      if (_lightStrength == 0) _lightOwner = targetOwner;
    }
    final entry = ((seconds - _entryStart) / 1.28).clamp(0.0, 1.0);
    if (entrance.value != entry) entrance.value = entry;
    final breath = (1 - math.cos(seconds * math.pi * 2 / 40)) / 2;
    // Quantize to physical 8-bit colour; avoid repainting a full-screen wash
    // thirty times a second when its rendered colour has not changed.
    background.value = Color.fromARGB(
      255,
      7 + (2 * breath).round(),
      8 + (2 * breath).round(),
      10 + (3 * breath).round(),
    );
    while (seconds >= _nextBirth) {
      final born = _nextBirth;
      _nextBirth += 4 + _random.nextDouble() * 2;
      final life = 8 + _random.nextDouble() * 4;
      final particle = FlowParticle(
        born: born,
        life: life,
        origin: Offset(_random.nextDouble(), .15 + _random.nextDouble() * .8),
        rise: 40 + _random.nextDouble() * 20,
        drift: _random.nextDouble() * 16 - 8,
        diameter: 1 + _random.nextDouble(),
        color: _random.nextDouble() < .15
            ? emotionSpectrum[_random.nextInt(emotionSpectrum.length)]
            : Colors.white,
      );
      if (seconds - born < life) particles.add(particle);
    }
    particles.removeWhere((p) => seconds - p.born >= p.life);
    if (particles.length > 12) particles.removeRange(0, particles.length - 12);
    while (seconds >= _nextMeteor) {
      final born = _nextMeteor;
      _nextMeteor += _meteorInterval();
      // A delayed frame must not replay bursts whose lives have already ended.
      if (seconds - born < 1.3) _emitMeteors(born);
    }
    meteors.removeWhere((meteor) => seconds >= meteor.endsAt);
    notifyListeners();
  }

  double _meteorInterval() => _meteorRandom.nextBool() ? 8 : 12;

  void _emitMeteors(double born) {
    final count = const [1, 3, 5, 8][_meteorRandom.nextInt(4)];
    final lanes = List.generate(count, (i) => i)..shuffle(_meteorRandom);
    for (var i = 0; i < count; i++) {
      meteors.add(
        FlowMeteor(
          born: born,
          delay: i * .035 + _meteorRandom.nextDouble() * .045,
          life: .65 + _meteorRandom.nextDouble() * .3,
          origin: Offset(
            .2 + .75 * (lanes[i] + _meteorRandom.nextDouble()) / count,
            .04 + _meteorRandom.nextDouble() * .38,
          ),
          angle: 2.45 + _meteorRandom.nextDouble() * .3,
          distance: 260 + _meteorRandom.nextDouble() * 180,
          tail: 80 + _meteorRandom.nextDouble() * 60,
          color: emotionSpectrum[_meteorRandom.nextInt(emotionSpectrum.length)],
        ),
      );
    }
  }

  @override
  void dispose() {
    entrance.dispose();
    background.dispose();
    super.dispose();
  }
}

class FlowParticle {
  const FlowParticle({
    required this.born,
    required this.life,
    required this.origin,
    required this.rise,
    required this.drift,
    required this.diameter,
    required this.color,
  });
  final double born, life, rise, drift, diameter;
  final Offset origin;
  final Color color;
  double progress(double time) => ((time - born) / life).clamp(0.0, 1.0);
  double opacity(double time) => .3 * (1 - progress(time));
  Offset position(Size size, double time) => Offset(
    origin.dx * size.width + drift * progress(time),
    origin.dy * size.height - rise * progress(time),
  );
}

class FlowMeteor {
  const FlowMeteor({
    required this.born,
    required this.delay,
    required this.life,
    required this.origin,
    required this.angle,
    required this.distance,
    required this.tail,
    required this.color,
  });

  final double born, delay, life, angle, distance, tail;
  final Offset origin;
  final Color color;
  double get endsAt => born + delay + life;
  Offset get direction => Offset(math.cos(angle), math.sin(angle));
  double progress(double time) =>
      ((time - born - delay) / life).clamp(0.0, 1.0);
  double scale(Size size) => (size.shortestSide / 800).clamp(.65, 1.2);

  double opacity(double time) {
    final t = progress(time);
    return .62 *
        math.min((t / .12).clamp(0.0, 1.0), ((1 - t) / .3).clamp(0.0, 1.0));
  }

  Offset position(Size size, double time) =>
      Offset(origin.dx * size.width, origin.dy * size.height) +
      direction * distance * scale(size) * progress(time);
}

class FlowAtmospherePainter extends CustomPainter {
  FlowAtmospherePainter(this.flow) : super(repaint: flow);
  final HomeFlow flow;
  final _paint = Paint();
  final _streakPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  @override
  void paint(Canvas canvas, Size size) {
    if (flow.reducedMotion) return;
    // Keep the pool's full lifetimes, but give only one particle the light budget.
    final particle = flow.visibleParticle;
    if (particle != null) {
      _paint.color = particle.color.withValues(
        alpha: particle.opacity(flow.seconds),
      );
      canvas.drawCircle(
        particle.position(size, flow.seconds),
        particle.diameter / 2,
        _paint,
      );
    }
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final meteor in flow.meteors) {
      final alpha = meteor.opacity(flow.seconds);
      if (alpha <= 0) continue;
      final head = meteor.position(size, flow.seconds);
      final tail = head - meteor.direction * meteor.tail * meteor.scale(size);
      _streakPaint
        ..strokeWidth = 1
        ..shader = ui.Gradient.linear(
          tail,
          head,
          [
            meteor.color.withValues(alpha: 0),
            meteor.color.withValues(alpha: alpha * .25),
            meteor.color.withValues(alpha: alpha),
          ],
          [0, .55, 1],
        );
      canvas.drawLine(tail, head, _streakPaint);
      _paint.color = Color.lerp(
        meteor.color,
        Colors.white,
        .3,
      )!.withValues(alpha: alpha);
      canvas.drawCircle(head, 1.1, _paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant FlowAtmospherePainter old) => old.flow != flow;
}

class FlowBorderPainter extends CustomPainter {
  FlowBorderPainter(this.flow, this.index) : super(repaint: flow);
  final HomeFlow flow;
  final int index;
  Size? _size;
  ui.PathMetric? _metric;
  final _paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;

  void _segment(Canvas canvas, double from, double to, Color color) {
    final metric = _metric!, length = metric.length;
    final revealLength = length * flow.reveal(index);
    final start = from % length, distance = to - from;
    _paint.color = color;
    void draw(double a, double b) {
      // Entrance grows clockwise from the path origin, independently of the
      // moving tip. Clamp both pieces at a wrapped seam.
      b = math.min(b, revealLength);
      if (b > a) canvas.drawPath(metric.extractPath(a, b), _paint);
    }

    draw(start, math.min(length, start + distance));
    if (start + distance > length) draw(0, start + distance - length);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (flow.reducedMotion) {
      if (flow.active(index)) {
        _paint.color = index == 0 ? sorrow : joy;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            (Offset.zero & size).deflate(.5),
            const Radius.circular(3.5),
          ),
          _paint,
        );
      }
      return;
    }
    if (flow.reveal(index) <= 0) return;
    if (_size != size) {
      _size = size;
      _metric =
          (Path()..addRRect(
                RRect.fromRectAndRadius(
                  (Offset.zero & size).deflate(.5),
                  const Radius.circular(3.5),
                ),
              ))
              .computeMetrics()
              .first;
    }
    final length = _metric!.length;
    final direction = index == 0 ? 1.0 : -1.0;
    final head =
        (index == 0 ? flow.phases[index] : 1 - flow.phases[index]) * length;
    final tail = length * .18;
    final strength = flow.highlightStrength(index);
    final tip = flow.tipColor(index);
    // Short path segments keep the tail continuous around corners and t=0;
    // only the final four pixels carry the coloured tip, with no blur layer.
    for (double distance = tail; distance > 0;) {
      final next = math.max(0.0, distance - (distance > 8 ? 8 : 1));
      final nearTip = (1 - next / 4).clamp(0.0, 1.0);
      final alpha = .08 + .57 * nearTip * strength;
      final color = Color.lerp(
        Colors.white,
        tip,
        nearTip * strength,
      )!.withValues(alpha: alpha);
      final a = head - direction * distance, b = head - direction * next;
      _segment(canvas, math.min(a, b), math.max(a, b), color);
      distance = next;
    }
    // Two percent of the path after the head drops to transparent; the visible
    // falloff is confined to four pixels rather than lighting an entire edge.
    for (var pixel = 0; pixel < 4; pixel++) {
      final a = head + direction * pixel, b = head + direction * (pixel + 1);
      _segment(
        canvas,
        math.min(a, b),
        math.max(a, b),
        tip.withValues(alpha: .65 * strength * (1 - pixel / 4)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant FlowBorderPainter old) =>
      old.flow != flow || old.index != index;
}

String entryTrace(DateTime? modified, {DateTime? now}) {
  if (modified == null) return '尚未进入';
  final age = (now ?? DateTime.now()).difference(modified);
  final relative = age.inDays > 0
      ? '${age.inDays} 天前'
      : age.inHours > 0
      ? '${age.inHours} 小时前'
      : age.inMinutes > 0
      ? '${age.inMinutes} 分钟前'
      : '刚刚';
  return '上次进入 · $relative';
}
