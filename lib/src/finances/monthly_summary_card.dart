import 'package:budget_ai/src/finances/monthly_summary_service.dart';
import 'package:budget_ai/src/helpers/app_button.dart';
import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:flutter/material.dart';

class MonthlySummaryCard extends StatefulWidget {
  const MonthlySummaryCard({super.key, required this.month, this.service});
  final DateTime month;
  final MonthlySummaryService? service;

  @override
  State<MonthlySummaryCard> createState() => _MonthlySummaryCardState();
}

class _MonthlySummaryCardState extends State<MonthlySummaryCard> {
  late final MonthlySummaryService _service =
      widget.service ?? MonthlySummaryService();
  MonthlySummary? _summary;
  bool _loading = true;
  bool _generating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final summary = await _service.load(widget.month);
      if (mounted) setState(() => _summary = summary);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load the saved summary.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _generate() async {
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final summary = await _service.generate(widget.month);
      if (mounted) setState(() => _summary = summary);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Bad state: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_awesome_outlined,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Monthly Summary',
                  style: AppTheme.bodyMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading)
            const LinearProgressIndicator()
          else
            Text(
              _summary?.text ??
                  'Get a short summary of this month’s income, expenses, and balance.',
              style: AppTheme.bodyMedium.copyWith(height: 1.5),
            ),
          if (_summary != null) ...[
            const SizedBox(height: 8),
            Text(
              'Saved on this device · ${_summary!.generatedAt.day}/${_summary!.generatedAt.month}/${_summary!.generatedAt.year}',
              style: AppTheme.bodySmall.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: AppTheme.bodySmall.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 14),
          AppButton(
            text: _summary == null ? 'Generate Summary' : 'Regenerate Summary',
            icon: _summary == null
                ? Icons.auto_awesome_outlined
                : Icons.refresh,
            isLoading: _generating,
            onPressed: _loading || _generating ? null : _generate,
            variant: _summary == null
                ? AppButtonVariant.filled
                : AppButtonVariant.outlined,
          ),
        ],
      ),
    );
  }
}
