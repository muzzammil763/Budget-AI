import 'package:budget_ai/src/finances/finance_service.dart';
import 'package:budget_ai/src/helpers/app_button.dart';
import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/helpers/responsive_info_sheet.dart';
import 'package:budget_ai/src/helpers/toast_helper.dart';
import 'package:budget_ai/src/tools/finance_entry_tool_helpers.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:toastification/toastification.dart';

/// Outcome the edit screen pops with, so the caller can update its list in
/// place: the entry was saved (with the updated value) or removed (by id).
sealed class FinanceEntryEditResult {
  const FinanceEntryEditResult();
}

class FinanceEntrySaved extends FinanceEntryEditResult {
  const FinanceEntrySaved(this.entry);

  final FinanceEntry entry;
}

class FinanceEntryRemoved extends FinanceEntryEditResult {
  const FinanceEntryRemoved(this.id);

  final String id;
}

class FinanceEntryEditScreen extends StatefulWidget {
  const FinanceEntryEditScreen({super.key, required this.entry});

  final FinanceEntry entry;

  @override
  State<FinanceEntryEditScreen> createState() => _FinanceEntryEditScreenState();
}

class _FinanceEntryEditScreenState extends State<FinanceEntryEditScreen> {
  late final TextEditingController _descriptionController;
  late final TextEditingController _amountController;
  late final TextEditingController _categoryController;
  late FinanceEntryType _type;
  late DateTime _date;
  late bool _hasTime;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    _descriptionController = TextEditingController(text: entry.description);
    _amountController = TextEditingController(
      text: entry.amount == entry.amount.roundToDouble()
          ? entry.amount.toInt().toString()
          : entry.amount.toString(),
    );
    _categoryController = TextEditingController(text: entry.category);
    _type = entry.type;
    _date = entry.date;
    _hasTime = entry.hasTime;
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _amountController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _type == FinanceEntryType.income
        ? Colors.green
        : theme.colorScheme.error;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: Navigator.of(context).pop,
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
        ),
        title: const Text('Edit Finance Entry'),
        actions: [
          IconButton(
            tooltip: 'Delete entry',
            onPressed: _isSaving ? null : _confirmDelete,
            icon: Icon(CupertinoIcons.trash, color: theme.colorScheme.error),
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
            _buildAmountCard(theme, accent),
            const SizedBox(height: 12),
            _buildSection(
              theme,
              title: 'ENTRY TYPE',
              child: _buildTypeSelector(theme),
            ),
            const SizedBox(height: 12),
            _buildSection(
              theme,
              title: 'DETAILS',
              child: Column(
                children: [
                  _buildTextField(
                    theme,
                    controller: _descriptionController,
                    label: 'Title',
                    hint: 'e.g. Groceries, Salary',
                    icon: CupertinoIcons.textformat,
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    theme,
                    controller: _categoryController,
                    label: _type == FinanceEntryType.income
                        ? 'Income type'
                        : 'Category',
                    hint: _type == FinanceEntryType.income
                        ? 'e.g. Salary, Freelance'
                        : 'e.g. Food, Rent',
                    icon: CupertinoIcons.tag,
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'COMMON CATEGORIES',
                      style: AppTheme.bodySmall.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _categoryController,
                    builder: (context, value, _) {
                      final selected = value.text.trim().toLowerCase();
                      final categories = <String>{
                        ...(_type == FinanceEntryType.income
                            ? kIncomeCategories
                            : kFinanceCategories),
                        if (widget.entry.category.trim().isNotEmpty)
                          widget.entry.category.trim(),
                      }.toList();
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 8,
                          children: categories.map((category) {
                            final isSelected =
                                category.toLowerCase() == selected;
                            return ChoiceChip(
                              label: Text(category),
                              selected: isSelected,
                              showCheckmark: false,
                              selectedColor: theme.colorScheme.primary,
                              backgroundColor: theme.colorScheme.surface,

                              side: BorderSide(
                                color: isSelected
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.outline.withValues(
                                        alpha: 0.24,
                                      ),
                              ),
                              labelStyle: AppTheme.bodySmall.copyWith(
                                color: isSelected
                                    ? theme.colorScheme.onPrimary
                                    : theme.colorScheme.onSurface,
                                fontWeight: FontWeight.w700,
                              ),
                              onSelected: (_) {
                                _categoryController.text = category;
                                _categoryController.selection =
                                    TextSelection.collapsed(
                                      offset: category.length,
                                    );
                              },
                            );
                          }).toList(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _buildSection(
              theme,
              title: 'DATE & TIME',
              child: Column(
                children: [
                  _buildPickerRow(
                    theme,
                    icon: CupertinoIcons.calendar,
                    label: 'Date',
                    value: _formatDate(_date),
                    onTap: _pickDate,
                  ),
                  const SizedBox(height: 8),
                  _buildPickerRow(
                    theme,
                    icon: CupertinoIcons.time,
                    label: 'Time',
                    value: _hasTime ? _formatTime(_date) : 'Not specified',
                    onTap: _hasTime ? _pickTime : null,
                    trailing: Switch.adaptive(
                      value: _hasTime,
                      onChanged: (value) => setState(() {
                        _hasTime = value;
                        if (!value) {
                          _date = DateTime(_date.year, _date.month, _date.day);
                        }
                      }),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 54,
              child: FilledButton.icon(
                onPressed: _isSaving ? null : _save,
                icon: _isSaving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(CupertinoIcons.checkmark_alt),
                label: Text(_isSaving ? 'Saving' : 'Save Changes'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAmountCard(ThemeData theme, Color accent) {
    final readable = AppTheme.readableOn(accent);
    return Container(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent, accent.withValues(alpha: 0.76)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.18),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _type == FinanceEntryType.income
                ? 'INCOME AMOUNT'
                : 'EXPENSE AMOUNT',
            style: AppTheme.bodySmall.copyWith(
              color: readable.withValues(alpha: 0.72),
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
          TextField(
            controller: _amountController,
            cursorColor: readable,
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
            ],
            style: AppTheme.headingLarge.copyWith(
              color: readable,
              fontSize: 36,
              fontWeight: FontWeight.w900,
            ),
            decoration: InputDecoration(
              filled: false,
              fillColor: Colors.transparent,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              contentPadding: const EdgeInsets.only(top: 2),
              isDense: true,
              hintText: '0',
              hintStyle: TextStyle(color: readable.withValues(alpha: 0.42)),
              suffixText: FinanceEntry.money(0).replaceFirst('0', '').trim(),
              suffixStyle: AppTheme.headingSmall.copyWith(color: readable),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeSelector(ThemeData theme) {
    return Row(
      children: FinanceEntryType.values.map((type) {
        final selected = _type == type;
        final isIncome = type == FinanceEntryType.income;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: isIncome ? 0 : 8),
            child: Material(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() => _type = type),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outline.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isIncome
                            ? CupertinoIcons.arrow_down_left
                            : CupertinoIcons.arrow_up_right,
                        color: selected
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurface,
                        size: 18,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        isIncome ? 'Income' : 'Expense',
                        style: TextStyle(
                          color: selected
                              ? theme.colorScheme.onPrimary
                              : theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSection(
    ThemeData theme, {
    required String title,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
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
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.3,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  // Auth-screen-inspired field: floating label, hint, and prefix icon over the
  // shared filled 12-radius input theme, for a consistent look across the app.
  Widget _buildTextField(
    ThemeData theme, {
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required TextCapitalization textCapitalization,
  }) {
    return TextField(
      controller: controller,
      cursorColor: theme.colorScheme.primary,
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      textCapitalization: textCapitalization,
      style: AppTheme.bodyLarge.copyWith(
        color: theme.colorScheme.onSurface,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 20),
      ),
    );
  }

  Widget _buildPickerRow(
    ThemeData theme, {
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback? onTap,
    Widget? trailing,
  }) {
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.075),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppTheme.bodySmall.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                    Text(
                      value,
                      style: AppTheme.bodyMedium.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 3660)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _date = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _hasTime ? _date.hour : 0,
        _hasTime ? _date.minute : 0,
      );
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _date = DateTime(
        _date.year,
        _date.month,
        _date.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  Future<void> _save() async {
    final description = _descriptionController.text.trim();
    final category = _categoryController.text.trim();
    final amount = double.tryParse(_amountController.text.trim());
    if (description.isEmpty ||
        category.isEmpty ||
        amount == null ||
        amount <= 0) {
      showAppToast(
        context,
        message: 'Enter a title, category, and amount greater than zero',
        type: ToastificationType.error,
      );
      return;
    }
    if (category.toLowerCase() == 'other' ||
        category.toLowerCase() == 'others') {
      showAppToast(
        context,
        message: 'Use a specific category instead of Others',
        type: ToastificationType.error,
      );
      return;
    }

    setState(() => _isSaving = true);
    final updated = widget.entry.copyWith(
      type: _type,
      date: _date,
      hasTime: _hasTime,
      description: normalizeNewFinanceLabel(description),
      amount: amount,
      category: normalizeNewFinanceCategory(
        category,
        description: normalizeNewFinanceLabel(description),
      ),
    );
    final saved = await FinanceService.instance.update(updated);
    if (!mounted) return;
    if (saved == null) {
      setState(() => _isSaving = false);
      showAppToast(
        context,
        message: 'Finance entry could not be updated',
        type: ToastificationType.error,
      );
      return;
    }
    Navigator.of(context).pop(FinanceEntrySaved(saved));
  }

  Future<void> _confirmDelete() async {
    final theme = Theme.of(context);
    final confirmed = await ResponsiveInfoSheet.show<bool>(
      context,
      title: 'Delete Finance Entry?',
      headerIcon: Icon(
        CupertinoIcons.trash,
        size: 30,
        color: AppTheme.readableOn(theme.colorScheme.error),
      ),
      gradientColors: [
        theme.colorScheme.error,
        theme.colorScheme.error.withValues(alpha: 0.78),
      ],
      contentWidgets: [
        Text(
          'Delete "${widget.entry.description}" (${widget.entry.displayAmount})? '
          'This cannot be undone.',
          style: AppTheme.bodyMedium.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 14,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Row(
          spacing: 12,
          children: [
            Expanded(
              child: AppButton(
                text: 'Cancel',
                variant: AppButtonVariant.outlined,
                onPressed: () => Navigator.pop(context, false),
              ),
            ),
            Expanded(
              child: AppButton(
                text: 'Delete',
                isRed: true,
                onPressed: () => Navigator.pop(context, true),
              ),
            ),
          ],
        ),
      ],
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isSaving = true);
    final deleted = await FinanceService.instance.delete(widget.entry.id);
    if (!mounted) return;
    if (!deleted) {
      setState(() => _isSaving = false);
      showAppToast(
        context,
        message: 'Finance entry could not be deleted',
        type: ToastificationType.error,
      );
      return;
    }
    Navigator.of(context).pop(FinanceEntryRemoved(widget.entry.id));
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day.toString().padLeft(2, '0')} ${months[date.month - 1]} ${date.year}';
  }

  String _formatTime(DateTime date) {
    final hour = date.hour == 0
        ? 12
        : date.hour > 12
        ? date.hour - 12
        : date.hour;
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${date.hour >= 12 ? 'PM' : 'AM'}';
  }
}
