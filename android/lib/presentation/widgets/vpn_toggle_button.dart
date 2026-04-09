import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Static circular VPN toggle button with glow effect.
class VpnToggleButton extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final Color glowColor =
        isConnected ? AppTheme.success : AppTheme.primary;

    return GestureDetector(
      onTap: onPressed,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Static glow layer
          if (isConnected)
            Container(
              width: 145,
              height: 145,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: glowColor.withOpacity(0.25),
                    blurRadius: 40,
                    spreadRadius: 10,
                  ),
                ],
              ),
            ),
          
          // Main button body
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isConnected
                    ? [AppTheme.success, AppTheme.success.withOpacity(0.6)]
                    : [AppTheme.primary, AppTheme.accent.withOpacity(0.8)],
              ),
              boxShadow: [
                BoxShadow(
                  color: glowColor.withOpacity(0.35),
                  blurRadius: 25,
                  offset: const Offset(0, 8),
                ),
              ],
              border: Border.all(
                color: Colors.white.withOpacity(0.15),
                width: 2,
              ),
            ),
            child: Center(
              child: isLoading
                  ? const SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 3,
                      ),
                    )
                  : Icon(
                      isConnected
                          ? Icons.power_settings_new
                          : Icons.power_settings_new_outlined,
                      size: 64,
                      color: Colors.white,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
