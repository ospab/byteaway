import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

class AppScaffold extends StatelessWidget {
  final String title;
  final List<Widget> actions;
  final Widget body;

  const AppScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(gradient: AppTheme.ambientGradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(title),
          actions: actions,
        ),
        body: body,
      ),
    );
  }
}
