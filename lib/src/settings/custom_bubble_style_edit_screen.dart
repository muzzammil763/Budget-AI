import 'package:budget_ai/src/chat/expandable_user_message_text.dart';
import 'package:budget_ai/src/chat/user_bubble_style_surface.dart';
import 'package:budget_ai/src/helpers/app_button.dart';
import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/helpers/responsive_info_sheet.dart';
import 'package:budget_ai/src/helpers/toast_helper.dart';
import 'package:budget_ai/src/settings/bubble_style_settings_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:toastification/toastification.dart';

sealed class CustomBubbleEditResult {
  const CustomBubbleEditResult();
}

class CustomBubbleSaved extends CustomBubbleEditResult {
  const CustomBubbleSaved(this.style);

  final CustomBubbleStyle style;
}

class CustomBubbleDeleted extends CustomBubbleEditResult {
  const CustomBubbleDeleted(this.id);

  final String id;
}

class CustomBubbleStyleEditScreen extends StatefulWidget {
  const CustomBubbleStyleEditScreen({super.key, this.style});

  final CustomBubbleStyle? style;

  static Future<CustomBubbleEditResult?> show(
    BuildContext context, {
    CustomBubbleStyle? style,
  }) {
    return Navigator.of(context).push<CustomBubbleEditResult>(
      MaterialPageRoute(
        builder: (_) => CustomBubbleStyleEditScreen(style: style),
      ),
    );
  }

  @override
  State<CustomBubbleStyleEditScreen> createState() =>
      _CustomBubbleStyleEditScreenState();
}

class _CustomBubbleStyleEditScreenState
    extends State<CustomBubbleStyleEditScreen> {
  late final TextEditingController _nameController;
  late Color _backgroundColor;
  late Color _textColor;
  late CustomBubbleShape _shape;
  late CustomBubblePattern _pattern;
  bool _isSaving = false;

  bool get _isEditing => widget.style != null;

  @override
  void initState() {
    super.initState();
    final style = widget.style ?? CustomBubbleStyle.fallback;
    _nameController = TextEditingController(
      text: widget.style?.name ?? 'My bubble',
    );
    _backgroundColor = Color(style.backgroundColorValue);
    _textColor = Color(style.textColorValue);
    _shape = style.shape;
    _pattern = style.pattern;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  CustomBubbleStyle get _previewStyle => CustomBubbleStyle(
    id: widget.style?.id ?? 'preview',
    name: _nameController.text.trim(),
    backgroundColorValue: _backgroundColor.toARGB32(),
    textColorValue: _textColor.toARGB32(),
    shape: _shape,
    pattern: _pattern,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actionLabel = _isEditing ? 'Save Changes' : 'Add Bubble';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: Navigator.of(context).pop,
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
        ),
        title: Text(_isEditing ? 'Edit Custom Bubble' : 'Add Custom Bubble'),
        actions: [
          IconButton(
            tooltip: actionLabel,
            onPressed: _isSaving ? null : _save,
            icon: _isSaving
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(CupertinoIcons.check_mark),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: [
            _buildPreview(theme),
            const SizedBox(height: 12),
            _buildSection(
              theme,
              title: 'STYLE NAME',
              child: TextField(
                key: const ValueKey('custom-bubble-name'),
                controller: _nameController,
                autofocus: !_isEditing,
                maxLength: 30,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Bubble name',
                  hintText: 'e.g. Ocean notes',
                  prefixIcon: Icon(CupertinoIcons.textformat),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _ColorControl(
              title: 'BUBBLE COLOR',
              color: _backgroundColor,
              onChanged: (color) => setState(() => _backgroundColor = color),
            ),
            const SizedBox(height: 12),
            _ColorControl(
              title: 'TEXT COLOR',
              color: _textColor,
              onChanged: (color) => setState(() => _textColor = color),
            ),
            const SizedBox(height: 12),
            _buildChoiceSection<CustomBubbleShape>(
              theme,
              title: 'SHAPE',
              values: CustomBubbleShape.values,
              selected: _shape,
              label: (shape) => shape.label,
              onSelected: (shape) => setState(() => _shape = shape),
            ),
            const SizedBox(height: 12),
            _buildChoiceSection<CustomBubblePattern>(
              theme,
              title: 'PATTERN',
              values: CustomBubblePattern.values,
              selected: _pattern,
              label: (pattern) => pattern.label,
              onSelected: (pattern) => setState(() => _pattern = pattern),
            ),
            const SizedBox(height: 12),
            AppButton(
              text: actionLabel,
              icon: CupertinoIcons.check_mark,
              height: 54,
              isLoading: _isSaving,
              onPressed: _isSaving ? null : _save,
            ),
            if (_isEditing) ...[
              const SizedBox(height: 12),
              AppButton(
                text: 'Delete Bubble',
                icon: CupertinoIcons.trash,
                height: 54,
                isRed: true,
                onPressed: _isSaving ? null : _confirmDelete,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(ThemeData theme) {
    final preview = _previewStyle;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'LIVE PREVIEW',
            style: AppTheme.bodySmall.copyWith(
              color: theme.colorScheme.primary,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.3,
            ),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: UserBubbleStyleSurface(
              style: UserBubbleStyle.custom,
              customStyle: preview,
              child: ExpandableUserMessageText(
                text: 'This is your custom message bubble.',
                style: UserBubbleStyleSurface.messageTextStyle(
                  context,
                  UserBubbleStyle.custom,
                  customStyle: preview,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
    ThemeData theme, {
    required String title,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTheme.bodySmall.copyWith(
              color: theme.colorScheme.primary,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.3,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildChoiceSection<T>(
    ThemeData theme, {
    required String title,
    required List<T> values,
    required T selected,
    required String Function(T value) label,
    required ValueChanged<T> onSelected,
  }) {
    return _buildSection(
      theme,
      title: title,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final value in values)
            ChoiceChip(
              label: Text(label(value)),
              selected: value == selected,
              showCheckmark: false,
              onSelected: (_) => onSelected(value),
            ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_isSaving) return;
    final service = BubbleStyleSettingsService.instance;
    final error = service.customStyleValidationError(
      _nameController.text,
      originalId: widget.style?.id,
    );
    if (error != null) {
      showAppToast(context, message: error, type: ToastificationType.error);
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    HapticFeedback.selectionClick();
    setState(() => _isSaving = true);
    final saved = await service.saveCustomStyle(
      originalId: widget.style?.id,
      name: _nameController.text,
      backgroundColorValue: _backgroundColor.toARGB32(),
      textColorValue: _textColor.toARGB32(),
      shape: _shape,
      pattern: _pattern,
    );
    if (!mounted) return;
    if (saved == null) {
      setState(() => _isSaving = false);
      showAppToast(
        context,
        message: 'Custom bubble could not be saved',
        type: ToastificationType.error,
      );
      return;
    }
    Navigator.of(context).pop(CustomBubbleSaved(saved));
  }

  Future<void> _confirmDelete() async {
    final style = widget.style;
    if (style == null) return;
    final confirmed = await ResponsiveInfoSheet.confirm(
      context,
      title: 'Delete Custom Bubble?',
      message: 'Delete "${style.name}"? This cannot be undone.',
      icon: CupertinoIcons.trash,
      confirmLabel: 'Delete',
      isRed: true,
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isSaving = true);
    final deleted = await BubbleStyleSettingsService.instance.deleteCustomStyle(
      style.id,
    );
    if (!mounted) return;
    if (!deleted) {
      setState(() => _isSaving = false);
      showAppToast(
        context,
        message: 'Custom bubble could not be deleted',
        type: ToastificationType.error,
      );
      return;
    }
    Navigator.of(context).pop(CustomBubbleDeleted(style.id));
  }
}

class _ColorControl extends StatelessWidget {
  const _ColorControl({
    required this.title,
    required this.color,
    required this.onChanged,
  });

  static const palette = <Color>[
    Color(0xFF2364AA),
    Color(0xFF087F79),
    Color(0xFF248A58),
    Color(0xFF6B4EFF),
    Color(0xFF9C3D78),
    Color(0xFFD75A3D),
    Color(0xFFF3B61F),
    Color(0xFF24262A),
    Color(0xFFFFFFFF),
    Color(0xFFDCF7D9),
    Color(0xFFFFF3D6),
    Color(0xFFB7A6FF),
  ];

  final String title;
  final Color color;
  final ValueChanged<Color> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: AppTheme.bodySmall.copyWith(
                  color: theme.colorScheme.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.3,
                ),
              ),
              const Spacer(),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: theme.colorScheme.outline),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _hex(color),
                style: AppTheme.bodySmall.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final swatch in palette)
                InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => onChanged(swatch),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: swatch,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: swatch.toARGB32() == color.toARGB32()
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outline.withValues(alpha: 0.4),
                        width: swatch.toARGB32() == color.toARGB32() ? 3 : 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _ColorChannel(
            label: 'R',
            value: _channel(color, 16),
            color: Colors.red,
            onChanged: (value) =>
                onChanged(_withChannel(color, 16, value.round())),
          ),
          _ColorChannel(
            label: 'G',
            value: _channel(color, 8),
            color: Colors.green,
            onChanged: (value) =>
                onChanged(_withChannel(color, 8, value.round())),
          ),
          _ColorChannel(
            label: 'B',
            value: _channel(color, 0),
            color: Colors.blue,
            onChanged: (value) =>
                onChanged(_withChannel(color, 0, value.round())),
          ),
        ],
      ),
    );
  }

  static int _channel(Color color, int shift) =>
      (color.toARGB32() >> shift) & 0xFF;

  static Color _withChannel(Color color, int shift, int channel) {
    final mask = 0xFF << shift;
    final value = (color.toARGB32() & ~mask) | (channel << shift);
    return Color(value | 0xFF000000);
  }

  static String _hex(Color color) =>
      '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

class _ColorChannel extends StatelessWidget {
  const _ColorChannel({
    required this.label,
    required this.value,
    required this.color,
    required this.onChanged,
  });

  final String label;
  final int value;
  final Color color;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 18,
          child: Text(
            label,
            style: AppTheme.bodySmall.copyWith(fontWeight: FontWeight.w900),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: 0,
            max: 255,
            activeColor: color,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 30,
          child: Text(
            '$value',
            textAlign: TextAlign.end,
            style: AppTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
