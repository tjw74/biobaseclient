import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

class Move {
  final String id;
  final String demoName;
  String name;
  final double startPosition;
  final double endPosition;
  final int? startTick;
  final int? endTick;
  final DateTime createdAt;

  Move({
    required this.id,
    required this.demoName,
    required this.name,
    required this.startPosition,
    required this.endPosition,
    this.startTick,
    this.endTick,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'demoName': demoName,
        'name': name,
        'startPosition': startPosition,
        'endPosition': endPosition,
        if (startTick != null) 'startTick': startTick,
        if (endTick != null) 'endTick': endTick,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Move.fromJson(Map<String, dynamic> j) => Move(
        id: j['id'] as String,
        demoName: j['demoName'] as String,
        name: j['name'] as String,
        startPosition: (j['startPosition'] as num).toDouble(),
        endPosition: (j['endPosition'] as num).toDouble(),
        startTick: j['startTick'] as int?,
        endTick: j['endTick'] as int?,
        createdAt: DateTime.parse(j['createdAt'] as String),
      );
}

class MovesService {
  List<Move>? _cache;

  File get _file {
    final appData = Platform.environment['APPDATA'] ??
        Platform.environment['HOME'] ??
        '';
    return File(p.join(appData, 'BioBase', 'moves.json'));
  }

  List<Move> _load() {
    if (_cache != null) return _cache!;
    final f = _file;
    if (!f.existsSync()) return _cache = [];
    try {
      final list = jsonDecode(f.readAsStringSync()) as List;
      return _cache = list.map((e) => Move.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return _cache = [];
    }
  }

  void _save() {
    final f = _file;
    final dir = f.parent;
    if (!dir.existsSync()) dir.createSync(recursive: true);
    f.writeAsStringSync(jsonEncode(_load().map((m) => m.toJson()).toList()));
  }

  List<Move> movesForDemo(String demoName) {
    return _load().where((m) => m.demoName == demoName).toList()
      ..sort((a, b) => a.startPosition.compareTo(b.startPosition));
  }

  Move addMove({
    required String demoName,
    required double startPosition,
    required double endPosition,
    int? startTick,
    int? endTick,
  }) {
    final existing = movesForDemo(demoName);
    final move = Move(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      demoName: demoName,
      name: 'Move ${existing.length + 1}',
      startPosition: startPosition,
      endPosition: endPosition,
      startTick: startTick,
      endTick: endTick,
      createdAt: DateTime.now(),
    );
    _load().add(move);
    _save();
    return move;
  }

  void renameMove(String id, String newName) {
    final moves = _load();
    final idx = moves.indexWhere((m) => m.id == id);
    if (idx >= 0) {
      moves[idx].name = newName;
      _save();
    }
  }

  void deleteMove(String id) {
    _load().removeWhere((m) => m.id == id);
    _save();
  }
}
