import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'frosted.dart';
import 'motion.dart';

/// 3 × 4 keypad drawn in the app (no system keyboard): 1–9, a [special]
/// key ("#" for rooms, "." for amounts), 0 and delete. Long-press delete
/// clears. Keys are keyed `'$keyPrefix$label'` and `'${keyPrefix}back'`.
class DrawnKeypad extends StatelessWidget {
  const DrawnKeypad({
    super.key,
    this.special,
    this.specialLabel = '',
    required this.keyPrefix,
    required this.onKey,
    required this.onDelete,
    required this.onClear,
  });

  /// Bottom-left key; null leaves that slot empty (digits only).
  final String? special;

  /// Spoken name of [special], e.g. "井号" / "小数点".
  final String specialLabel;
  final String keyPrefix;
  final ValueChanged<String> onKey;
  final VoidCallback onDelete;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      [special ?? '', '0', '⌫'],
    ];
    return Column(
      children: [
        for (var r = 0; r < rows.length; r++) ...[
          if (r > 0) const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              for (var c = 0; c < 3; c++) ...[
                if (c > 0) const SizedBox(width: AppSpacing.sm),
                Expanded(child: _key(rows[r][c])),
              ],
            ],
          ),
        ],
      ],
    );
  }

  Widget _key(String label) {
    if (label.isEmpty) return const SizedBox(height: 52);
    if (label == '⌫') {
      return _Key(
        key: Key('${keyPrefix}back'),
        semantics: '删除，长按清空',
        onTap: onDelete,
        onLongPress: onClear,
        muted: true,
        child: const Icon(Icons.backspace_outlined, size: 22),
      );
    }
    final isSpecial = label == special;
    return _Key(
      key: Key('$keyPrefix$label'),
      semantics: isSpecial ? specialLabel : label,
      onTap: () => onKey(label),
      muted: isSpecial,
      child: Text(label),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({
    super.key,
    required this.semantics,
    required this.onTap,
    required this.child,
    this.onLongPress,
    this.muted = false,
  });

  final String semantics;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget child;

  /// Function keys sit on a slightly deeper tint.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      label: semantics,
      excludeSemantics: true,
      child: PressScale(
        scale: 0.94,
        child: FrostedCard(
          radius: AppRadius.md + 2,
          fill: muted
              ? scheme.surfaceContainerHighest.withValues(alpha: 0.7)
              : null,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: SizedBox(
              height: 52,
              child: Center(
                child: DefaultTextStyle.merge(
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w500,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  child: IconTheme.merge(
                    data: IconThemeData(color: scheme.onSurface),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Blinking text caret for drawn input displays. Solid while [typing]
/// changes; still when the user asked for reduced motion.
class BlinkingCaret extends StatefulWidget {
  const BlinkingCaret({
    super.key,
    required this.height,
    this.visible = true,
    this.typing = '',
  });

  final double height;
  final bool visible;

  /// The current text; any change restarts the caret solid.
  final String typing;

  @override
  State<BlinkingCaret> createState() => _BlinkingCaretState();
}

class _BlinkingCaretState extends State<BlinkingCaret> {
  var _on = true;
  late final _ticker = Stream<void>.periodic(const Duration(milliseconds: 530))
      .listen((_) {
        if (mounted && widget.visible && !AppMotion.reduced(context)) {
          setState(() => _on = !_on);
        }
      });

  @override
  void initState() {
    super.initState();
    _ticker; // start
  }

  @override
  void didUpdateWidget(BlinkingCaret oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.typing != widget.typing) _on = true;
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: widget.visible && _on ? 1 : 0,
      duration: const Duration(milliseconds: 90),
      child: Container(
        width: 2.5,
        height: widget.height,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// Display for a drawn-keypad input: label, value (or placeholder), a
/// blinking caret while [active], optional masking for passwords, and a
/// trailing hint. Tapping it opens/closes its keypad.
class DrawnField extends StatelessWidget {
  const DrawnField({
    super.key,
    required this.label,
    required this.text,
    required this.active,
    required this.onTap,
    this.enabled = true,
    this.icon,
    this.prefix = '',
    this.placeholder = '',
    this.hint,
    this.helper,
    this.obscure = false,
    this.error = false,
  });

  final String label;
  final String text;
  final bool active, enabled, obscure, error;
  final VoidCallback onTap;
  final IconData? icon;
  final String prefix, placeholder;
  final String? hint, helper;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final empty = text.isEmpty;
    final shown = obscure ? '•' * text.length : text;
    final valueStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: obscure ? 3 : 0.5,
      fontFeatures: const [FontFeature.tabularFigures()],
      color: enabled
          ? scheme.onSurface
          : scheme.onSurface.withValues(alpha: 0.4),
    );
    final edge = error
        ? BorderSide(color: scheme.error, width: 1.5)
        : active
        ? BorderSide(color: scheme.primary, width: 1.5)
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          textField: true,
          readOnly: true,
          label: label,
          value: empty ? '未输入' : (obscure ? '已输入 ${text.length} 位' : text),
          excludeSemantics: true,
          child: FrostedCard(
            radius: AppRadius.control,
            edge: edge,
            child: InkWell(
              onTap: enabled ? onTap : null,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      if (icon != null) ...[
                        Icon(
                          icon,
                          color: active
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: AppSpacing.md),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: active
                                    ? scheme.primary
                                    : scheme.onSurfaceVariant,
                              ),
                            ),
                            Row(
                              children: [
                                if (prefix.isNotEmpty && (!empty || active))
                                  Text(prefix, style: valueStyle),
                                Flexible(
                                  child: Text(
                                    empty ? (active ? '' : placeholder) : shown,
                                    maxLines: 1,
                                    overflow: TextOverflow.fade,
                                    softWrap: false,
                                    style: empty
                                        ? valueStyle?.copyWith(
                                            fontWeight: FontWeight.w400,
                                            color: scheme.onSurfaceVariant
                                                .withValues(alpha: 0.6),
                                          )
                                        : valueStyle,
                                  ),
                                ),
                                if (active) ...[
                                  const SizedBox(width: 1),
                                  BlinkingCaret(height: 20, typing: text),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (hint != null) ...[
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          hint!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(width: AppSpacing.sm),
                      AnimatedRotation(
                        turns: active ? 0.5 : 0,
                        duration: AppMotion.medium,
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (helper != null)
          Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.lg,
              top: AppSpacing.xs,
            ),
            child: Text(
              helper!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

/// Applies one keypad key to an amount: at most one ".", two decimals and
/// five whole digits, no leading zeros. Null when the key is rejected.
String? appendAmount(String current, String key) {
  if (key == '.') {
    if (current.contains('.')) return null;
    return current.isEmpty ? '0.' : '$current.';
  }
  final dot = current.indexOf('.');
  if (dot >= 0) {
    return current.length - dot - 1 >= 2 ? null : current + key;
  }
  if (current == '0') return key;
  return current.length >= 5 ? null : current + key;
}

/// Applies one digit key to a digits-only value of at most [max] length.
String? appendDigit(String current, String key, {int max = 16}) =>
    current.length >= max ? null : current + key;

/// Six-cell PIN entry (campus-card payment password). Each typed digit
/// drops a dot into its cell; the next empty cell is outlined with a
/// blinking caret while [active]. Digits are never shown.
class PinCells extends StatelessWidget {
  const PinCells({
    super.key,
    required this.filled,
    required this.active,
    required this.onTap,
    this.length = 6,
    this.enabled = true,
    this.error = false,
  });

  final int filled;
  final int length;
  final bool active, enabled, error;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduced = AppMotion.reduced(context);
    return Semantics(
      button: true,
      textField: true,
      readOnly: true,
      label: '$length 位支付密码',
      value: '已输入 $filled 位',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: Row(
          children: [
            for (var i = 0; i < length; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: FrostedCard(
                    radius: AppRadius.md,
                    edge: error
                        ? BorderSide(color: scheme.error, width: 1.5)
                        : active && i == filled.clamp(0, length - 1)
                        ? BorderSide(color: scheme.primary, width: 1.5)
                        : null,
                    child: Center(
                      child: i < filled
                          ? TweenAnimationBuilder<double>(
                              key: ValueKey('pin.filled.$i'),
                              tween: Tween(begin: reduced ? 1 : 0, end: 1),
                              duration: AppMotion.medium,
                              curve: AppMotion.pop,
                              builder: (context, t, _) => Transform.scale(
                                scale: t,
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: scheme.onSurface,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            )
                          : active && i == filled
                          ? BlinkingCaret(height: 22, typing: '$filled')
                          : const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
