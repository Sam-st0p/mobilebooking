// lib/widgets/rental_guide_scaffold.dart
//
// Shared layout for the four static "Rental Guide" pages (How to Book,
// Rental Requirements, Terms & Conditions, FAQs), ported from the web app's
// /how-to-book, /rental-requirements, /terms, /faq pages. Content is fixed
// business copy from the live site, not fetched from any API.
//
// Each page supplies: an eyebrow label, title, subtitle, optional notice
// box text, and its own body. This scaffold renders the shared header,
// wraps the body in a scroll view, and renders the "Continue through the
// rental guide" cross-navigation footer shown on every one of these pages.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';
import 'form_layout.dart';

class GuideLink {
  final String label;
  final String path;
  const GuideLink(this.label, this.path);
}

/// The four pages link to each other, in this fixed order, matching the
/// pill row shown at the bottom of every guide page on the website.
const List<GuideLink> kGuideLinks = [
  GuideLink('How to Book', '/how-to-book'),
  GuideLink('Rental Requirements', '/rental-requirements'),
  GuideLink('Terms & Conditions', '/terms'),
  GuideLink('FAQs', '/faq'),
];

class RentalGuideScaffold extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String subtitle;
  final String? noticeText;
  final Widget body;

  /// Path of the page currently showing, so its pill in the footer can be
  /// shown as selected instead of tappable.
  final String currentPath;

  const RentalGuideScaffold({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.body,
    required this.currentPath,
    this.noticeText,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 700;
            return SingleChildScrollView(
              padding: EdgeInsets.all(wide ? 24 : 16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 960),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        eyebrow.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 11,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        title,
                        style: TextStyle(fontSize: wide ? 32 : 26, height: 1.15, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        subtitle,
                        style: const TextStyle(fontSize: 13.5, height: 1.5, color: AppColors.charcoal),
                      ),
                      if (noticeText != null) ...[
                        const SizedBox(height: 16),
                        NoticeBox(
                          child: Text(
                            noticeText!,
                            style: const TextStyle(fontSize: 12.5, height: 1.45, color: AppColors.textPrimary),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      body,
                      const SizedBox(height: 24),
                      _footer(context),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _footer(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Continue through the rental guide',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.charcoal),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final link in kGuideLinks) _pill(context, link),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pill(BuildContext context, GuideLink link) {
    final selected = link.path == currentPath;
    return Material(
      color: selected ? AppColors.primary : AppColors.white,
      shape: StadiumBorder(side: BorderSide(color: selected ? AppColors.primary : AppColors.border)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: selected ? null : () => context.push(link.path),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Text(
            link.label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: selected ? AppColors.white : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

/// A responsive grid of [GuideCard]s: 2 columns when there is room, 1
/// column on phones. Used by How to Book and Rental Requirements.
class GuideCardGrid extends StatelessWidget {
  final List<Widget> children;
  const GuideCardGrid({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 620 ? 2 : 1;
        if (columns == 1) {
          return Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(height: 16),
                children[i],
              ],
            ],
          );
        }
        final rows = <Widget>[];
        for (var i = 0; i < children.length; i += 2) {
          final hasSecond = i + 1 < children.length;
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: children[i]),
                  const SizedBox(width: 16),
                  Expanded(child: hasSecond ? children[i + 1] : const SizedBox.shrink()),
                ],
              ),
            ),
          );
          if (i + 2 < children.length) rows.add(const SizedBox(height: 16));
        }
        return Column(children: rows);
      },
    );
  }
}

/// One card in the guide grid: an optional step/number label, a bold
/// title, body text, and optional bullet points.
class GuideCard extends StatelessWidget {
  final String? stepLabel; // e.g. "STEP 01" or "01"
  final String title;
  final String? body;
  final List<String> bullets;

  /// An extra inset box for a nested callout (used by the "Requests may not
  /// be processed when…" box on the Rental Requirements page).
  final Widget? insetBox;

  const GuideCard({
    super.key,
    required this.title,
    this.stepLabel,
    this.body,
    this.bullets = const [],
    this.insetBox,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (stepLabel != null) ...[
            Text(
              stepLabel!.toUpperCase(),
              style: const TextStyle(
                fontSize: 10.5,
                letterSpacing: 1,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 6),
          ],
          Text(title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
          if (body != null) ...[
            const SizedBox(height: 6),
            Text(body!, style: const TextStyle(fontSize: 12.5, height: 1.5, color: AppColors.charcoal)),
          ],
          if (bullets.isNotEmpty) ...[
            const SizedBox(height: 8),
            BulletList(items: bullets),
          ],
          if (insetBox != null) ...[
            const SizedBox(height: 10),
            insetBox!,
          ],
        ],
      ),
    );
  }
}

/// Simple "•  text" list, wrapped consistently wherever bullet points are
/// used across the guide pages.
class BulletList extends StatelessWidget {
  final List<String> items;
  final TextStyle? style;
  const BulletList({super.key, required this.items, this.style});

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = style ?? const TextStyle(fontSize: 12.5, height: 1.5, color: AppColors.charcoal);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('•  ', style: effectiveStyle),
                Expanded(child: Text(item, style: effectiveStyle)),
              ],
            ),
          ),
      ],
    );
  }
}