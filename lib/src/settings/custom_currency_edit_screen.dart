import 'package:budget_ai/src/helpers/app_button.dart';
import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/helpers/toast_helper.dart';
import 'package:budget_ai/src/settings/currency_settings_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:toastification/toastification.dart';

class CustomCurrencyEditScreen extends StatefulWidget {
  const CustomCurrencyEditScreen({super.key, this.currency});

  final String? currency;

  static Future<bool?> show(BuildContext context, {String? currency}) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CustomCurrencyEditScreen(currency: currency),
      ),
    );
  }

  @override
  State<CustomCurrencyEditScreen> createState() =>
      _CustomCurrencyEditScreenState();
}

class _CustomCurrencyEditScreenState extends State<CustomCurrencyEditScreen> {
  late final TextEditingController _currencyController;
  bool _isSaving = false;

  bool get _isEditing => widget.currency != null;
  String get _value => _currencyController.text.trim();

  @override
  void initState() {
    super.initState();
    _currencyController = TextEditingController(text: widget.currency ?? '');
  }

  @override
  void dispose() {
    _currencyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actionLabel = _isEditing ? 'Save Changes' : 'Add Currency';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: Navigator.of(context).pop,
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
        ),
        title: Text(
          _isEditing ? 'Edit Custom Currency' : 'Add Custom Currency',
        ),
        actions: [
          IconButton(
            tooltip: actionLabel,
            onPressed: _isSaving ? null : _save,
            icon: _isSaving
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
          children: [
            Container(
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
                    'CUSTOM DISPLAY',
                    style: AppTheme.bodySmall.copyWith(
                      color: theme.colorScheme.primary,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.3,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('custom-currency-field'),
                    controller: _currencyController,
                    autofocus: true,
                    cursorColor: theme.colorScheme.primary,
                    textAlign: TextAlign.center,
                    textCapitalization: TextCapitalization.characters,
                    textInputAction: TextInputAction.done,
                    maxLength: kMaxCustomCurrencyCharacters,
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(
                        kMaxCustomCurrencyCharacters,
                      ),
                    ],
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _save(),
                    style: AppTheme.headingLarge.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontSize: 44,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Currency display',
                      hintText: 'e.g. CHF',
                      helperText: 'Up to 5 letters, symbols, or characters',
                      prefixIcon: Icon(CupertinoIcons.money_dollar, size: 22),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'PREVIEW',
                    style: AppTheme.bodySmall.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: Text(
                      _value.isEmpty
                          ? '1,200 —'
                          : CurrencySettingsService.instance.formatAmount(
                              1200,
                              currency: _value,
                            ),
                      key: ValueKey(_value),
                      style: AppTheme.headingSmall.copyWith(
                        color: _value.isEmpty
                            ? theme.colorScheme.onSurfaceVariant
                            : theme.colorScheme.onSurface,
                        fontSize: 24,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            AppButton(
              text: actionLabel,
              icon: CupertinoIcons.checkmark_alt,
              isLoading: _isSaving,
              onPressed: _isSaving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_isSaving) return;
    final error = CurrencySettingsService.instance
        .customCurrencyValidationError(_value, originalValue: widget.currency);
    if (error != null) {
      showAppToast(context, message: error, type: ToastificationType.error);
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    HapticFeedback.selectionClick();
    setState(() => _isSaving = true);
    final saved = await CurrencySettingsService.instance.saveCustomCurrency(
      _value,
      originalValue: widget.currency,
    );
    if (!mounted) return;
    if (!saved) {
      setState(() => _isSaving = false);
      showAppToast(
        context,
        message: 'Custom currency could not be saved',
        type: ToastificationType.error,
      );
      return;
    }
    Navigator.of(context).pop(true);
  }
}
