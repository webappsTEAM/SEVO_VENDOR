import 'package:flutter/material.dart';

import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_theme.dart';
import 'sevo_animated_card.dart';
import 'sevo_count_up.dart';
import 'sevo_typography.dart';

/// Semantic colour families for badges and chips. All resolve through
/// [AppColors], so they are correct in light and dark themes.
enum SevoTone { success, warning, error, info, violet, brand, neutral }

class SevoToneColors {
  const SevoToneColors(this.bg, this.border, this.fg);

  final Color bg;
  final Color border;
  final Color fg;

  static SevoToneColors of(SevoTone tone) {
    final dark = AppColors.isDark;
    switch (tone) {
      case SevoTone.success:
        return SevoToneColors(
          AppColors.successBg,
          AppColors.successBorder,
          AppColors.successText,
        );
      case SevoTone.warning:
        return SevoToneColors(
          AppColors.warningBg,
          AppColors.warningBorder,
          AppColors.warningText,
        );
      case SevoTone.error:
        return SevoToneColors(
          AppColors.errorBg,
          AppColors.errorBorder,
          AppColors.errorText,
        );
      case SevoTone.info:
        return SevoToneColors(
          AppColors.infoBg,
          AppColors.infoBorder,
          AppColors.infoText,
        );
      case SevoTone.violet:
        return SevoToneColors(
          dark
              ? const Color(0xFF4C1D95).withValues(alpha: 0.35)
              : const Color(0xFFF5F3FF),
          dark ? const Color(0xFF6D28D9) : const Color(0xFFDDD6FE),
          dark ? const Color(0xFFC4B5FD) : const Color(0xFF6D28D9),
        );
      case SevoTone.brand:
        return SevoToneColors(
          AppColors.selectedTint,
          AppColors.selectedOnTint.withValues(alpha: 0.35),
          AppColors.selectedOnTint,
        );
      case SevoTone.neutral:
        return SevoToneColors(
          AppColors.surfaceMuted,
          AppColors.border,
          AppColors.textSecondary,
        );
    }
  }
}

/// A status / label pill. The label is one line and ellipsised, so it can
/// never overflow its row.
class SevoBadge extends StatelessWidget {
  const SevoBadge({
    super.key,
    required this.label,
    this.tone = SevoTone.neutral,
    this.icon,
    this.dot = false,
  });

  final String label;
  final SevoTone tone;
  final IconData? icon;

  /// A small filled dot before the label (status indicator).
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final c = SevoToneColors.of(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Icon(Icons.circle, size: 7, color: c.fg),
            const SizedBox(width: 5),
          ],
          if (icon != null) ...[
            Icon(icon, size: 13, color: c.fg),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SevoText.badge.copyWith(color: c.fg),
            ),
          ),
        ],
      ),
    );
  }
}

/// A filter chip with an optional count. The selected state animates between
/// outlined and filled.
class SevoFilterChip extends StatelessWidget {
  const SevoFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
    this.color,
    this.alert = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;

  /// Selected fill colour (defaults to the brand action colour).
  final Color? color;

  /// Shows the count in red when unselected (something needs attention).
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final active = color ?? AppColors.actionColor;
    final dur = AppMotion.resolve(AppMotion.normal);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Bounded (e.g. inside a Wrap): let the label ellipsise instead of overflowing.
        final bounded = constraints.maxWidth.isFinite;
        return Semantics(
          button: true,
          selected: selected,
          child: GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: dur,
              curve: AppMotion.curve,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? active : AppColors.surface,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: selected ? active : AppColors.border),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: active.withValues(alpha: 0.28),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  () {
                    final text = AnimatedDefaultTextStyle(
                      duration: dur,
                      style: SevoText.badge.copyWith(
                        fontSize: 12,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: selected ? Colors.white : AppColors.bodyText,
                      ),
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                    return bounded ? Flexible(child: text) : text;
                  }(),
                  if (count != null) ...[
                    const SizedBox(width: 7),
                    AnimatedContainer(
                      duration: dur,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? Colors.white.withValues(alpha: 0.22)
                            : (alert
                                  ? AppColors.errorBg
                                  : AppColors.surfaceMuted),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$count',
                        style: SevoText.badge.copyWith(
                          fontSize: 11,
                          color: selected
                              ? Colors.white
                              : (alert
                                    ? AppColors.errorText
                                    : AppColors.textSecondary),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A horizontally scrolling row of [SevoFilterChip]s with even spacing.
class SevoFilterRow extends StatelessWidget {
  const SevoFilterRow({super.key, required this.chips});

  final List<Widget> chips;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      // Room for the selected chip's glow.
      padding: const EdgeInsets.symmetric(vertical: 6),
      clipBehavior: Clip.none,
      child: Row(
        children: [
          for (var i = 0; i < chips.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            chips[i],
          ],
        ],
      ),
    );
  }
}

/// A themed dropdown in the same shape as [SevoSearchField].
class SevoDropdownField<T> extends StatelessWidget {
  const SevoDropdownField({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.icon,
    this.label,
  });

  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final IconData icon;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      key: ValueKey('${T.toString()}-$value-${items.length}'),
      initialValue: items.any((i) => i.value == value)
          ? value
          : items.first.value,
      items: items,
      onChanged: onChanged,
      isExpanded: true,
      icon: Icon(
        Icons.keyboard_arrow_down_rounded,
        color: AppColors.textSecondary,
      ),
      dropdownColor: AppColors.elevatedSurface,
      style: SevoText.body.copyWith(color: AppColors.headingText),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: SevoText.caption,
        prefixIcon: Icon(icon, size: 20, color: AppColors.textMuted),
        isDense: true,
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input + 2),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input + 2),
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input + 2),
          borderSide: BorderSide(color: AppColors.actionColor, width: 1.6),
        ),
      ),
    );
  }
}

/// A selectable statistic tile: tinted gradient, icon chip, counting figure,
/// label, caption and a faint icon watermark. [selected] draws an accent ring.
class SevoStatTile extends StatelessWidget {
  const SevoStatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    this.caption,
    this.selected = false,
    this.alert = false,
    this.alertLabel,
    this.onTap,
    this.index = 0,
  });

  final String label;
  final int value;
  final String? caption;
  final IconData icon;
  final Color accent;
  final bool selected;
  final bool alert;

  /// Small pill in the corner while [alert] is true (e.g. `AUDIT`).
  final String? alertLabel;
  final VoidCallback? onTap;
  final int index;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark;
    final chip = accent.withValues(alpha: dark ? 0.22 : 0.12);
    final on = dark ? Color.lerp(accent, Colors.white, 0.45)! : accent;
    return SevoAnimatedCard(
      index: index,
      onTap: onTap,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: dark
            ? [accent.withValues(alpha: 0.16), AppColors.surface]
            : [accent.withValues(alpha: 0.10), Colors.white],
      ),
      child: AnimatedContainer(
        duration: AppMotion.resolve(AppMotion.normal),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: selected ? accent : Colors.transparent,
            width: 1.6,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Stack(
            children: [
              Positioned(
                right: -14,
                top: -12,
                child: ExcludeSemantics(
                  child: Icon(
                    icon,
                    size: 70,
                    color: accent.withValues(alpha: dark ? 0.09 : 0.07),
                  ),
                ),
              ),
              if (alert && alertLabel != null)
                Positioned(
                  right: 10,
                  top: 10,
                  child: SevoBadge(label: alertLabel!, tone: SevoTone.error),
                ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: chip,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, size: 19, color: on),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SevoCountUp(
                            value: value,
                            style: SevoText.metric.copyWith(
                              color: alert ? AppColors.errorText : null,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: SevoText.overline.copyWith(
                              fontSize: 9.5,
                              letterSpacing: 0.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          if (caption != null)
                            Text(
                              caption!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: SevoText.meta.copyWith(
                                fontSize: 10.5,
                                height: 1.3,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lays [tiles] out two per row (one per row on very narrow screens).
class SevoTileGrid extends StatelessWidget {
  const SevoTileGrid({super.key, required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 300) {
          return Column(
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                tiles[i],
              ],
            ],
          );
        }
        final rows = <Widget>[];
        for (var i = 0; i < tiles.length; i += 2) {
          final a = tiles[i];
          final b = i + 1 < tiles.length
              ? tiles[i + 1]
              : const SizedBox.shrink();
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: a),
                  const SizedBox(width: 10),
                  Expanded(child: b),
                ],
              ),
            ),
          );
        }
        return Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              rows[i],
            ],
          ],
        );
      },
    );
  }
}

/// A tappable tinted call-to-action row: icon chip, title, caption, arrow.
class SevoLinkCard extends StatelessWidget {
  const SevoLinkCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.tone = SevoTone.info,
    this.index = 0,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final SevoTone tone;
  final int index;

  @override
  Widget build(BuildContext context) {
    final c = SevoToneColors.of(tone);
    return SevoAnimatedCard(
      index: index,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: c.bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.border),
            ),
            child: Icon(icon, size: 20, color: c.fg),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: SevoText.bodyStrong),
                const SizedBox(height: 1),
                Text(subtitle, style: SevoText.caption),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Icon(Icons.arrow_forward_rounded, size: 18, color: c.fg),
        ],
      ),
    );
  }
}
