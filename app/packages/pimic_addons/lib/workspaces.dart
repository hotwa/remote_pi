import 'dart:convert';

class WorkspaceKey {
  const WorkspaceKey(this.peer, this.room);
  final String peer, room;
  String get id => jsonEncode([peer, room]);
  @override
  bool operator ==(Object other) =>
      other is WorkspaceKey && other.peer == peer && other.room == room;
  @override
  int get hashCode => Object.hash(peer, room);
}

class WorkspaceTarget {
  const WorkspaceTarget({
    required this.key,
    required this.device,
    required this.title,
    required this.path,
    this.online = false,
    this.working = false,
  });
  final WorkspaceKey key;
  final String device, title, path;
  final bool online, working;
}

class WorkspaceDraft {
  const WorkspaceDraft({
    this.text = '',
    this.scroll = 0,
    this.tooLarge = false,
  });
  final String text;
  final double scroll;
  final bool tooLarge;
}

/// RAM only, scoped to this app run. No identity, disk or network access.
class WorkspaceMemory {
  static const maxTargets = 32;
  static const maxDraftCharacters = 64000;
  static const maxTotalCharacters = 512000;
  final _drafts = <WorkspaceKey, WorkspaceDraft>{};
  final _favorites = <WorkspaceKey>{};
  int get count => _drafts.length;
  int get characters => _drafts.values.fold(0, (n, d) => n + d.text.length);
  Set<WorkspaceKey> get favorites => Set.unmodifiable(_favorites);
  bool isFavorite(WorkspaceKey key) => _favorites.contains(key);
  WorkspaceDraft read(WorkspaceKey key) {
    final draft = _drafts.remove(key);
    if (draft == null) return const WorkspaceDraft();
    _drafts[key] = draft;
    return draft;
  }

  bool saveText(WorkspaceKey key, String text) {
    final previous = _drafts.remove(key) ?? const WorkspaceDraft();
    final tooLarge = text.length > maxDraftCharacters;
    _drafts[key] = WorkspaceDraft(
      text: tooLarge ? '' : text,
      scroll: previous.scroll,
      tooLarge: tooLarge,
    );
    _trim();
    return !tooLarge;
  }

  void saveScroll(WorkspaceKey key, double offset) {
    if (!offset.isFinite || offset < 0) return;
    final previous = _drafts.remove(key) ?? const WorkspaceDraft();
    _drafts[key] = WorkspaceDraft(
      text: previous.text,
      scroll: offset,
      tooLarge: previous.tooLarge,
    );
    _trim();
  }

  void toggleFavorite(WorkspaceKey key) {
    if (_favorites.remove(key)) return;
    _favorites.add(key);
    while (_favorites.length > 128) {
      _favorites.remove(_favorites.first);
    }
  }

  void _trim() {
    while (_drafts.length > maxTargets || characters > maxTotalCharacters) {
      _drafts.remove(_drafts.keys.first);
    }
  }

  void clear() {
    _drafts.clear();
    _favorites.clear();
  }
}
