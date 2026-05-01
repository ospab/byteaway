import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

/// Enhanced status card with animations and better UX
class EnhancedStatusCard extends StatefulWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final bool isActive;
  final bool isLoading;
  final String? error;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Color? activeColor;
  final Color? inactiveColor;
  final bool showGlow;

  const EnhancedStatusCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    this.isActive = false,
    this.isLoading = false,
    this.error,
    this.onTap,
    this.trailing,
    this.activeColor,
    this.inactiveColor,
    this.showGlow = false,
  });

  @override
  State<EnhancedStatusCard> createState() => _EnhancedStatusCardState();
}

class _EnhancedStatusCardState extends State<EnhancedStatusCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: AppTheme.slowAnimation,
      vsync: this,
    );

    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.05,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));

    if (widget.isActive || widget.isLoading) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(EnhancedStatusCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isActive || widget.isLoading) {
      if (!_controller.isAnimating) {
        _controller.repeat(reverse: true);
      }
    } else {
      if (_controller.isAnimating) {
        _controller.stop();
        _controller.reset();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color get _statusColor {
    if (widget.error != null) return AppTheme.error;
    if (widget.isActive) return widget.activeColor ?? AppTheme.success;
    return widget.inactiveColor ?? AppTheme.textSecondary;
  }

  BoxDecoration _getCardDecoration() {
    final baseDecoration = BoxDecoration(
      gradient: widget.isActive
          ? AppTheme.premiumGlassGradient
          : AppTheme.glassGradient,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: widget.isActive
            ? _statusColor.withOpacity(0.3)
            : Colors.white.withOpacity(0.08),
        width: 1.0,
      ),
    );

    if (widget.showGlow && widget.isActive) {
      return baseDecoration.copyWith(
        boxShadow: [
          AppTheme.glowShadow,
          AppTheme.cardShadow,
        ],
      );
    }

    return baseDecoration.copyWith(
      boxShadow: [AppTheme.glassShadow],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: widget.isLoading ? _pulseAnimation.value : 1.0,
          child: GestureDetector(
            onTap: widget.onTap,
            child: Container(
              decoration: _getCardDecoration(),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    _buildIcon(),
                    const SizedBox(width: 16),
                    Expanded(child: _buildContent()),
                    if (widget.trailing != null) ...[
                      const SizedBox(width: 16),
                      widget.trailing!,
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildIcon() {
    Color iconColor = _statusColor;
    if (widget.isLoading) {
      iconColor = AppTheme.primary;
    }

    return AnimatedContainer(
      duration: AppTheme.mediumAnimation,
      curve: AppTheme.defaultCurve,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: iconColor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: widget.isLoading
          ? SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(iconColor),
              ),
            )
          : Icon(
              widget.icon,
              color: iconColor,
              size: 24,
            ),
    );
  }

  Widget _buildContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
              ),
        ),
        if (widget.subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            widget.subtitle!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textSecondary,
                ),
          ),
        ],
        if (widget.error != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.error.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppTheme.error.withOpacity(0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 14,
                  color: AppTheme.error,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    widget.error!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.error,
                          fontSize: 11,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
