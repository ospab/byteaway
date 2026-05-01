import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Enhanced glass card with multiple variants and animations
class EnhancedGlassCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final VoidCallback? onTap;
  final bool isInteractive;
  final GlassCardVariant variant;
  final AnimationType animationType;

  const EnhancedGlassCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.onTap,
    this.isInteractive = false,
    this.variant = GlassCardVariant.standard,
    this.animationType = AnimationType.none,
  });

  @override
  State<EnhancedGlassCard> createState() => _EnhancedGlassCardState();
}

class _EnhancedGlassCardState extends State<EnhancedGlassCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: AppTheme.mediumAnimation,
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.05,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: AppTheme.defaultCurve,
    ));

    _opacityAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: AppTheme.smoothCurve,
    ));

    if (widget.animationType != AnimationType.none) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  BoxDecoration _getDecoration() {
    switch (widget.variant) {
      case GlassCardVariant.premium:
        return AppTheme.premiumCardDecoration;
      case GlassCardVariant.success:
        return AppTheme.successCardDecoration;
      case GlassCardVariant.error:
        return AppTheme.errorCardDecoration;
      case GlassCardVariant.elevated:
        return AppTheme.elevatedCardDecoration;
      case GlassCardVariant.standard:
        return AppTheme.glassCardDecoration;
    }
  }

  @override
  Widget build(BuildContext context) {
    final decoration = _getDecoration();

    Widget card = AnimatedContainer(
      duration: AppTheme.fastAnimation,
      curve: AppTheme.defaultCurve,
      width: widget.width,
      height: widget.height,
      margin: widget.margin,
      padding: widget.padding ?? const EdgeInsets.all(16),
      decoration: decoration,
      child: widget.child,
    );

    if (widget.isInteractive && widget.onTap != null) {
      card = GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              double scale = 1.0;
              if (_isHovered) scale = 1.02;
              if (_isPressed) scale = 0.98;

              return Transform.scale(
                scale: scale,
                child: AnimatedOpacity(
                  duration: AppTheme.fastAnimation,
                  opacity: _isHovered ? 0.9 : 1.0,
                  child: card,
                ),
              );
            },
          ),
        ),
      );
    }

    return AnimatedBuilder(
      animation: widget.animationType != AnimationType.none
          ? _controller
          : const AlwaysStoppedAnimation(0),
      builder: (context, child) {
        if (widget.animationType == AnimationType.fadeIn) {
          return FadeTransition(
            opacity: _opacityAnimation,
            child: Transform.scale(
              scale: _scaleAnimation.value,
              child: card,
            ),
          );
        } else if (widget.animationType == AnimationType.scale) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: card,
          );
        }
        return card;
      },
    );
  }
}

enum GlassCardVariant {
  standard,
  premium,
  success,
  error,
  elevated,
}

enum AnimationType {
  none,
  fadeIn,
  scale,
  slide,
}
