import 'package:flutter/material.dart';

class KeyboardHandler {
  /// Wraps a widget with keyboard-aware scrolling
  static Widget wrapWithKeyboardAwareScroll({
    required Widget child,
    EdgeInsetsGeometry? padding,
    ScrollController? controller,
  }) {
    return SingleChildScrollView(
      controller: controller,
      padding: padding,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: child,
    );
  }

  /// Creates a keyboard-aware container with proper spacing
  static Widget createKeyboardAwareContainer({
    required Widget child,
    EdgeInsetsGeometry? padding,
    double bottomSpacing = 100,
  }) {
    return SingleChildScrollView(
      padding: padding,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Column(
        children: [
          child,
          SizedBox(height: bottomSpacing),
        ],
      ),
    );
  }

  /// Handles keyboard visibility changes
  static void handleKeyboardVisibility({
    required BuildContext context,
    required VoidCallback onKeyboardShow,
    required VoidCallback onKeyboardHide,
  }) {
    // This can be used to detect keyboard visibility changes
    // and adjust UI accordingly
  }

  /// Ensures proper spacing when keyboard is visible
  static Widget ensureKeyboardSpacing({
    required Widget child,
    double minSpacing = 20,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
        return Container(
          padding: EdgeInsets.only(
            bottom: keyboardHeight > 0 ? keyboardHeight + minSpacing : minSpacing,
          ),
          child: child,
        );
      },
    );
  }
}

/// A widget that automatically adjusts its content when keyboard appears
class KeyboardAwareWidget extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double bottomSpacing;

  const KeyboardAwareWidget({
    super.key,
    required this.child,
    this.padding,
    this.bottomSpacing = 100,
  });

  @override
  State<KeyboardAwareWidget> createState() => _KeyboardAwareWidgetState();
}

class _KeyboardAwareWidgetState extends State<KeyboardAwareWidget> {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: widget.padding,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Column(
        children: [
          widget.child,
          SizedBox(height: widget.bottomSpacing),
        ],
      ),
    );
  }
}

/// A custom TextField that handles keyboard properly
class KeyboardAwareTextField extends StatelessWidget {
  final TextEditingController controller;
  final String? hintText;
  final String? helperText;
  final int? maxLines;
  final int? minLines;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final VoidCallback? onSubmitted;
  final Widget? prefixIcon;
  final List<Widget>? trailing;

  const KeyboardAwareTextField({
    super.key,
    required this.controller,
    this.hintText,
    this.helperText,
    this.maxLines = 1,
    this.minLines = 1,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.prefixIcon,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: hintText,
        helperText: helperText,
        helperMaxLines: 2,
        prefixIcon: prefixIcon,
        suffixIcon: trailing != null ? Row(
          mainAxisSize: MainAxisSize.min,
          children: trailing!,
        ) : null,
        border: const OutlineInputBorder(),
      ),
      maxLines: maxLines,
      minLines: minLines,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted != null ? (_) => onSubmitted!() : null,
    );
  }
}
