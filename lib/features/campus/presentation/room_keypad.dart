import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/drawn_keypad.dart';
import '../../../shared/widgets/frosted.dart';

/// Room numbers are "building#room", e.g. 9#312.
final _roomPattern = RegExp(r'^\d{1,3}#\d{1,5}$');
const _maxLength = 9;

/// Normalises a saved room for the keypad: "5号楼524" → "5#524"; anything
/// the keypad cannot type is dropped.
String keypadRoom(String? value) {
  final text = (value ?? '').trim().replaceAll(RegExp(r'\s+'), '');
  final legacy = RegExp(r'^(\d+)(?:号楼|栋|号)(\d+)$').firstMatch(text);
  if (legacy != null) return '${legacy[1]}#${legacy[2]}';
  final kept = text.replaceAll(RegExp(r'[^0-9#]'), '');
  return kept.length > _maxLength ? kept.substring(0, _maxLength) : kept;
}

/// Room entry with its own drawn keypad instead of the system keyboard:
/// a display with a blinking caret, keys 0–9, "#" and delete (long-press
/// clears), and a submit button. Hardware keyboards still work.
class RoomKeypadForm extends StatefulWidget {
  const RoomKeypadForm({
    super.key,
    required this.initial,
    required this.onSubmit,
  });

  final String? initial;
  final ValueChanged<String> onSubmit;

  @override
  State<RoomKeypadForm> createState() => _RoomKeypadFormState();
}

class _RoomKeypadFormState extends State<RoomKeypadForm> {
  late var _text = keypadRoom(widget.initial);
  String? _error;
  final _focus = FocusNode(debugLabel: 'room keypad');

  @override
  void initState() {
    super.initState();
    // Takes focus for hardware keys without asking for a soft keyboard.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _type(String key) {
    if (_text.length >= _maxLength) {
      HapticFeedback.mediumImpact();
      return;
    }
    // One "#", and not as the first character.
    if (key == '#' && (_text.isEmpty || _text.contains('#'))) {
      HapticFeedback.mediumImpact();
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      _text += key;
      _error = null;
    });
  }

  void _delete() {
    if (_text.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _text = _text.substring(0, _text.length - 1);
      _error = null;
    });
  }

  void _clear() {
    if (_text.isEmpty) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _text = '';
      _error = null;
    });
  }

  void _submit() {
    if (_text.isEmpty) {
      HapticFeedback.mediumImpact();
      setState(() => _error = '请输入宿舍号');
      return;
    }
    if (!_roomPattern.hasMatch(_text)) {
      HapticFeedback.mediumImpact();
      setState(() => _error = '请按「楼号#房间号」输入，例如 9#312');
      return;
    }
    widget.onSubmit(_text);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final char = event.character;
    if (char != null && RegExp(r'^[0-9#]$').hasMatch(char)) {
      _type(char);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace) {
      _delete();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _submit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Display(text: _text, error: _error != null),
          AnimatedSize(
            duration: AppMotion.medium,
            curve: AppMotion.emphasized,
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Semantics(
                liveRegion: _error != null,
                child: Text(
                  _error ?? '楼号 # 房间号，例如 9#312',
                  key: const Key('room.hint'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _error != null
                        ? scheme.error
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          DrawnKeypad(
            special: '#',
            specialLabel: '井号',
            keyPrefix: 'room.key.',
            onKey: _type,
            onDelete: _delete,
            onClear: _clear,
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            key: const Key('room.submit'),
            label: '查询电量',
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}

/// The typed room in large digits with a blinking caret.
class _Display extends StatelessWidget {
  const _Display({required this.text, required this.error});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final empty = text.isEmpty;
    final digits = theme.textTheme.headlineMedium?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: 2,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Semantics(
      key: const Key('room.input'),
      label: '宿舍号',
      value: empty ? '未输入' : text,
      textField: true,
      readOnly: true,
      excludeSemantics: true,
      child: FrostedCard(
        radius: AppRadius.lg + 2,
        edge: BorderSide(
          color: error ? scheme.error : scheme.primary,
          width: 1.5,
        ),
        child: SizedBox(
          height: 68,
          child: Row(
            children: [
              const SizedBox(width: AppSpacing.lg),
              Icon(Icons.meeting_room_outlined, color: scheme.onSurfaceVariant),
              Expanded(
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (empty)
                          Text(
                            '9#312',
                            style: digits?.copyWith(
                              color: scheme.onSurfaceVariant.withValues(
                                alpha: 0.35,
                              ),
                            ),
                          )
                        else
                          Text(text, style: digits),
                        const SizedBox(width: 2),
                        BlinkingCaret(height: 30, typing: text),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.lg + 24),
            ],
          ),
        ),
      ),
    );
  }
}
