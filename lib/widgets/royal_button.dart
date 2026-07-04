import 'package:flutter/material.dart';

import '../services/haptic_service.dart';
import '../theme_constants.dart';

enum RoyalButtonVariant { primary, emphasized, secondary, tertiary }

/// The app's shared text button.
///
/// One choke point for button look & feel: colors come from the design
/// tokens, and every press gets a subtle scale-down plus a selection
/// haptic for free.
///
/// The four variants encode the app's actual button hierarchy:
/// - [RoyalButtonVariant.primary]    → gold [FilledButton] (dialog main action)
/// - [RoyalButtonVariant.emphasized] → outlined with translucent gold fill —
///   the hero action on the win/loss overlays
/// - [RoyalButtonVariant.secondary]  → gold-border [OutlinedButton]
/// - [RoyalButtonVariant.tertiary]   → plain [TextButton] (dismiss/back)
///
/// [minHeight] and [padding] exist only so call sites can preserve their
/// exact legacy geometry during adoption — colors and shape are not
/// overridable here by design.
class RoyalButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final RoyalButtonVariant variant;

  /// Stretches the button to the available width.
  final bool expand;

  /// Dense paddings for tight dialog layouts.
  final bool compact;

  /// Set false when the surrounding flow already fires its own haptic.
  final bool enableHaptic;

  final double? minHeight;
  final EdgeInsetsGeometry? padding;

  const RoyalButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.variant = RoyalButtonVariant.primary,
    this.expand = false,
    this.compact = false,
    this.enableHaptic = true,
    this.minHeight,
    this.padding,
  });

  @override
  State<RoyalButton> createState() => _RoyalButtonState();
}

class _RoyalButtonState extends State<RoyalButton> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null;

  void _handlePressed() {
    if (widget.enableHaptic) HapticService.selection();
    widget.onPressed!.call();
  }

  /// Tier styling on top of the button themes in [ThemeData].
  ButtonStyle? _variantStyle() {
    return switch (widget.variant) {
      RoyalButtonVariant.primary => null, // filledButtonTheme covers it
      RoyalButtonVariant.emphasized => OutlinedButton.styleFrom(
          foregroundColor: kGold,
          backgroundColor: kGoldTintBg,
          side: const BorderSide(color: kGold, width: 1.5),
          textStyle: const TextStyle(
              fontWeight: FontWeight.bold, fontSize: 16),
        ),
      RoyalButtonVariant.secondary => OutlinedButton.styleFrom(
          foregroundColor: kGold,
          side: const BorderSide(color: kGold, width: 1.5),
          textStyle: const TextStyle(fontWeight: FontWeight.bold),
        ),
      RoyalButtonVariant.tertiary => TextButton.styleFrom(
          foregroundColor: kGoldLight,
          textStyle: const TextStyle(fontSize: 13),
          iconSize: 16,
          padding: const EdgeInsets.symmetric(
              horizontal: kSpaceMd, vertical: kSpaceSm),
        ),
    };
  }

  ButtonStyle? _effectiveStyle() {
    final ButtonStyle? base = _variantStyle();
    final double? height = widget.minHeight;
    final EdgeInsetsGeometry? pad = widget.padding ??
        (widget.compact
            ? const EdgeInsets.symmetric(
                horizontal: kSpaceMd, vertical: kSpaceSm)
            : null);
    if (height == null && pad == null && !widget.compact) return base;
    final geometry = ButtonStyle(
      minimumSize: height != null
          ? WidgetStatePropertyAll(Size(0, height))
          : null,
      padding: pad != null ? WidgetStatePropertyAll(pad) : null,
      visualDensity: widget.compact ? VisualDensity.compact : null,
    );
    return base == null ? geometry : geometry.merge(base);
  }

  Widget _buildButton() {
    final VoidCallback? onPressed = _enabled ? _handlePressed : null;
    final ButtonStyle? style = _effectiveStyle();
    final Text text = Text(widget.label);
    final Widget? icon = widget.icon != null ? Icon(widget.icon) : null;

    return switch (widget.variant) {
      RoyalButtonVariant.primary => icon != null
          ? FilledButton.icon(
              onPressed: onPressed, style: style, icon: icon, label: text)
          : FilledButton(onPressed: onPressed, style: style, child: text),
      RoyalButtonVariant.emphasized ||
      RoyalButtonVariant.secondary =>
        icon != null
            ? OutlinedButton.icon(
                onPressed: onPressed, style: style, icon: icon, label: text)
            : OutlinedButton(onPressed: onPressed, style: style, child: text),
      RoyalButtonVariant.tertiary => icon != null
          ? TextButton.icon(
              onPressed: onPressed, style: style, icon: icon, label: text)
          : TextButton(onPressed: onPressed, style: style, child: text),
    };
  }

  @override
  Widget build(BuildContext context) {
    Widget button = _buildButton();
    if (widget.expand) {
      button = SizedBox(width: double.infinity, child: button);
    }
    // Listener (not GestureDetector) observes the press without competing
    // in the gesture arena, so the inner Material button keeps its tap.
    return Listener(
      onPointerDown: _enabled ? (_) => setState(() => _pressed = true) : null,
      onPointerUp: _enabled ? (_) => setState(() => _pressed = false) : null,
      onPointerCancel:
          _enabled ? (_) => setState(() => _pressed = false) : null,
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: kDurFast,
        curve: kCurveStandard,
        child: button,
      ),
    );
  }
}
