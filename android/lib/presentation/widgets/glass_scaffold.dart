import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A base scaffold with a static professional background (blobs and blur).
/// Used to unify the UI across all screens.
class GlassScaffold extends StatelessWidget {
  final Widget body;
  final String? title;
  final List<Widget>? actions;
  final Widget? bottomNavigationBar;

  const GlassScaffold({
    super.key,
    required this.body,
    this.title,
    this.actions,
    this.bottomNavigationBar,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: title != null || actions != null
          ? AppBar(
              title: title != null ? Text(title!) : null,
              actions: actions,
              backgroundColor: Colors.transparent,
              elevation: 0,
            )
          : null,
      body: Stack(
        children: [
          // ── Static Background Blobs ────────────────
          Container(color: AppTheme.background),
          Positioned(
            top: -50,
            right: -50,
            child: _buildBlob(250, AppTheme.primary.withOpacity(0.08)),
          ),
          Positioned(
            bottom: 150,
            left: -80,
            child: _buildBlob(300, AppTheme.accent.withOpacity(0.08)),
          ),

          // ── Content ───────────────────────────────
          body,
        ],
      ),
      bottomNavigationBar: bottomNavigationBar,
    );
  }

  Widget _buildBlob(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
        child: Container(color: Colors.transparent),
      ),
    );
  }
}
