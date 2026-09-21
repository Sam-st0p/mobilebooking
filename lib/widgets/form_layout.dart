// lib/widgets/form_layout.dart
//
// Small layout pieces shared by every step of the guided reservation:
// labelled fields, the responsive field grid, radio-style choice cards,
// bordered section panels, and the pink notice box.

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A field label with the required-field asterisk, e.g. "Full name *".
class FieldLabel extends StatelessWidget {
  final String text;
  final bool required;
  const FieldLabel(this.text, {super.key, this.required = true});

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: text),
          if (required) const TextSpan(text: ' *', style: TextStyle(color: AppColors.primary)),
        ],
      ),
      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
    );
  }
}

/// Label above a field, with an optional helper note beneath it.
class LabeledField extends StatelessWidget {
  final String label;
  final Widget child;
  final String? note;
  final Color? noteColor;
  final bool required;

  const LabeledField({
    super.key,
    required this.label,
    required this.child,
    this.note,
    this.noteColor,
    this.required = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(label, required: required),
        const SizedBox(height: 6),
        child,
        if (note != null) ...[
          const SizedBox(height: 6),
          Text(
            note!,
            style: TextStyle(fontSize: 11.5, height: 1.35, color: noteColor ?? AppColors.charcoal),
          ),
        ],
      ],
    );
  }
}

/// Lays children out in [wideColumns] columns when the available width is at
/// least [breakpoint], and in [narrowColumns] columns (default 1) otherwise.
class FieldGrid extends StatelessWidget {
  final List<Widget> children;
  final int wideColumns;
  final int narrowColumns;
  final double breakpoint;
  final double gap;

  const FieldGrid({
    super.key,
    required this.children,
    required this.wideColumns,
    this.narrowColumns = 1,
    this.breakpoint = 620,
    this.gap = 16,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= breakpoint ? wideColumns : narrowColumns;

        if (columns == 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(height: gap),
                children[i],
              ],
            ],
          );
        }

        final rows = <Widget>[];
        for (var start = 0; start < children.length; start += columns) {
          final slice = children.skip(start).take(columns).toList();
          rows.add(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var j = 0; j < columns; j++) ...[
                  if (j > 0) SizedBox(width: gap),
                  Expanded(child: j < slice.length ? slice[j] : const SizedBox.shrink()),
                ],
              ],
            ),
          );
          if (start + columns < children.length) rows.add(SizedBox(height: gap));
        }
        return Column(children: rows);
      },
    );
  }
}

/// A radio-style card (payment option, pickup/delivery). The whole card is
/// tappable; the selected card gets a rose border and blush fill.
class ChoiceCard extends StatelessWidget {
  final bool selected;
  final String title;
  final String? description;
  final VoidCallback? onTap;

  const ChoiceCard({
    super.key,
    required this.selected,
    required this.title,
    this.description,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: selected ? AppColors.primary : AppColors.border, width: selected ? 1.5 : 1),
    );
    return Semantics(
      container: true,
      inMutuallyExclusiveGroup: true,
      checked: selected,
      child: Material(
        color: selected ? AppColors.blush.withValues(alpha: 0.18) : AppColors.white,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    size: 20,
                    color: selected ? AppColors.primary : AppColors.charcoal,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      if (description != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          description!,
                          style: const TextStyle(fontSize: 12, height: 1.4, color: AppColors.charcoal),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A white, bordered, rounded panel with an optional bold title.
class SectionPanel extends StatelessWidget {
  final String? title;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;

  const SectionPanel({
    super.key,
    this.title,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? AppColors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(title!, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
          ],
          child,
        ],
      ),
    );
  }
}

/// The pink notice box used for payment notes, "still needed" lists, etc.
class NoticeBox extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double fillAlpha;

  const NoticeBox({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.fillAlpha = 0.5,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.blush.withValues(alpha: fillAlpha),
        border: Border.all(color: AppColors.dustyRose.withValues(alpha: 0.7)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: child,
    );
  }
}