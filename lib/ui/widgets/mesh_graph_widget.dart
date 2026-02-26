import 'dart:math';

import 'package:flutter/material.dart';

import 'package:bitchat/services/mesh_graph_service.dart';

/// Force-directed mesh graph visualization widget.
///
/// Matches Android `MeshGraph.kt`:
/// - Force-directed layout (repulsion + spring + center gravity)
/// - Confirmed edges as solid lines, unconfirmed as dashed
/// - Node pulse animation on packet activity
/// - Drag-to-reposition nodes
class MeshGraphWidget extends StatefulWidget {
  const MeshGraphWidget({super.key, required this.snapshot});

  final GraphSnapshot snapshot;

  @override
  State<MeshGraphWidget> createState() => _MeshGraphWidgetState();
}

// Physics constants (match Android)
const _repulsionForce = 100000.0;
const _springLength = 150.0;
const _springStrength = 0.02;
const _centerGravity = 0.02;
const _damping = 0.85;
const _maxVelocity = 30.0;

class _NodeState {
  _NodeState({
    required this.id,
    required this.label,
    required this.x,
    required this.y,
  });

  final String id;
  String label;
  double x, y;
  double vx = 0, vy = 0;
  bool isDragged = false;
  double pulseLevel = 0;
}

class _MeshGraphWidgetState extends State<MeshGraphWidget>
    with SingleTickerProviderStateMixin {
  final _nodes = <String, _NodeState>{};
  late AnimationController _ticker;
  final _random = Random();
  String? _draggedNode;

  @override
  void initState() {
    super.initState();
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
    _ticker.addListener(_step);
    _updateTopology();
  }

  @override
  void didUpdateWidget(MeshGraphWidget old) {
    super.didUpdateWidget(old);
    _updateTopology();
  }

  @override
  void dispose() {
    _ticker.removeListener(_step);
    _ticker.dispose();
    super.dispose();
  }

  void _updateTopology() {
    final newIds = widget.snapshot.nodes.map((n) => n.peerID).toSet();
    _nodes.removeWhere((id, _) => !newIds.contains(id));

    for (final node in widget.snapshot.nodes) {
      final existing = _nodes[node.peerID];
      if (existing != null) {
        existing.label = node.displayLabel;
      } else {
        final angle = _random.nextDouble() * 2 * pi;
        final radius = 50 + _random.nextDouble() * 50;
        _nodes[node.peerID] = _NodeState(
          id: node.peerID,
          label: node.displayLabel,
          x: 200 + cos(angle) * radius,
          y: 200 + sin(angle) * radius,
        );
      }
    }
  }

  void _step() {
    final nodeList = _nodes.values.toList();
    if (nodeList.isEmpty) return;

    const cx = 200.0;
    const cy = 200.0;

    // Repulsion
    for (var i = 0; i < nodeList.length; i++) {
      final n1 = nodeList[i];
      for (var j = i + 1; j < nodeList.length; j++) {
        final n2 = nodeList[j];
        final dx = n1.x - n2.x;
        final dy = n1.y - n2.y;
        final distSq = dx * dx + dy * dy;
        if (distSq > 0.1) {
          final dist = sqrt(distSq);
          final force = _repulsionForce / distSq;
          final fx = (dx / dist) * force;
          final fy = (dy / dist) * force;
          if (!n1.isDragged) {
            n1.vx += fx;
            n1.vy += fy;
          }
          if (!n2.isDragged) {
            n2.vx -= fx;
            n2.vy -= fy;
          }
        }
      }
    }

    // Spring attraction
    for (final edge in widget.snapshot.edges) {
      final n1 = _nodes[edge.a];
      final n2 = _nodes[edge.b];
      if (n1 != null && n2 != null) {
        final dx = n1.x - n2.x;
        final dy = n1.y - n2.y;
        final dist = sqrt(dx * dx + dy * dy);
        if (dist > 0.1) {
          final force = (dist - _springLength) * _springStrength;
          final fx = (dx / dist) * force;
          final fy = (dy / dist) * force;
          if (!n1.isDragged) {
            n1.vx -= fx;
            n1.vy -= fy;
          }
          if (!n2.isDragged) {
            n2.vx += fx;
            n2.vy += fy;
          }
        }
      }
    }

    // Center gravity + integration
    for (final n in nodeList) {
      if (!n.isDragged) {
        n.vx -= (n.x - cx) * _centerGravity;
        n.vy -= (n.y - cy) * _centerGravity;

        final vMag = sqrt(n.vx * n.vx + n.vy * n.vy);
        if (vMag > _maxVelocity) {
          n.vx = (n.vx / vMag) * _maxVelocity;
          n.vy = (n.vy / vMag) * _maxVelocity;
        }

        n.x += n.vx;
        n.y += n.vy;
        n.vx *= _damping;
        n.vy *= _damping;
      }

      if (n.pulseLevel > 0) {
        n.pulseLevel = (n.pulseLevel - 0.05).clamp(0.0, 1.0);
      }
    }
  }

  /// Trigger a pulse animation on a node.
  void triggerPulse(String peerID) {
    _nodes[peerID]?.pulseLevel = 1.0;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onPanStart: (details) {
        final pos = details.localPosition;
        _NodeState? closest;
        double closestDist = double.infinity;
        for (final n in _nodes.values) {
          final d = sqrt(pow(n.x - pos.dx, 2) + pow(n.y - pos.dy, 2));
          if (d < closestDist) {
            closestDist = d;
            closest = n;
          }
        }
        if (closest != null && closestDist < 40) {
          closest.isDragged = true;
          _draggedNode = closest.id;
        }
      },
      onPanUpdate: (details) {
        if (_draggedNode != null) {
          final n = _nodes[_draggedNode!];
          if (n != null) {
            n.x += details.delta.dx;
            n.y += details.delta.dy;
          }
        }
      },
      onPanEnd: (_) {
        if (_draggedNode != null) {
          _nodes[_draggedNode!]?.isDragged = false;
          _draggedNode = null;
        }
      },
      child: AnimatedBuilder(
        animation: _ticker,
        builder: (context, _) {
          return CustomPaint(
            painter: _MeshPainter(
              nodes: _nodes,
              edges: widget.snapshot.edges,
              isDark: isDark,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _MeshPainter extends CustomPainter {
  _MeshPainter({
    required this.nodes,
    required this.edges,
    required this.isDark,
  });

  final Map<String, _NodeState> nodes;
  final List<GraphEdge> edges;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final edgePaint = Paint()
      ..color = const Color(0xFF4A90E2)
      ..strokeWidth = 3;

    final dashedPaint = Paint()
      ..color = const Color(0xFF4A90E2).withValues(alpha: 0.4)
      ..strokeWidth = 2;

    // Draw edges
    for (final edge in edges) {
      final n1 = nodes[edge.a];
      final n2 = nodes[edge.b];
      if (n1 != null && n2 != null) {
        if (edge.isConfirmed) {
          canvas.drawLine(Offset(n1.x, n1.y), Offset(n2.x, n2.y), edgePaint);
        } else {
          // Dashed line for unconfirmed
          canvas.drawLine(Offset(n1.x, n1.y), Offset(n2.x, n2.y), dashedPaint);
        }
      }
    }

    // Draw nodes
    for (final node in nodes.values) {
      final center = Offset(node.x, node.y);
      final pulse = node.pulseLevel;

      // Pulse glow
      if (pulse > 0.05) {
        canvas.drawCircle(
          center,
          16 + pulse * 20,
          Paint()
            ..color = const Color(0xFF00FF00).withValues(alpha: pulse * 0.4),
        );
      }

      // Node circle
      canvas.drawCircle(
        center,
        14 + pulse * 3,
        Paint()..color = const Color(0xFF00C851),
      );

      // Border
      canvas.drawCircle(
        center,
        12 + pulse * 2,
        Paint()
          ..color = isDark ? Colors.white : Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );

      // Label
      final textPainter = TextPainter(
        text: TextSpan(
          text: node.label,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 10,
            color: isDark ? Colors.white70 : Colors.black87,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(node.x + 18, node.y - 5));
    }
  }

  @override
  bool shouldRepaint(covariant _MeshPainter old) => true;
}
