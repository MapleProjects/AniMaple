import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Envoltorio para navegación por D-Pad / control remoto en Android TV.
class TvFocusable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final FocusNode? focusNode;
  final bool autofocus;
  final double scaleOnFocus;
  final BorderRadius? borderRadius;
  final Color? focusBorderColor;
  final Color? glowColor;
  final bool enableGlow;
  final bool autoScroll;
  final EdgeInsetsGeometry padding;
  final FocusOnKeyEventCallback? onKeyEvent;

  const TvFocusable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.focusNode,
    this.autofocus = false,
    this.scaleOnFocus = 1.0,
    this.borderRadius,
    this.focusBorderColor,
    this.glowColor,
    this.enableGlow = false,
    this.autoScroll = true,
    this.padding = EdgeInsets.zero,
    this.onKeyEvent,
  });

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  late FocusNode _focusNode;
  bool _isFocused = false;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(TvFocusable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusNode != oldWidget.focusNode) {
      if (oldWidget.focusNode == null) {
        _focusNode.removeListener(_handleFocusChange);
        _focusNode.dispose();
      }
      _focusNode = widget.focusNode ?? FocusNode();
      _focusNode.addListener(_handleFocusChange);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void _handleFocusChange() {
    if (_isFocused != _focusNode.hasFocus) {
      setState(() {
        _isFocused = _focusNode.hasFocus;
      });
      if (_isFocused && widget.autoScroll && mounted) {
        Scrollable.ensureVisible(
          context,
          alignment: 0.5,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (widget.onKeyEvent != null) {
      final res = widget.onKeyEvent!(node, event);
      if (res != KeyEventResult.ignored) return res;
    }

    final isActivationKey = event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter ||
        event.logicalKey == LogicalKeyboardKey.space ||
        event.logicalKey == LogicalKeyboardKey.gameButtonA;

    if (isActivationKey) {
      if (event is KeyDownEvent) {
        setState(() => _isPressed = true);
        return KeyEventResult.handled;
      } else if (event is KeyUpEvent) {
        setState(() => _isPressed = false);
        widget.onTap?.call();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final effectiveRadius = widget.borderRadius ?? BorderRadius.circular(8);
    final borderColor = widget.focusBorderColor ?? const Color(0xFFa78bfa);
    final glow = widget.glowColor ?? const Color(0xFF8b5cf6);

    final scale = _isPressed
        ? 0.98
        : (_isFocused ? widget.scaleOnFocus : 1.0);

    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: _onKey,
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: widget.padding,
            decoration: BoxDecoration(
              borderRadius: effectiveRadius,
              border: Border.all(
                color: _isFocused ? borderColor : Colors.transparent,
                width: _isFocused ? 2.5 : 0.0,
              ),
              boxShadow: (_isFocused && widget.enableGlow)
                  ? [
                      BoxShadow(
                        color: glow.withValues(alpha: 0.55),
                        blurRadius: 18,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
