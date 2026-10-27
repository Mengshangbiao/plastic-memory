import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'models.dart';
import 'ui.dart';

class GraphCanvas extends StatefulWidget {
  const GraphCanvas({
    super.key,
    required this.project,
    required this.selectedId,
    required this.onSelect,
    required this.onChanged,
    required this.onOpen,
    required this.onContext,
  });
  final ProjectModel project;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final VoidCallback onChanged;
  final ValueChanged<StoryNode> onOpen;
  final void Function(StoryNode, Offset) onContext;
  static const nodeSize = Size(210, 112);
  @override
  State<GraphCanvas> createState() => GraphCanvasState();
}

class GraphCanvasState extends State<GraphCanvas> {
  final transform = TransformationController();
  final viewportKey = GlobalKey();
  Size viewportSize = Size.zero;
  String? hovered, connecting;
  Offset? pointer;
  Offset? dragStartScene, dragNodeOrigin;
  bool initialized = false;
  @override
  void dispose() {
    transform.dispose();
    super.dispose();
  }

  Offset _scene(Offset global) => transform.toScene(
    (viewportKey.currentContext!.findRenderObject() as RenderBox).globalToLocal(
      global,
    ),
  );
  Offset get center => transform.toScene(viewportSize.center(Offset.zero));
  void centerOn(StoryNode node) {
    transform.value = Matrix4.identity()
      ..translateByDouble(
        viewportSize.width / 2 - node.position.dx - 105,
        viewportSize.height / 2 - node.position.dy - 56,
        0,
        1,
      );
  }

  void fit() {
    if (widget.project.nodes.isEmpty) return;
    final positions = widget.project.nodes.map((n) => n.position);
    final left = positions.map((p) => p.dx).reduce(math.min) - 80,
        top = positions.map((p) => p.dy).reduce(math.min) - 80,
        right = positions.map((p) => p.dx).reduce(math.max) + 290,
        bottom = positions.map((p) => p.dy).reduce(math.max) + 192;
    final scale = math
        .min(
          (viewportSize.width - 550) / (right - left),
          (viewportSize.height - 100) / (bottom - top),
        )
        .clamp(.25, 1.2);
    transform.value = Matrix4.identity()
      ..translateByDouble(
        240 +
            (viewportSize.width - 550 - (right - left) * scale) / 2 -
            left * scale,
        (viewportSize.height - (bottom - top) * scale) / 2 - top * scale,
        0,
        1,
      )
      ..scaleByDouble(scale, scale, 1, 1);
  }

  StoryNode add(StoryNodeType type, [Offset? position]) {
    var placement = position ?? center - const Offset(105, 56);
    if (position == null) {
      for (var attempt = 0; attempt < 20; attempt++) {
        final bounds = Rect.fromLTWH(
          placement.dx,
          placement.dy,
          210,
          112,
        ).inflate(10);
        if (!widget.project.nodes.any(
          (n) => bounds.overlaps(
            Rect.fromLTWH(n.position.dx, n.position.dy, 210, 112),
          ),
        ))
          break;
        placement += const Offset(230, 32);
        if (placement.dx > 3300)
          placement = Offset(center.dx - 105, placement.dy + 160);
      }
    }
    final node = widget.project.addNode(type, _clamp(placement));
    widget.onSelect(node.id);
    widget.onChanged();
    return node;
  }

  Offset _clamp(Offset p) => Offset(p.dx.clamp(10, 3580), p.dy.clamp(10, 2280));
  void _connect(String from, String to) {
    final error = widget.project.connect(from, to);
    if (error != null)
      notify(context, error);
    else
      widget.onChanged();
    setState(() {
      connecting = null;
      pointer = null;
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      viewportSize = constraints.biggest;
      if (!initialized) {
        initialized = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted)
            centerOn(widget.project.nodeById(widget.project.startNodeId)!);
        });
      }
      return MouseRegion(
        onHover: (event) {
          if (connecting != null)
            setState(() => pointer = _scene(event.position));
        },
        child: DragTarget<StoryNodeType>(
          onAcceptWithDetails: (d) => add(d.data, _scene(d.offset)),
          builder: (context, candidates, rejected) => Container(
            key: viewportKey,
            color: paper,
            child: InteractiveViewer(
              transformationController: transform,
              constrained: false,
              boundaryMargin: const EdgeInsets.all(2400),
              minScale: .25,
              maxScale: 2,
              child: SizedBox(
                width: 3800,
                height: 2500,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: GraphPainter(
                          widget.project,
                          connecting,
                          pointer,
                          widget.selectedId,
                        ),
                      ),
                    ),
                    ...widget.project.nodes.map(_node),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
  Widget _node(StoryNode node) {
    final selected = widget.selectedId == node.id;
    return Positioned(
      left: node.position.dx,
      top: node.position.dy,
      width: GraphCanvas.nodeSize.width,
      height: GraphCanvas.nodeSize.height,
      child: MouseRegion(
        onEnter: (_) => setState(() => hovered = node.id),
        onExit: (_) => setState(() => hovered = null),
        child: GestureDetector(
          key: ValueKey('node-${node.id}'),
          onTap: () => widget.onSelect(node.id),
          onDoubleTap: () => widget.onOpen(node),
          onSecondaryTapUp: (d) => widget.onContext(node, d.globalPosition),
          onPanDown: (d) {
            dragStartScene = _scene(d.globalPosition);
            dragNodeOrigin = node.position;
          },
          onPanUpdate: (d) {
            if (dragStartScene == null || dragNodeOrigin == null) return;
            node.position = _clamp(
              dragNodeOrigin! + _scene(d.globalPosition) - dragStartScene!,
            );
            widget.onChanged();
          },
          child: Stack(
            children: [
              Positioned.fill(
                left: 10,
                top: 10,
                right: 10,
                bottom: 10,
                child: AnimatedContainer(
                  duration: memoryMotion,
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? raisedSurface : surface,
                    borderRadius: memoryRadius,
                    border: Border.all(
                      color: selected
                          ? node.type.color
                          : node.type.color.withValues(
                              alpha: hovered == node.id ? .7 : .35,
                            ),
                      width: 1,
                    ),
                    boxShadow: [
                      if (selected)
                        BoxShadow(
                          color: node.type.color.withValues(alpha: .12),
                          blurRadius: 6,
                        ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            node.type.icon,
                            size: 17,
                            color: node.type.color,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            node.type == StoryNodeType.choice
                                ? '选项 #${node.choiceNumber}'
                                : node.type.label,
                            style: TextStyle(
                              color: node.type.color,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Text(
                        node.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        node.type == StoryNodeType.choice
                            ? '${node.requiredChoices.length} 个出现条件'
                            : '${node.dialogue.length} 段对白 · ${node.outgoing.length} 条连线',
                        style: const TextStyle(
                          fontSize: 10,
                          color: secondaryInk,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (hovered == node.id || selected || connecting != null)
                ...[
                  const Offset(0, 46),
                  const Offset(190, 46),
                  const Offset(95, 0),
                  const Offset(95, 92),
                ].map(
                  (point) => Positioned(
                    left: point.dx,
                    top: point.dy,
                    width: 20,
                    height: 20,
                    child: DragTarget<String>(
                      onWillAcceptWithDetails: (d) =>
                          d.data != node.id &&
                          (node.type != StoryNodeType.start ||
                              widget.project.nodeById(d.data)?.type ==
                                  StoryNodeType.event),
                      onAcceptWithDetails: (d) => _connect(d.data, node.id),
                      builder: (context, candidates, rejected) {
                        final handle = Tooltip(
                          message: '拖动连线；也可依次点击两个连接点',
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: candidates.isEmpty
                                  ? raisedSurface
                                  : node.type.color,
                              border: Border.all(
                                color: node.type.color,
                                width: 2,
                              ),
                            ),
                          ),
                        );
                        return GestureDetector(
                          onTap: () {
                            if (connecting != null) {
                              _connect(connecting!, node.id);
                            } else if (node.type != StoryNodeType.ending)
                              setState(() => connecting = node.id);
                          },
                          child: node.type == StoryNodeType.ending
                              ? handle
                              : Draggable<String>(
                                  data: node.id,
                                  onDragStarted: () =>
                                      setState(() => connecting = node.id),
                                  onDragUpdate: (d) => setState(
                                    () => pointer = _scene(d.globalPosition),
                                  ),
                                  onDragEnd: (_) => setState(() {
                                    connecting = null;
                                    pointer = null;
                                  }),
                                  feedback: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: handle,
                                  ),
                                  child: handle,
                                ),
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class GraphPainter extends CustomPainter {
  GraphPainter(this.project, this.connecting, this.pointer, this.selectedId);
  final ProjectModel project;
  final String? connecting;
  final Offset? pointer;
  final String? selectedId;
  @override
  void paint(Canvas canvas, Size size) {
    final dot = Paint()..color = hairline;
    for (double x = 0; x < size.width; x += 24) {
      for (double y = 0; y < size.height; y += 24) {
        canvas.drawCircle(Offset(x, y), 1, dot);
      }
    }
    Offset port(StoryNode node, Offset target) {
      final center = node.position + const Offset(105, 56),
          delta = target - center;
      if (delta.dx.abs() > delta.dy.abs())
        return center + Offset(delta.dx > 0 ? 95 : -95, 0);
      return center + Offset(0, delta.dy > 0 ? 46 : -46);
    }

    void draw(Offset start, Offset end, Color color, {bool active = false}) {
      final direction = end - start;
      final curve = Path()..moveTo(start.dx, start.dy);
      if (direction.dx.abs() > direction.dy.abs()) {
        final bend =
            math.max(50.0, direction.dx.abs() * .45) * direction.dx.sign;
        curve.cubicTo(
          start.dx + bend,
          start.dy,
          end.dx - bend,
          end.dy,
          end.dx,
          end.dy,
        );
      } else {
        final bend =
            math.max(50.0, direction.dy.abs() * .45) * direction.dy.sign;
        curve.cubicTo(
          start.dx,
          start.dy + bend,
          end.dx,
          end.dy - bend,
          end.dx,
          end.dy,
        );
      }
      if (active)
        canvas.drawPath(
          curve,
          Paint()
            ..color = color.withValues(alpha: .18)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
      canvas.drawPath(
        curve,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      final metric = curve.computeMetrics().first;
      final tangent = metric.getTangentForOffset(metric.length);
      final angle = tangent?.vector.direction ?? direction.direction;
      final left =
              end - Offset(math.cos(angle - .45), math.sin(angle - .45)) * 12,
          right =
              end - Offset(math.cos(angle + .45), math.sin(angle + .45)) * 12;
      canvas.drawPath(
        Path()
          ..moveTo(end.dx, end.dy)
          ..lineTo(left.dx, left.dy)
          ..lineTo(right.dx, right.dy)
          ..close(),
        Paint()..color = color,
      );
    }

    for (final node in project.nodes) {
      for (final id in node.outgoing) {
        final target = project.nodeById(id);
        if (target == null) continue;
        final active = node.id == selectedId || target.id == selectedId;
        draw(
          port(node, target.position + const Offset(105, 56)),
          port(target, node.position + const Offset(105, 56)),
          node.type.color.withValues(alpha: active ? .7 : .25),
          active: active,
        );
      }
    }
    final from = connecting == null ? null : project.nodeById(connecting!);
    if (from != null && pointer != null)
      draw(
        port(from, pointer!),
        pointer!,
        from.type.color.withValues(alpha: .7),
        active: true,
      );
  }

  @override
  bool shouldRepaint(covariant GraphPainter oldDelegate) => true;
}
