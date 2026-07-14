import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Lightweight app logger — writes timestamped lines to console (debug) and a
/// rotating log file under the app support directory.
class AppLog {
  AppLog._();

  static File? _file;
  static bool _initialized = false;
  static final Queue<String> _pending = Queue<String>();
  static bool _draining = false;

  /// Path to the active log file, or null before [initialize].
  static String? get logFilePath => _file?.path;

  static Future<void> initialize() async {
    if (_initialized) return;

    final supportDir = await getApplicationSupportDirectory();
    final logDir = Directory(p.join(supportDir.path, 'logs'));
    if (!await logDir.exists()) {
      await logDir.create(recursive: true);
    }

    _file = File(p.join(logDir.path, 'maathai.log'));
    _initialized = true;

    // Start each session with a separator so multi-run logs stay readable.
    await _write('INFO', 'AppLog', '─── session start ───');
    await _write('INFO', 'AppLog', 'Log file: ${_file!.path}');
  }

  static void info(String tag, String message) {
    unawaited(_write('INFO', tag, message));
  }

  static void warn(String tag, String message) {
    unawaited(_write('WARN', tag, message));
  }

  static void error(
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    final detail = error != null ? '$message | $error' : message;
    unawaited(_write('ERROR', tag, detail));
    if (stackTrace != null && kDebugMode) {
      debugPrintStack(stackTrace: stackTrace, label: tag);
    }
  }

  /// Log elapsed time for a timed operation.
  static void timed(String tag, String operation, DateTime started) {
    final ms = DateTime.now().difference(started).inMilliseconds;
    info(tag, '$operation (${ms}ms)');
  }

  static Future<void> _write(String level, String tag, String message) async {
    final line =
        '${DateTime.now().toIso8601String()} [$level] $tag: $message';
    if (kDebugMode) {
      debugPrint(line);
    }
    if (!_initialized || _file == null) return;
    _pending.add(line);
    unawaited(_drainQueue());
  }

  static Future<void> _drainQueue() async {
    if (_draining || _file == null) return;
    _draining = true;
    try {
      while (_pending.isNotEmpty) {
        final batch = _pending.join('\n');
        _pending.clear();
        await _file!.writeAsString('$batch\n', mode: FileMode.append, flush: true);
      }
    } catch (_) {
      // Avoid recursive failures if disk is full or path is locked.
    } finally {
      _draining = false;
      if (_pending.isNotEmpty) {
        unawaited(_drainQueue());
      }
    }
  }
}
