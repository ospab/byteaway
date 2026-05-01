import 'package:flutter/material.dart';

import '../../core/services/log_service.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/app_scaffold.dart';

class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  bool _isLoading = true;
  String _content = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
    });
    final data = await LogService.readAll();
    if (!mounted) return;
    setState(() {
      _content = data;
      _isLoading = false;
    });
  }

  Future<void> _clear() async {
    await LogService.clear();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Логи',
      actions: [
        IconButton(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded),
        ),
        IconButton(
          onPressed: _clear,
          icon: const Icon(Icons.delete_outline_rounded),
        ),
      ],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _content.trim().isEmpty
              ? const Center(child: Text('Логи пустые'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(
                    _content,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
    );
  }
}
