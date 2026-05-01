import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Enhanced button with multiple styles and animations
class EnhancedButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  final Widget? icon;
  final ButtonType type;
  final ButtonSize size;
  final bool isLoading;
  final bool isFullWidth;
  final Color? customColor;
  final Color? textColor;
  final double? borderRadius;
  final EdgeInsetsGeometry? padding;

  const EnhancedButton({
    super.key,
    required this.text,
    this.onPressed,
    this.icon,
    this.type = ButtonType.primary,
    this.size = ButtonSize.medium,
    this.isLoading = false,
    this.isFullWidth = false,
    this.customColor,
    this.textColor,
    this.borderRadius,
    this.padding,
  });

  @override
  State<EnhancedButton> createState() => _EnhancedButtonState();
}

class _EnhancedButtonState extends State<EnhancedButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: AppTheme.fastAnimation,
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: AppTheme.defaultCurve,
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color get _buttonColor {
    if (widget.customColor != null) return widget.customColor!;

    switch (widget.type) {
      case ButtonType.primary:
        return AppTheme.primary;
      case ButtonType.secondary:
        return AppTheme.accent;
      case ButtonType.outline:
        return Colors.transparent;
      case ButtonType.text:
        return Colors.transparent;
      case ButtonType.success:
        return AppTheme.success;
      case ButtonType.danger:
        return AppTheme.error;
      case ButtonType.warning:
        return AppTheme.warning;
    }
  }

  Color get _textColor {
    if (widget.textColor != null) return widget.textColor!;

    switch (widget.type) {
      case ButtonType.primary:
      case ButtonType.secondary:
      case ButtonType.success:
      case ButtonType.danger:
      case ButtonType.warning:
        return Colors.white;
      case ButtonType.outline:
      case ButtonType.text:
        return _buttonColor;
    }
  }

  BorderSide get _borderSide {
    switch (widget.type) {
      case ButtonType.outline:
        return BorderSide(color: _buttonColor, width: 1.5);
      default:
        return BorderSide.none;
    }
  }

  EdgeInsetsGeometry get _defaultPadding {
    switch (widget.size) {
      case ButtonSize.small:
        return const EdgeInsets.symmetric(horizontal: 16, vertical: 8);
      case ButtonSize.medium:
        return const EdgeInsets.symmetric(horizontal: 24, vertical: 12);
      case ButtonSize.large:
        return const EdgeInsets.symmetric(horizontal: 32, vertical: 16);
    }
  }

  TextStyle get _textStyle {
    switch (widget.size) {
      case ButtonSize.small:
        return Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: _textColor,
                  fontWeight: FontWeight.w600,
                ) ??
            const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            );
      case ButtonSize.medium:
        return Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: _textColor,
                  fontWeight: FontWeight.w600,
                ) ??
            const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            );
      case ButtonSize.large:
        return Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: _textColor,
                  fontWeight: FontWeight.w600,
                ) ??
            const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _isPressed ? _scaleAnimation.value : 1.0,
          child: SizedBox(
            width: widget.isFullWidth ? double.infinity : null,
            child: _buildButton(),
          ),
        );
      },
    );
  }

  Widget _buildButton() {
    Widget buttonChild = _buildButtonContent();

    if (widget.type == ButtonType.text) {
      return TextButton(
        onPressed: widget.isLoading ? null : widget.onPressed,
        style: TextButton.styleFrom(
          padding: widget.padding ?? _defaultPadding,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: buttonChild,
      );
    }

    return AnimatedContainer(
      duration: AppTheme.fastAnimation,
      curve: AppTheme.defaultCurve,
      decoration: BoxDecoration(
        gradient: widget.type == ButtonType.outline
            ? null
            : LinearGradient(
                colors: [_buttonColor, _buttonColor.withOpacity(0.8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        borderRadius: BorderRadius.circular(widget.borderRadius ?? 12),
        border: Border.fromBorderSide(_borderSide),
        boxShadow:
            widget.type != ButtonType.outline && widget.type != ButtonType.text
                ? [
                    BoxShadow(
                      color: _buttonColor.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.isLoading ? null : _handleTap,
          borderRadius: BorderRadius.circular(widget.borderRadius ?? 12),
          child: Padding(
            padding: widget.padding ?? _defaultPadding,
            child: buttonChild,
          ),
        ),
      ),
    );
  }

  Widget _buildButtonContent() {
    if (widget.isLoading) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(_textColor),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Загрузка...',
            style: _textStyle,
          ),
        ],
      );
    }

    if (widget.icon != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          widget.icon!,
          const SizedBox(width: 8),
          Text(
            widget.text,
            style: _textStyle,
          ),
        ],
      );
    }

    return Text(
      widget.text,
      style: _textStyle,
    );
  }

  void _handleTap() {
    if (widget.onPressed != null) {
      _controller.forward().then((_) {
        _controller.reverse().then((_) {
          widget.onPressed!();
        });
      });
    }
  }
}

enum ButtonType {
  primary,
  secondary,
  outline,
  text,
  success,
  danger,
  warning,
}

enum ButtonSize {
  small,
  medium,
  large,
}
