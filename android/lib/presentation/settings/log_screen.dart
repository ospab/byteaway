import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/logger.dart';
import '../theme/app_theme.dart';

class LogScreen extends StatelessWidget {
  const LogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Application Logs'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy all logs',
            onPressed: () {
              final text = AppLogger.currentLogs.join('\n');
              Clipboard.setData(ClipboardData(text: text)).then((_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Logs copied to clipboard')),
                  );
                }
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Clear logs',
            onPressed: AppLogger.clear,
          ),
        ],
      ),
      body: StreamBuilder<List<String>>(
        stream: AppLogger.logStream,
        initialData: AppLogger.currentLogs,
        builder: (context, snapshot) {
          final logs = (snapshot.data ?? const <String>[]).join('\n');
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'APP LOGGER',
                style: TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 1.2),
              ),
              const SizedBox(height: 8),
              SelectableText(
                logs.isEmpty ? 'No app logs captured yet.' : logs,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
