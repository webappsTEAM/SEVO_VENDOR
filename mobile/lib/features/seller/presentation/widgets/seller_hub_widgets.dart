import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/sevo/sevo_animated_card.dart';
import '../../../../shared/widgets/sevo/sevo_module_frame.dart';
import '../../../../shared/widgets/sevo/sevo_search_field.dart';
import '../../../../shared/widgets/sevo/sevo_skeleton.dart';
import '../../../../shared/widgets/sevo/sevo_typography.dart';

/// Shared building blocks for the Seller Hub screens (Home, Orders, Returns),
/// in the SEVO mobile visual language.

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sept',
  'Oct',
  'Nov',
  'Dec',
];

String _two(int v) => v.toString().padLeft(2, '0');

/// `29 Sept, 10:04` — matches the Web `en-GB` day/short-month/time format.
String formatSellerDateTime(DateTime? d) {
  if (d == null) return '—';
  return '${d.day} ${_months[d.month - 1]}, ${_two(d.hour)}:${_two(d.minute)}';
}

/// `19/09/2026` — matches the Web `toLocaleDateString('en-GB')`.
String formatSellerDate(DateTime? d) {
  if (d == null) return '-';
  return '${_two(d.day)}/${_two(d.month)}/${d.year}';
}

/// `19/09/2026, 14:05:09` — matches the Web `toLocaleString('en-GB')`.
String formatSellerTimestamp(DateTime? d) {
  if (d == null) return '';
  return '${formatSellerDate(d)}, ${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}';
}

/// `19 Sept 2026` — the Web `{day, month: 'short', year}` format.
String formatSellerLongDate(DateTime? d) {
  if (d == null) return '—';
  return '${d.day} ${_months[d.month - 1]} ${d.year}';
}

String formatRupees(double amount) => '₹ ${amount.toStringAsFixed(2)}';

/// `₹69,404` — Indian digit grouping (lakh / crore), no decimals.
String formatRupeesCompact(double amount) {
  final negative = amount < 0;
  final digits = amount.abs().round().toString();
  String grouped;
  if (digits.length <= 3) {
    grouped = digits;
  } else {
    final last3 = digits.substring(digits.length - 3);
    var rest = digits.substring(0, digits.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    grouped = '${parts.join(',')},$last3';
  }
  return '${negative ? '-' : ''}₹$grouped';
}

/// Full-width dropdown filter (e.g. "All Claim Types").
class SellerDropdownFilter extends StatelessWidget {
  const SellerDropdownFilter({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String value;
  final List<(String, String)> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final safeValue = options.any((o) => o.$1 == value)
        ? value
        : options.first.$1;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.input + 2),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.cardShadow,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: safeValue,
          isExpanded: true,
          dropdownColor: AppColors.elevatedSurface,
          borderRadius: BorderRadius.circular(14),
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: AppColors.textSecondary,
          ),
          style: SevoText.bodyStrong,
          items: [
            for (final (v, label) in options)
              DropdownMenuItem(
                value: v,
                child: Text(label, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

/// Page header. Inside a [SevoModuleFrame] the frame already shows the title,
/// so only the badge and the actions are drawn (as a compact row); outside a
/// frame it renders the original title card.
class SellerHubHeader extends StatelessWidget {
  const SellerHubHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.badge,
    this.iconColor = AppColors.emerald,
    this.actions = const [],
  });

  final IconData icon;
  final String title;
  final String description;
  final String? badge;
  final Color iconColor;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    if (SevoFrameScope.isInside(context)) {
      if (badge == null && actions.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (badge != null)
            SellerPill(label: badge!.toUpperCase(), color: iconColor),
          if (badge != null && actions.isNotEmpty) const SizedBox(height: 10),
          if (actions.isNotEmpty)
            Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      );
    }
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: AppColors.heroGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Colors.white, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(title, style: SevoText.cardTitle),
                        if (badge != null)
                          SellerPill(
                            label: badge!.toUpperCase(),
                            color: iconColor,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(description, style: SevoText.caption),
                  ],
                ),
              ),
            ],
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ],
      ),
    );
  }
}

/// Small rounded label, e.g. "MERCHANT CENTER" or "Live Data".
class SellerPill extends StatelessWidget {
  const SellerPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    // Lighten strong colours on dark surfaces so the text stays readable.
    final fg = AppColors.isDark
        ? Color.lerp(color, Colors.white, 0.35)!
        : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: AppColors.isDark ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SevoText.badge.copyWith(
                fontSize: 10.5,
                color: fg,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact header action button (refresh, cross-links).
class SellerHeaderAction extends StatelessWidget {
  const SellerHeaderAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.primary = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(
      backgroundColor: primary ? AppColors.actionColor : AppColors.selectedTint,
      foregroundColor: primary ? Colors.white : AppColors.selectedOnTint,
      disabledBackgroundColor: AppColors.surfaceMuted,
      minimumSize: const Size(0, 38),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
    final text = Text(label, style: SevoText.button.copyWith(fontSize: 12.5));
    return icon == null
        ? FilledButton(onPressed: onPressed, style: style, child: text)
        : FilledButton.icon(
            onPressed: onPressed,
            style: style,
            icon: Icon(icon, size: 16),
            label: text,
          );
  }
}

/// Upper-case section label, e.g. "LIVE STORE CONFIGURATIONS".
class SellerSectionLabel extends StatelessWidget {
  const SellerSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.sm),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 13,
            decoration: BoxDecoration(
              color: AppColors.actionColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: SevoText.overline.copyWith(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

/// Metric tile: icon chip, value, label and caption on a tinted gradient with a
/// faint icon watermark. Optionally tappable and selectable (Returns uses tiles
/// as filters, like the Web).
class SellerMetricTile extends StatelessWidget {
  const SellerMetricTile({
    super.key,
    required this.label,
    required this.value,
    required this.caption,
    required this.icon,
    required this.color,
    this.onTap,
    this.selected = false,
    this.trailing,
  });

  final String label;
  final String value;
  final String caption;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final bool selected;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark;
    final on = dark ? Color.lerp(color, Colors.white, 0.4)! : color;
    return SevoAnimatedCard(
      onTap: onTap,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: dark
            ? [color.withValues(alpha: 0.16), AppColors.surface]
            : [color.withValues(alpha: 0.10), Colors.white],
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: selected ? color : Colors.transparent,
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
                    size: 66,
                    color: color.withValues(alpha: dark ? 0.09 : 0.07),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: dark ? 0.22 : 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(icon, size: 16, color: on),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: SevoText.overline.copyWith(
                              color: on,
                              fontSize: 10,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(value, style: SevoText.metric),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            caption,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: SevoText.meta.copyWith(
                              fontSize: 10.5,
                              height: 1.3,
                            ),
                          ),
                        ),
                        trailing ??
                            (onTap != null
                                ? Icon(
                                    Icons.chevron_right_rounded,
                                    size: 16,
                                    color: AppColors.textMuted,
                                  )
                                : const SizedBox.shrink()),
                      ],
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

/// Two-column responsive grid for metric tiles.
class SellerTileGrid extends StatelessWidget {
  const SellerTileGrid({
    super.key,
    required this.children,
    this.minTileWidth = 150,
  });

  final List<Widget> children;
  final double minTileWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final columns = (constraints.maxWidth / minTileWidth).floor().clamp(
          1,
          5,
        );
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final c in children) SizedBox(width: width, child: c),
          ],
        );
      },
    );
  }
}

/// Horizontally scrolling single-select filter chips (themed [ChoiceChip]s:
/// pill shape, animated selection with a soft glow).
class SellerFilterChips extends StatelessWidget {
  const SellerFilterChips({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.selectedColor = AppColors.primary,
  });

  /// (value, label) pairs.
  final List<(String, String)> options;
  final String selected;
  final ValueChanged<String> onSelected;
  final Color selectedColor;

  @override
  Widget build(BuildContext context) {
    final active = AppColors.isDark ? AppColors.actionColor : selectedColor;
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final (value, label) = options[i];
          final isSelected = value == selected;
          return ChoiceChip(
            label: Text(
              label,
              style: SevoText.badge.copyWith(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? Colors.white : AppColors.bodyText,
              ),
            ),
            selected: isSelected,
            showCheckmark: false,
            selectedColor: active,
            backgroundColor: AppColors.surface,
            elevation: isSelected ? 3 : 0,
            shadowColor: active.withValues(alpha: 0.4),
            pressElevation: 0,
            side: BorderSide(color: isSelected ? active : AppColors.border),
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            onSelected: (_) => onSelected(value),
          );
        },
      ),
    );
  }
}

/// Search field with an animated focus ring and clear button.
class SellerSearchField extends StatelessWidget {
  const SellerSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) =>
      SevoSearchField(controller: controller, hint: hint, onChanged: onChanged);
}

/// Loading / error-with-retry / empty states used by the list screens.
class SellerStateMessage extends StatelessWidget {
  const SellerStateMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.color,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color? color;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textMuted;
    final fg = AppColors.isDark ? Color.lerp(c, Colors.white, 0.3)! : c;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xl,
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.withValues(alpha: 0.10),
            ),
            child: Icon(icon, size: 34, color: fg),
          ),
          const SizedBox(height: 14),
          Text(title, textAlign: TextAlign.center, style: SevoText.section),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: SevoText.caption.copyWith(fontSize: 12.5, height: 1.5),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onAction,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.actionColor,
              ),
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

/// Loading placeholder: shimmering card skeletons with the message beneath.
class SellerLoading extends StatelessWidget {
  const SellerLoading({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SevoListSkeleton(count: 2),
        Text(message, style: SevoText.caption),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }
}

/// Labelled key/value line used inside detail sheets.
class SellerKeyValue extends StatelessWidget {
  const SellerKeyValue(this.label, this.value, {super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: SevoText.caption.copyWith(color: AppColors.textMuted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: SevoText.bodyStrong.copyWith(fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// Rounded panel used for detail-sheet sections and workflow steps.
class SellerPanel extends StatelessWidget {
  const SellerPanel({
    super.key,
    required this.child,
    this.tint,
    this.title,
    this.subtitle,
  });

  final Widget child;
  final Color? tint;
  final String? title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final t = tint;
    final tc = t == null
        ? null
        : (AppColors.isDark ? Color.lerp(t, Colors.white, 0.3)! : t);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t == null
            ? AppColors.surface
            : t.withValues(alpha: AppColors.isDark ? 0.12 : 0.06),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: t == null ? AppColors.border : t.withValues(alpha: 0.3),
        ),
        boxShadow: t == null ? AppColors.cardShadow : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Text(
              title!,
              style: SevoText.bodyStrong.copyWith(
                fontWeight: FontWeight.w600,
                color: tc ?? AppColors.headingText,
              ),
            ),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(subtitle!, style: SevoText.caption),
          ],
          if (title != null || subtitle != null) const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

/// Timeline row for fulfilment / return audit logs.
class SellerAuditRow extends StatelessWidget {
  const SellerAuditRow({
    super.key,
    required this.title,
    this.subtitle,
    this.note,
    required this.timestamp,
  });

  final String title;
  final String? subtitle;
  final String? note;
  final String timestamp;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 5),
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: AppColors.primaryAccent,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryAccent.withValues(alpha: 0.35),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: SevoText.bodyStrong.copyWith(fontSize: 12.5),
                      ),
                    ),
                    Text(
                      timestamp,
                      style: SevoText.meta.copyWith(fontSize: 10),
                    ),
                  ],
                ),
                if (subtitle != null) Text(subtitle!, style: SevoText.caption),
                if (note != null)
                  Text(
                    note!,
                    style: SevoText.caption.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
