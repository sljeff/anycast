import 'dart:ui';

import 'package:anycast/design_system/anycast_theme.dart';
import 'package:flutter/material.dart';

class AnycastGlassSurface extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;
  final Color? tint;

  const AnycastGlassSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(
      Radius.circular(AnycastRadius.card),
    ),
    this.padding,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final resolvedTint = tint ?? colors.surface;
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: resolvedTint,
            borderRadius: borderRadius,
            border: Border.all(
              color: AnycastColor.sandAlpha4(theme.brightness),
            ),
            boxShadow: [
              BoxShadow(
                color: colors.shadow.withValues(alpha: .08),
                blurRadius: 32,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: padding == null
              ? child
              : Padding(padding: padding!, child: child),
        ),
      ),
    );
  }
}

class AnycastEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  const AnycastEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AnycastSpacing.large),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: theme.colorScheme.primary,
                  size: 30,
                ),
              ),
              const SizedBox(height: AnycastSpacing.cardInner),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium,
              ),
              const SizedBox(height: AnycastSpacing.md),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (action != null) ...[
                const SizedBox(height: AnycastSpacing.pageHeader),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class AnycastCompactProgress extends StatelessWidget {
  final double value;

  const AnycastCompactProgress({
    super.key,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LinearProgressIndicator(
      value: value.clamp(0.0, 1.0).toDouble(),
      minHeight: AnycastSpacing.compactProgress,
      color: theme.colorScheme.primary,
      backgroundColor: AnycastColor.sandAlpha4(theme.brightness),
    );
  }
}
