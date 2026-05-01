import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Simple in-memory logger to capture application logs for in-app viewing.
class AppLogger {
  AppLogger._();

  static final _logs = <String>[];
  static const _maxLogs = 1000;
  static File? _logFile;

  static const _sensitivePatternSources = <String>[
    r'(authorization\s*:\s*bearer\s+)[A-Za-z0-9._\-+/=]+',
    r'(api[_-]?key\s*[:=]\s*)[A-Za-z0-9._\-+/=]+',
    r'(token\s*[:=]\s*)[A-Za-z0-9._\-+/=]+',
  ];

  static final _controller = StreamController<List<String>>.broadcast();

  static Stream<List<String>> get logStream => _controller.stream;
  static List<String> get currentLogs => List.unmodifiable(_logs);

  static Future<void> init() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      _logFile = File('${directory.path}/byteaway_logs.txt');
      if (await _logFile!.exists()) {
        final existingLogs = await _logFile!.readAsString();
        _logs.addAll(existingLogs.split('\n').where((l) => l.isNotEmpty));
        if (_logs.length > _maxLogs) {
          _logs.removeRange(0, _logs.length - _maxLogs);
        }
      }
    } catch (e) {
      // Ignore init errors
    }
  }

  static void log(String message) {
    final timestamp =
        DateTime.now().toString().split('.').first.split(' ').last;
    final sanitized = _sanitize(message);
    final formatted = '[$timestamp] $sanitized';

    _logs.add(formatted);
    if (_logs.length > _maxLogs) {
      _logs.removeAt(0);
    }

    _controller.add(List.from(_logs));

    // Persist to file
    _persistLogs();
  }

  static Future<void> _persistLogs() async {
    if (_logFile == null) return;
    try {
      await _logFile!.writeAsString(_logs.join('\n'));
    } catch (e) {
      // Ignore write errors
    }
  }

  static void clear() {
    _logs.clear();
    _controller.add([]);
    _persistLogs();
  }

  static String _sanitize(String message) {
    try {
      var result = message;
      for (final source in _sensitivePatternSources) {
        final pattern = RegExp(source, caseSensitive: false);
        result = result.replaceAllMapped(pattern, (match) {
          return '${match.group(1)}***';
        });
      }
      return result;
    } on FormatException {
      // Never break app flow because of log sanitization.
      return message;
    }
  }
}
