import 'dart:math';

/// Mesh graph data model — tracks network topology from peer announcements.
///
/// Matches Android `MeshGraphService.kt`:
/// - Nodes are peers (peerID + optional nickname)
/// - Edges are connections (confirmed if both peers announce each other)
/// - Timestamps for announcement freshness
class MeshGraphService {
  MeshGraphService._();

  static final instance = MeshGraphService._();

  final _nicknames = <String, String?>{};
  final _announcements = <String, Set<String>>{};
  final _lastUpdate = <String, int>{};
  final _listeners = <void Function(GraphSnapshot)>[];

  /// Current graph snapshot.
  GraphSnapshot get snapshot => _computeSnapshot();

  /// Listen for graph updates.
  void addListener(void Function(GraphSnapshot) listener) {
    _listeners.add(listener);
  }

  void removeListener(void Function(GraphSnapshot) listener) {
    _listeners.remove(listener);
  }

  /// Update graph from a peer announcement.
  void updateFromAnnouncement(
    String originPeerID, {
    String? nickname,
    List<String>? neighbors,
    int timestamp = 0,
  }) {
    if (nickname != null) _nicknames[originPeerID] = nickname;

    final prev = _lastUpdate[originPeerID];
    if (prev != null && prev >= timestamp) return;
    _lastUpdate[originPeerID] = timestamp;

    final filtered = (neighbors ?? [])
        .where((n) => n != originPeerID)
        .take(10)
        .toSet();
    _announcements[originPeerID] = filtered;

    _notifyListeners();
  }

  /// Update a peer's nickname.
  void updateNickname(String peerID, String? nickname) {
    if (nickname == null) return;
    _nicknames[peerID] = nickname;
    _notifyListeners();
  }

  /// Remove a peer from the graph.
  void removePeer(String peerID) {
    _nicknames.remove(peerID);
    _announcements.remove(peerID);
    _lastUpdate.remove(peerID);
    _notifyListeners();
  }

  /// Reset for testing.
  void reset() {
    _nicknames.clear();
    _announcements.clear();
    _lastUpdate.clear();
    _notifyListeners();
  }

  GraphSnapshot _computeSnapshot() {
    // Collect all nodes
    final allNodeIds = <String>{};
    allNodeIds.addAll(_nicknames.keys);
    for (final entry in _announcements.entries) {
      allNodeIds.add(entry.key);
      allNodeIds.addAll(entry.value);
    }

    final nodes =
        allNodeIds
            .map((id) => GraphNode(peerID: id, nickname: _nicknames[id]))
            .toList()
          ..sort((a, b) => a.peerID.compareTo(b.peerID));

    // Compute edges
    final edges = <GraphEdge>[];
    final processed = <String>{};

    for (final entry in _announcements.entries) {
      final source = entry.key;
      for (final target in entry.value) {
        final pairKey = source.compareTo(target) <= 0
            ? '$source:$target'
            : '$target:$source';
        if (processed.add(pairKey)) {
          final a = source.compareTo(target) <= 0 ? source : target;
          final b = source.compareTo(target) <= 0 ? target : source;
          final aAnnouncesB = _announcements[a]?.contains(b) ?? false;
          final bAnnouncesA = _announcements[b]?.contains(a) ?? false;

          if (aAnnouncesB && bAnnouncesA) {
            edges.add(GraphEdge(a: a, b: b, isConfirmed: true));
          } else if (aAnnouncesB) {
            edges.add(
              GraphEdge(a: a, b: b, isConfirmed: false, confirmedBy: a),
            );
          } else if (bAnnouncesA) {
            edges.add(
              GraphEdge(a: a, b: b, isConfirmed: false, confirmedBy: b),
            );
          }
        }
      }
    }

    edges.sort((a, b) {
      final cmp = a.a.compareTo(b.a);
      return cmp != 0 ? cmp : a.b.compareTo(b.b);
    });

    return GraphSnapshot(nodes: nodes, edges: edges);
  }

  void _notifyListeners() {
    final snap = _computeSnapshot();
    for (final l in _listeners) {
      l(snap);
    }
  }
}

class GraphNode {
  const GraphNode({required this.peerID, this.nickname});
  final String peerID;
  final String? nickname;

  String get displayLabel =>
      nickname ?? peerID.substring(0, min(8, peerID.length));
}

class GraphEdge {
  const GraphEdge({
    required this.a,
    required this.b,
    required this.isConfirmed,
    this.confirmedBy,
  });
  final String a;
  final String b;
  final bool isConfirmed;
  final String? confirmedBy;
}

class GraphSnapshot {
  const GraphSnapshot({required this.nodes, required this.edges});
  final List<GraphNode> nodes;
  final List<GraphEdge> edges;
}
