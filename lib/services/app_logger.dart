import 'package:flutter/foundation.dart';

class AppLogEntry {
  final DateTime timestamp;
  final String tag;
  final String mensagem;

  AppLogEntry(this.tag, this.mensagem) : timestamp = DateTime.now();

  @override
  String toString() {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    return '[$h:$m:$s] [$tag] $mensagem';
  }
}

class AppLogger {
  static const int _maxLogs = 40;
  static final List<AppLogEntry> _logs = [];

  static List<AppLogEntry> get logs => List.unmodifiable(_logs);

  static void erro(String tag, Object error, [StackTrace? st]) {
    final msg = error.toString();
    _logs.insert(0, AppLogEntry(tag, msg));
    if (_logs.length > _maxLogs) {
      _logs.removeLast();
    }
    if (kDebugMode) {
      debugPrint('[CineMax][$tag] $msg');
    }
  }

  static void info(String tag, String msg) {
    _logs.insert(0, AppLogEntry(tag, msg));
    if (_logs.length > _maxLogs) {
      _logs.removeLast();
    }
    if (kDebugMode) {
      debugPrint('[CineMax][$tag] $msg');
    }
  }

  static void limpar() => _logs.clear();
}
