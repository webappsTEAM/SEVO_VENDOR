import 'package:flutter/material.dart';

import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_theme.dart';
import 'sevo_typography.dart';

/// Search box with a controlled radius, an animated focus ring and a clear
/// button. One `TextField`, fully theme-aware in light and dark.
class SevoSearchField extends StatefulWidget {
  const SevoSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  State<SevoSearchField> createState() => _SevoSearchFieldState();
}

class _SevoSearchFieldState extends State<SevoSearchField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_rebuild);
    widget.controller.addListener(_rebuild);
  }

  @override
  void dispose() {
    _focus.removeListener(_rebuild);
    widget.controller.removeListener(_rebuild);
    _focus.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focus.hasFocus;
    final hasText = widget.controller.text.isNotEmpty;
    return AnimatedContainer(
      duration: AppMotion.resolve(AppMotion.normal),
      curve: AppMotion.curve,
      height: 48,
      padding: const EdgeInsets.only(left: 14, right: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.input + 2),
        border: Border.all(
          color: focused ? AppColors.actionColor : AppColors.border,
          width: focused ? 1.6 : 1,
        ),
        boxShadow: focused
            ? [
                BoxShadow(
                  color: AppColors.actionColor.withValues(alpha: 0.16),
                  blurRadius: 10,
                ),
              ]
            : AppColors.cardShadow,
      ),
      child: Row(
        children: [
          Icon(
            Icons.search_rounded,
            size: 21,
            color: focused ? AppColors.actionColor : AppColors.textMuted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              onChanged: widget.onChanged,
              style: SevoText.body.copyWith(color: AppColors.headingText),
              cursorColor: AppColors.actionColor,
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: SevoText.body.copyWith(color: AppColors.textMuted),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          if (hasText)
            IconButton(
              icon: const Icon(Icons.clear_rounded, size: 18),
              color: AppColors.textMuted,
              tooltip: 'Clear search',
              onPressed: () {
                widget.controller.clear();
                widget.onChanged('');
              },
            ),
        ],
      ),
    );
  }
}
