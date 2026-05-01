import 'dart:io';
import 'package:path_provider/path_provider.dart';

class LogService {
  static const _fileName = 'byteaway.log';

  static Future<File> _logFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<void> write(String message) async {
    final file = await _logFile();
    final ts = DateTime.now().toIso8601String();
    await file.writeAsString('[$ts] $message\n', mode: FileMode.append);
  }

  static Future<String> readAll() async {
    final file = await _logFile();
    if (!await file.exists()) return '';
    return file.readAsString();
  }

  static Future<void> clear() async {
    final file = await _logFile();
    if (await file.exists()) {
      await file.writeAsString('');
    }
  }
}
