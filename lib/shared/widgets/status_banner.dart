import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum StatusTone { error, warning, info }

/// Inline, non-blocking message with an optional recovery action.
class StatusBanner extends StatelessWidget {
  const StatusBanner({
    super.key,
    required this.message,
    this.title,
    this.tone = StatusTone.error,
    this.actionLabel,
    this.onAction,
    this.actionBusy = false,
    this.onDismiss,
  });

  final String message;
  final String? title;
  final StatusTone tone;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool actionBusy;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = StatusColors.of(context);
    final (background, foreground, icon) = switch (tone) {
      StatusTone.error => (
        scheme.errorContainer,
        scheme.onErrorContainer,
        Icons.error_outline_rounded,
      ),
      StatusTone.warning => (
        status.warningContainer,
        status.onWarningContainer,
        Icons.wifi_off_rounded,
      ),
      StatusTone.info => (
        scheme.surfaceContainerHigh,
        scheme.onSurfaceVariant,
        Icons.info_outline_rounded,
      ),
    };

    return Semantics(
      container: true,
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Padding(
          padding: EdgeInsetsDirectional.only(
            start: AppSpacing.lg,
            top: AppSpacing.md,
            bottom: actionLabel != null ? AppSpacing.xs : AppSpacing.md,
            end: onDismiss != null ? AppSpacing.xs : AppSpacing.lg,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(icon, size: 20, color: foreground),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null)
                      Text(
                        title!,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: foreground,
                        ),
                      ),
                    Text(
                      message,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: foreground,
                      ),
                    ),
                    if (actionLabel != null)
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Transform.translate(
                          offset: const Offset(-AppSpacing.md, 0),
                          child: TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: foreground,
                              disabledForegroundColor: foreground.withValues(
                                alpha: 0.6,
                              ),
                            ),
                            onPressed: actionBusy ? null : onAction,
                            child: actionBusy
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox.square(
                                        dimension: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: foreground,
                                        ),
                                      ),
                                      const SizedBox(width: AppSpacing.sm),
                                      Flexible(child: Text(actionLabel!)),
                                    ],
                                  )
                                : Text(actionLabel!),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (onDismiss != null)
                Transform.translate(
                  offset: const Offset(0, -AppSpacing.sm),
                  child: IconButton(
                    tooltip: '关闭提示',
                    onPressed: onDismiss,
                    color: foreground,
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
