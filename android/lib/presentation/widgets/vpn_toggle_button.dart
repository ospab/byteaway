import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

/// Animated circular VPN toggle button with pulsing glow effect.
class VpnToggleButton extends StatefulWidget {
  final bool isConnected;
  final bool isLoading;
  final VoidCallback onPressed;

  const VpnToggleButton({
    super.key,
    required this.isConnected,
    this.isLoading = false,
    required this.onPressed,
  });

  @override
  State<VpnToggleButton> createState() => _VpnToggleButtonState();
}

class _VpnToggleButtonState extends State<VpnToggleButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    if (widget.isConnected) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(VpnToggleButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isConnected && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.isConnected && _pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color glowColor =
        widget.isConnected ? AppTheme.success : AppTheme.primary;

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return GestureDetector(
          onTap: widget.isLoading ? null : () {
            HapticFeedback.mediumImpact();
            widget.onPressed();
          },
          child: Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: glowColor.withOpacity(
                    widget.isConnected ? 0.3 * _pulseAnimation.value : 0.15,
                  ),
                  blurRadius: widget.isConnected ? 40 : 20,
                  spreadRadius: widget.isConnected ? 5 : 0,
                ),
              ],
            ),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: widget.isConnected
                      ? [AppTheme.success, AppTheme.success.withOpacity(0.7)]
                      : [AppTheme.primary, AppTheme.accent],
                ),
                border: Border.all(
                  color: Colors.white.withOpacity(0.1),
                  width: 2,
                ),
              ),
              child: widget.isLoading
                  ? const Center(
                      child: SizedBox(
                        width: 36,
                        height: 36,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 3,
                        ),
                      ),
                    )
                  : Icon(
                      widget.isConnected ? Icons.power_settings_new : Icons.power_settings_new_outlined,
                      size: 56,
                      color: Colors.white,
                    ),
            ),
          ),
        );
      },
    );
  }
}

/// Helper: AnimatedBuilder that takes a Listenable animation.
class AnimatedBuilder extends StatelessWidget {
  final Animation<double> animation;
  final Widget Function(BuildContext, Widget?) builder;

  const AnimatedBuilder({
    super.key,
    required this.animation,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder2(
      animation: animation,
      builder: builder,
    );
  }
}

class AnimatedBuilder2 extends AnimatedWidget {
  final Widget Function(BuildContext, Widget?) builder;

  const AnimatedBuilder2({
    super.key,
    required Animation<double> animation,
    required this.builder,
  }) : super(listenable: animation);

  @override
  Widget build(BuildContext context) {
    return builder(context, null);
  }
}
