import 'dart:async';

import 'package:budget_ai/src/finances/finance_service.dart';
import 'package:budget_ai/src/helpers/app_button.dart';
import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/helpers/toast_helper.dart';
import 'package:budget_ai/src/settings/currency_settings_service.dart';
import 'package:budget_ai/src/widgets/home_widget_catalog.dart';
import 'package:budget_ai/src/widgets/home_widget_previews.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:toastification/toastification.dart';

/// Budget Hub → Home Screen Widgets: every widget previewed with the user's
/// numbers, one-tap pinning where Android's launcher supports it, and
/// step-by-step instructions everywhere else (iOS has no pinning API).
class HomeWidgetGalleryScreen extends StatefulWidget {
  const HomeWidgetGalleryScreen({super.key});

  static Future<void> show(BuildContext context) {
    return Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const HomeWidgetGalleryScreen()),
    );
  }

  @override
  State<HomeWidgetGalleryScreen> createState() =>
      _HomeWidgetGalleryScreenState();
}

class _HomeWidgetGalleryScreenState extends State<HomeWidgetGalleryScreen>
    with WidgetsBindingObserver {
  WidgetPreviewSnapshot? _snapshot;
  bool _pinSupported = false;
  Set<String> _installed = const {};
  final List<Timer> _refreshTimers = [];

  bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

  List<HomeWidgetDefinition> get _definitions => _isAndroid
      ? homeWidgetCatalog.where((widget) => widget.isOnAndroid).toList()
      : homeWidgetCatalog;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadSnapshot());
    unawaited(_loadPinSupport());
    unawaited(_refreshInstalled());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final timer in _refreshTimers) {
      timer.cancel();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refreshInstalled());
  }

  Future<void> _loadSnapshot() async {
    final entries = await FinanceService.instance.getAll();
    final currency = CurrencySettingsService.instance.current;
    final now = DateTime.now();
    var snapshot = WidgetPreviewSnapshot(
      entries: entries,
      currency: currency,
      now: now,
    );
    if (snapshot.entries.isEmpty) {
      snapshot = WidgetPreviewSnapshot.sample(currency: currency, now: now);
    }
    if (mounted) setState(() => _snapshot = snapshot);
  }

  Future<void> _loadPinSupport() async {
    if (!_isAndroid) return;
    try {
      final supported = await HomeWidget.isRequestPinWidgetSupported();
      if (mounted) setState(() => _pinSupported = supported ?? false);
    } catch (error) {
      debugPrint('[HomeWidgetGallery] Pin support unknown: $error');
    }
  }

  Future<void> _refreshInstalled() async {
    try {
      final widgets = await HomeWidget.getInstalledWidgets();
      final installed = <String>{
        for (final widget in widgets) ?widget.androidClassName?.split('.').last,
        for (final widget in widgets) ?widget.iOSKind,
      };
      if (mounted) setState(() => _installed = installed);
    } catch (error) {
      debugPrint('[HomeWidgetGallery] Installed widgets unknown: $error');
    }
  }

  bool _isInstalled(HomeWidgetDefinition widget) =>
      _installed.contains(_isAndroid ? widget.androidProvider : widget.iOSKind);

  Future<void> _addToHomeScreen(HomeWidgetDefinition widget) async {
    try {
      // Make sure the new widget opens with today's numbers.
      await FinanceService.instance.syncHomeWidget();
      await HomeWidget.requestPinWidget(
        qualifiedAndroidName: widget.qualifiedAndroidProvider,
      );
      if (!mounted) return;
      showAppToast(
        context,
        message: 'Confirm on the pop-up to place ${widget.title}',
      );
      // Launchers confirm in an overlay without pausing the app, so check
      // a few times for the newly placed widget.
      for (final seconds in const [2, 5, 10]) {
        _refreshTimers.add(
          Timer(Duration(seconds: seconds), () => _refreshInstalled()),
        );
      }
    } catch (error) {
      debugPrint('[HomeWidgetGallery] Pin request failed: $error');
      if (!mounted) return;
      setState(() => _pinSupported = false);
      showAppToast(
        context,
        message:
            "Your launcher can't add widgets from the app. Follow the steps "
            'below instead.',
        type: ToastificationType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snapshot = _snapshot;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: Navigator.of(context).pop,
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
        ),
        title: const Text('Home Screen Widgets'),
      ),
      body: snapshot == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: [
                _intro(theme, snapshot),
                const SizedBox(height: 16),
                if (!_isAndroid || !_pinSupported) ...[
                  _guide(theme),
                  const SizedBox(height: 20),
                ],
                for (final widget in _definitions) ...[
                  _widgetCard(theme, widget, snapshot),
                  const SizedBox(height: 12),
                ],
                if (_isAndroid && _pinSupported) ...[
                  const SizedBox(height: 8),
                  _guide(theme),
                ],
              ],
            ),
    );
  }

  Widget _intro(ThemeData theme, WidgetPreviewSnapshot snapshot) {
    final primary = theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(CupertinoIcons.square_grid_2x2, color: primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your budget at a glance',
                  style: AppTheme.headingSmall.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isAndroid && _pinSupported
                      ? 'See your spending without opening the app. Pick a '
                            'widget below and tap Add to Home Screen.'
                      : 'See your spending without opening the app. Tap any '
                            'widget to jump straight into Budget AI.',
                  style: AppTheme.bodySmall.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
                if (snapshot.isSample) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Previews show sample numbers until you add entries.',
                    key: const ValueKey('widget-gallery-sample-note'),
                    style: AppTheme.bodySmall.copyWith(
                      color: primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _widgetCard(
    ThemeData theme,
    HomeWidgetDefinition widget,
    WidgetPreviewSnapshot snapshot,
  ) {
    final installed = _isInstalled(widget);
    final canPin = _isAndroid && _pinSupported && widget.isOnAndroid;
    return Container(
      key: ValueKey('widget-gallery-${widget.id}'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: AppTheme.bodyMedium.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              if (installed)
                _chip(
                  'On Home Screen',
                  Colors.green.shade600,
                  icon: CupertinoIcons.checkmark_alt,
                )
              else
                _chip(
                  widget.size == HomeWidgetSize.lockScreen
                      ? widget.size.label
                      : '${widget.size.label} · ${widget.size.cells}',
                  theme.colorScheme.onSurfaceVariant,
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            widget.description,
            style: AppTheme.bodySmall.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: HomeWidgetPreview(definition: widget, snapshot: snapshot),
          ),
          if (canPin) ...[
            const SizedBox(height: 16),
            AppButton(
              key: ValueKey('widget-gallery-add-${widget.id}'),
              text: installed ? 'Add Another' : 'Add to Home Screen',
              icon: CupertinoIcons.add,
              variant: installed
                  ? AppButtonVariant.outlined
                  : AppButtonVariant.filled,
              onPressed: () => _addToHomeScreen(widget),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(String text, Color color, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: ShapeDecoration(
        color: color.withValues(alpha: 0.1),
        shape: const StadiumBorder(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            text,
            style: AppTheme.bodySmall.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _guide(ThemeData theme) {
    final steps = _isAndroid
        ? const [
            'Touch and hold an empty spot on your Home Screen.',
            'Tap Widgets.',
            'Find Budget AI, or search for it.',
            'Touch and hold the widget you want, then drag it into place.',
          ]
        : const [
            'Touch and hold an empty spot on your Home Screen until the apps '
                'jiggle.',
            'Tap Edit in the top corner, then Add Widget.',
            'Search for Budget AI.',
            'Swipe to the size you want, then tap Add Widget.',
          ];
    return Container(
      key: const ValueKey('widget-gallery-guide'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isAndroid && _pinSupported
                ? 'Prefer to add it yourself?'
                : 'How to add a widget',
            style: AppTheme.bodyMedium.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 10),
          for (final (index, step) in steps.indexed) _step(theme, index, step),
          if (!_isAndroid) ...[
            const SizedBox(height: 6),
            Text(
              'Lock Screen: touch and hold the Lock Screen, tap Customize, '
              'choose Lock Screen, tap the widget area, then pick Budget AI.',
              style: AppTheme.bodySmall.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            'Tip: tap a widget to open that part of Budget AI, and use ‹ › on '
            'month widgets to look back.',
            style: AppTheme.bodySmall.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _step(ThemeData theme, int index, String text) {
    final primary = theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Text(
              '${index + 1}',
              style: AppTheme.bodySmall.copyWith(
                color: primary,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                text,
                style: AppTheme.bodyMedium.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
