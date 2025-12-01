import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/vlvt_colors.dart';
import '../theme/vlvt_text_styles.dart';
import '../theme/vlvt_decorations.dart';

/// A styled text input for the VLVT design system.
///
/// Features glassmorphism effect with gold accents.
class VlvtInput extends StatefulWidget {
  /// The text controller.
  final TextEditingController? controller;

  /// Hint text displayed when empty.
  final String? hintText;

  /// Label text displayed above the input.
  final String? labelText;

  /// Prefix icon.
  final IconData? prefixIcon;

  /// Suffix icon.
  final IconData? suffixIcon;

  /// Suffix icon callback.
  final VoidCallback? onSuffixTap;

  /// Whether the text is obscured (for passwords).
  final bool obscureText;

  /// Keyboard type.
  final TextInputType? keyboardType;

  /// Text input action.
  final TextInputAction? textInputAction;

  /// Validation function.
  final String? Function(String?)? validator;

  /// Called when the value changes.
  final ValueChanged<String>? onChanged;

  /// Called when submitted.
  final ValueChanged<String>? onSubmitted;

  /// Whether to use glassmorphism blur effect.
  final bool blur;

  /// Whether the input is enabled.
  final bool enabled;

  /// Auto-correct behavior.
  final bool autocorrect;

  /// Maximum number of lines.
  final int? maxLines;

  /// Focus node.
  final FocusNode? focusNode;

  /// Input formatters (e.g., digits only).
  final List<TextInputFormatter>? inputFormatters;

  /// Maximum character length.
  final int? maxLength;

  /// Text capitalization.
  final TextCapitalization textCapitalization;

  const VlvtInput({
    super.key,
    this.controller,
    this.hintText,
    this.labelText,
    this.prefixIcon,
    this.suffixIcon,
    this.onSuffixTap,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.blur = true,
    this.enabled = true,
    this.autocorrect = true,
    this.maxLines = 1,
    this.focusNode,
    this.inputFormatters,
    this.maxLength,
    this.textCapitalization = TextCapitalization.none,
  });

  @override
  State<VlvtInput> createState() => _VlvtInputState();
}

class _VlvtInputState extends State<VlvtInput> {
  late FocusNode _focusNode;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    if (widget.focusNode == null) {
      _focusNode.dispose();
    } else {
      _focusNode.removeListener(_onFocusChange);
    }
    super.dispose();
  }

  void _onFocusChange() {
    setState(() {
      _isFocused = _focusNode.hasFocus;
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget inputField = TextFormField(
      controller: widget.controller,
      focusNode: _focusNode,
      obscureText: widget.obscureText,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      autocorrect: widget.autocorrect,
      enabled: widget.enabled,
      maxLines: widget.maxLines,
      maxLength: widget.maxLength,
      inputFormatters: widget.inputFormatters,
      textCapitalization: widget.textCapitalization,
      style: VlvtTextStyles.input,
      validator: widget.validator,
      onChanged: widget.onChanged,
      onFieldSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        hintText: widget.hintText,
        labelText: widget.labelText,
        hintStyle: VlvtTextStyles.inputHint,
        labelStyle: VlvtTextStyles.inputHint,
        prefixIcon: widget.prefixIcon != null
            ? Icon(widget.prefixIcon, color: VlvtColors.gold)
            : null,
        suffixIcon: widget.suffixIcon != null
            ? GestureDetector(
                onTap: widget.onSuffixTap,
                child: Icon(widget.suffixIcon, color: VlvtColors.gold),
              )
            : null,
        filled: true,
        fillColor: VlvtColors.glassBackgroundStrong,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: VlvtDecorations.borderRadiusMd,
          borderSide: BorderSide(
            color: VlvtColors.borderStrong,
            width: 1,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: VlvtDecorations.borderRadiusMd,
          borderSide: BorderSide(
            color: VlvtColors.borderStrong,
            width: 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: VlvtDecorations.borderRadiusMd,
          borderSide: const BorderSide(
            color: VlvtColors.gold,
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: VlvtDecorations.borderRadiusMd,
          borderSide: const BorderSide(
            color: VlvtColors.crimson,
            width: 1,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: VlvtDecorations.borderRadiusMd,
          borderSide: const BorderSide(
            color: VlvtColors.crimson,
            width: 2,
          ),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: VlvtDecorations.borderRadiusMd,
          borderSide: BorderSide(
            color: VlvtColors.borderSubtle,
            width: 1,
          ),
        ),
        errorStyle: VlvtTextStyles.error,
      ),
    );

    // Apply blur effect if enabled
    if (widget.blur) {
      inputField = ClipRRect(
        borderRadius: VlvtDecorations.borderRadiusMd,
        child: BackdropFilter(
          filter: VlvtDecorations.glassBlur,
          child: inputField,
        ),
      );
    }

    // Add gold glow when focused
    if (_isFocused) {
      inputField = Container(
        decoration: BoxDecoration(
          borderRadius: VlvtDecorations.borderRadiusMd,
          boxShadow: [VlvtDecorations.goldGlowSoft],
        ),
        child: inputField,
      );
    }

    return inputField;
  }
}

/// An underline-style input for simpler forms.
class VlvtUnderlineInput extends StatelessWidget {
  final TextEditingController? controller;
  final String? hintText;
  final IconData? prefixIcon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;

  const VlvtUnderlineInput({
    super.key,
    this.controller,
    this.hintText,
    this.prefixIcon,
    this.obscureText = false,
    this.keyboardType,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      onChanged: onChanged,
      style: VlvtTextStyles.input,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: VlvtTextStyles.inputHint,
        prefixIcon: prefixIcon != null
            ? Icon(prefixIcon, color: VlvtColors.gold)
            : null,
        filled: false,
        border: UnderlineInputBorder(
          borderSide: BorderSide(
            color: VlvtColors.gold.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(
            color: VlvtColors.gold.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(
            color: VlvtColors.gold,
            width: 2,
          ),
        ),
      ),
    );
  }
}
