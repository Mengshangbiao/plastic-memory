import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'home_flow.dart';

import 'ui.dart';

class MemoryHomeView extends StatefulWidget {
  const MemoryHomeView({
    super.key,
    required this.loading,
    required this.error,
    required this.projectCount,
    required this.nodeCount,
    required this.lastModified,
    required this.onLibrary,
    required this.onCreate,
    required this.onSettings,
    required this.onExit,
    required this.onRetry,
    this.libraryVisited,
    this.creationVisited,
    this.motionEnabled = true,
  });
  final bool loading;
  final String? error;
  final int projectCount, nodeCount;
  final DateTime? lastModified, libraryVisited, creationVisited;
  final bool motionEnabled;
  final VoidCallback onLibrary, onCreate, onSettings, onExit, onRetry;

  @override
  State<MemoryHomeView> createState() => MemoryHomeViewState();
}

class MemoryHomeViewState extends State<MemoryHomeView>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final flow = HomeFlow();
  late final Ticker _ticker;
  Duration _lastSample = Duration.zero;
  bool _resumed = true;
  bool get motionRunning => _ticker.isActive;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker((elapsed) {
      final delta = elapsed - _lastSample;
      if (delta.inMicroseconds < 33333) return;
      _lastSample = elapsed;
      flow.advance(delta);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant MemoryHomeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMotion();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A visible desktop window can be inactive while the user works elsewhere.
    // Only hidden/suspended windows stop the home timeline.
    _resumed =
        state != AppLifecycleState.hidden &&
        state != AppLifecycleState.paused &&
        state != AppLifecycleState.detached;
    _syncMotion();
  }

  void _syncMotion() {
    flow.setReducedMotion(
      MediaQuery.disableAnimationsOf(context) || !widget.motionEnabled,
    );
    final run =
        !flow.reducedMotion &&
        _resumed &&
        !widget.loading &&
        widget.error == null &&
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    if (run && !_ticker.isActive) {
      _lastSample = Duration.zero;
      flow.enter();
      _ticker.start();
    } else if (!run && _ticker.isActive) {
      _ticker.stop();
      flow.clearInteraction();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    flow.dispose();
    super.dispose();
  }

  String get _lastModified {
    final date = widget.lastModified?.toLocal();
    if (date == null) return '尚无记录';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${date.year}.${two(date.month)}.${two(date.day)} ${two(date.hour)}:${two(date.minute)}';
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Color>(
    valueListenable: flow.background,
    builder: (_, color, child) => ColoredBox(color: color, child: child),
    child: Scaffold(
      backgroundColor: Colors.transparent,
      body: MemoryAtmosphere(
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(painter: FlowAtmospherePainter(flow)),
                ),
              ),
            ),
            LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 96, 24, 64),
                      child: SizedBox(
                        width: 560,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const ExcludeSemantics(
                              child: SizedBox(
                                width: 56,
                                height: 56,
                                child: CustomPaint(painter: _MemoryMark()),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              'MEMORY STUDIO',
                              style: monoStyle.copyWith(
                                fontSize: 10,
                                letterSpacing: 3.2,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              '可塑性记忆',
                              style: TextStyle(
                                fontSize: 48,
                                fontWeight: FontWeight.w300,
                                letterSpacing: .96,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              '让每一段回忆，都拥有重新塑形的机会',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: secondaryInk,
                                letterSpacing: .5,
                              ),
                            ),
                            const SizedBox(height: 48),
                            if (widget.loading)
                              const SizedBox(
                                height: 208,
                                child: Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                  ),
                                ),
                              )
                            else if (widget.error != null)
                              SizedBox(
                                height: 208,
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        widget.error!,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: secondaryInk,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      OutlinedButton(
                                        onPressed: widget.onRetry,
                                        child: const Text('重试'),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            else ...[
                              _MemoryEntry(
                                index: '01',
                                slot: 0,
                                flow: flow,
                                trace: entryTrace(widget.libraryVisited),
                                label: '纷乱回忆',
                                hint: '走进故事，拾起散落的光。',
                                emotion: calm,
                                icon: Icons.auto_stories_outlined,
                                onTap: widget.onLibrary,
                              ),
                              const SizedBox(height: 16),
                              _MemoryEntry(
                                index: '02',
                                slot: 1,
                                flow: flow,
                                trace: entryTrace(widget.creationVisited),
                                label: '创造回忆',
                                hint: '从一个开幕，写下新的可能。',
                                emotion: thought,
                                icon: Icons.edit_note_outlined,
                                onTap: widget.onCreate,
                              ),
                            ],
                            const SizedBox(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                TextButton(
                                  onPressed: widget.onSettings,
                                  child: Text(
                                    '设置',
                                    style: monoStyle.copyWith(fontSize: 12),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                const SizedBox(
                                  height: 12,
                                  child: VerticalDivider(
                                    width: 1,
                                    color: hairline,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                TextButton(
                                  onPressed: widget.onExit,
                                  child: Text(
                                    '退出',
                                    style: monoStyle.copyWith(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ],
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
      bottomNavigationBar: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: const BoxDecoration(
          color: Colors.transparent,
          border: Border(top: BorderSide(color: hairline)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            children: [
              Text(
                'MEMORY STUDIO / 0.2',
                style: monoStyle.copyWith(fontSize: 10),
              ),
              const Spacer(),
              if (widget.loading || widget.error != null)
                Text(widget.loading ? '正在读取记忆…' : '项目读取失败', style: monoStyle)
              else ...[
                Text(
                  '${widget.projectCount} 个项目  /  ${widget.nodeCount} 个节点',
                  style: monoStyle,
                ),
                if (constraints.maxWidth >= 880) ...[
                  const SizedBox(width: 32),
                  Text(
                    '最近修改  $_lastModified',
                    style: monoStyle.copyWith(fontSize: 10),
                  ),
                ],
              ],
              if (constraints.maxWidth >= 720) ...[
                const SizedBox(width: 32),
                for (final color in emotionSpectrum)
                  Container(
                    width: 3,
                    height: 3,
                    margin: const EdgeInsets.only(left: 5),
                    color: color.withValues(alpha: .55),
                  ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class _MemoryEntry extends StatelessWidget {
  const _MemoryEntry({
    required this.index,
    required this.slot,
    required this.flow,
    required this.label,
    required this.hint,
    required this.trace,
    required this.emotion,
    required this.icon,
    required this.onTap,
  });
  final String index, label, hint, trace;
  final int slot;
  final HomeFlow flow;
  final Color emotion;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: flow.entrance,
    builder: (context, child) {
      final value = flow.arrival(slot);
      return Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 8 * (1 - value)),
          child: child,
        ),
      );
    },
    child: RepaintBoundary(
      child: SizedBox(
        height: 96,
        child: CustomPaint(
          foregroundPainter: FlowBorderPainter(flow, slot),
          child: RepaintBoundary(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: surface,
                borderRadius: memoryRadius,
                border: Border.all(color: hairline),
              ),
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: onTap,
                  onHover: (value) => flow.setHovered(slot, value),
                  onFocusChange: (value) => flow.setFocused(slot, value),
                  borderRadius: memoryRadius,
                  hoverColor: Colors.transparent,
                  focusColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                        child: Row(
                          children: [
                            Icon(icon, size: 24, color: emotion),
                            const SizedBox(width: 24),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    label,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w300,
                                      letterSpacing: .4,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    hint,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: secondaryInk,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(index, style: monoStyle),
                            const SizedBox(width: 16),
                            const Icon(
                              Icons.arrow_forward,
                              size: 16,
                              color: secondaryInk,
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        right: 24,
                        bottom: 8,
                        child: Text(
                          trace,
                          style: TextStyle(
                            fontSize: 11,
                            color: ink.withValues(alpha: .35),
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
      ),
    ),
  );
}

class _MemoryMark extends CustomPainter {
  const _MemoryMark();
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final rect = Rect.fromCircle(center: center, radius: 12 + i * 7);
      paint.color = [calm, sorrow, love][i].withValues(alpha: .65 - i * .12);
      canvas.drawArc(rect, -.7 + i * .75, math.pi * 1.42, false, paint);
    }
    canvas.drawCircle(center, 2, Paint()..color = ink);
  }

  @override
  bool shouldRepaint(covariant _MemoryMark oldDelegate) => false;
}
