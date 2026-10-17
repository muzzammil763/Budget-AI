import 'package:budget_ai/src/billing/bubble_style_access.dart';
import 'package:budget_ai/src/billing/paywall_screen.dart';
import 'package:budget_ai/src/billing/premium_gate.dart';
import 'package:budget_ai/src/billing/premium_plans.dart';
import 'package:budget_ai/src/billing/subscription_service.dart';
import 'package:budget_ai/src/chat/expandable_user_message_text.dart';
import 'package:budget_ai/src/chat/user_bubble_style_surface.dart';
import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/settings/ai_usage_service.dart';
import 'package:budget_ai/src/settings/bubble_style_settings_service.dart';
import 'package:budget_ai/src/settings/custom_bubble_style_edit_screen.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BubbleStyleScreen extends StatelessWidget {
  const BubbleStyleScreen({super.key});

  static Future<void> show(BuildContext context) {
    return Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => const BubbleStyleScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: Navigator.of(context).pop,
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
        ),
        title: const Text('Message Bubble Style'),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: const _BubbleStyleScreenContent(),
          ),
        ),
      ),
    );
  }
}

class _BubbleStyleScreenContent extends StatefulWidget {
  const _BubbleStyleScreenContent();

  @override
  State<_BubbleStyleScreenContent> createState() =>
      _BubbleStyleScreenContentState();
}

class _BubbleStyleScreenContentState extends State<_BubbleStyleScreenContent> {
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _optionKeys = {};
  bool _didScheduleInitialScroll = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  GlobalKey _optionKey(String id) => _optionKeys.putIfAbsent(id, GlobalKey.new);

  void _scheduleReveal(String id) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final optionContext = _optionKeys[id]?.currentContext;
      if (optionContext == null) return;
      Scrollable.ensureVisible(
        optionContext,
        alignment: 0.18,
        duration: Duration.zero,
      );
    });
  }

  Future<void> _unlock(PremiumTier tier) async {
    HapticFeedback.selectionClick();
    await PaywallScreen.show(context, initialTier: tier);
  }

  Future<void> _selectPreset(UserBubbleStyle style) async {
    if (BubbleStyleSettingsService.instance.current == style) return;
    HapticFeedback.selectionClick();
    await BubbleStyleSettingsService.instance.setStyle(style);
  }

  Future<void> _selectCustom(CustomBubbleStyle style) async {
    final service = BubbleStyleSettingsService.instance;
    if (service.current == UserBubbleStyle.custom &&
        service.currentCustomStyle?.id == style.id) {
      return;
    }
    HapticFeedback.selectionClick();
    await service.setCustomStyle(style.id);
  }

  Future<void> _openCustomEditor({CustomBubbleStyle? style}) async {
    final result = await CustomBubbleStyleEditScreen.show(
      context,
      style: style,
    );
    if (!mounted || result == null) return;
    setState(() {});
    if (result case CustomBubbleSaved(:final style)) {
      _scheduleReveal('custom:${style.id}');
      return;
    }
    final service = BubbleStyleSettingsService.instance;
    final selectedId = service.current == UserBubbleStyle.custom
        ? 'custom:${service.currentCustomStyle?.id}'
        : 'preset:${service.current.name}';
    _scheduleReveal(selectedId);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final service = BubbleStyleSettingsService.instance;
    return Stack(
      children: [
        Positioned.fill(
          child: SingleChildScrollView(
            key: const ValueKey('bubble-style-options-scroll'),
            controller: _scrollController,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                  child: Text(
                    'Pick how your messages look in chat.',
                    style: AppTheme.bodySmall.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                AnimatedBuilder(
                  animation: Listenable.merge([
                    service.customStyles,
                    service.style,
                    AiUsageService.instance.usage,
                    SubscriptionService.instance.tier,
                  ]),
                  builder: (context, _) {
                    final tier = BubbleStyleAccess.currentTier;
                    final choices = [
                      for (final style in UserBubbleStyle.values)
                        if (style != UserBubbleStyle.custom)
                          _BubbleChoice.preset(style),
                      for (final custom in service.customStyles.value)
                        _BubbleChoice.custom(custom),
                    ];
                    // A style from a lapsed plan stays saved, but the picker
                    // marks what chat really draws.
                    final selected = BubbleStyleAccess.effective(
                      service.current,
                    );
                    final selectedId = selected == UserBubbleStyle.custom
                        ? 'custom:${service.currentCustomStyle?.id}'
                        : 'preset:${selected.name}';
                    if (!_didScheduleInitialScroll) {
                      _didScheduleInitialScroll = true;
                      _scheduleReveal(selectedId);
                    }

                    Widget option(_BubbleChoice choice) {
                      final required = BubbleStyleAccess.requiredTier(
                        choice.style,
                      );
                      final locked = !BubbleStyleAccess.isUnlocked(
                        choice.style,
                        tier,
                      );
                      return Padding(
                        key: _optionKey(choice.id),
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _BubbleStyleOption(
                          choice: choice,
                          selected: choice.id == selectedId,
                          lockedTier: locked ? required : null,
                          onTap: locked
                              ? () => _unlock(required)
                              : choice.customStyle == null
                              ? () => _selectPreset(choice.style)
                              : () => _selectCustom(choice.customStyle!),
                          onEdit: choice.customStyle == null || locked
                              ? null
                              : () => _openCustomEditor(
                                  style: choice.customStyle,
                                ),
                        ),
                      );
                    }

                    if (!PremiumGate.paywallEnabled) {
                      return Column(
                        children: [
                          for (final choice in choices) option(choice),
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final section in PremiumTier.values)
                          if (choices.any(
                            (choice) =>
                                BubbleStyleAccess.requiredTier(choice.style) ==
                                section,
                          )) ...[
                            _TierSectionHeader(
                              tier: section,
                              unlocked: section.index <= tier.index,
                              onUnlock: () => _unlock(section),
                            ),
                            for (final choice in choices)
                              if (BubbleStyleAccess.requiredTier(
                                    choice.style,
                                  ) ==
                                  section)
                                option(choice),
                          ],
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BubbleChoice {
  const _BubbleChoice._({
    required this.id,
    required this.label,
    required this.style,
    this.customStyle,
  });

  factory _BubbleChoice.preset(UserBubbleStyle style) => _BubbleChoice._(
    id: 'preset:${style.name}',
    label: style.label,
    style: style,
  );

  factory _BubbleChoice.custom(CustomBubbleStyle custom) => _BubbleChoice._(
    id: 'custom:${custom.id}',
    label: custom.name,
    style: UserBubbleStyle.custom,
    customStyle: custom,
  );

  final String id;
  final String label;
  final UserBubbleStyle style;
  final CustomBubbleStyle? customStyle;
}

class _BubbleStyleOption extends StatelessWidget {
  const _BubbleStyleOption({
    required this.choice,
    required this.selected,
    required this.onTap,
    this.lockedTier,
    this.onEdit,
  });

  final _BubbleChoice choice;
  final bool selected;

  /// The plan that unlocks this style, or null when it is available.
  final PremiumTier? lockedTier;
  final VoidCallback onTap;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lockedTier = this.lockedTier;
    final accent = lockedTier == null ? null : premiumTierAccent(lockedTier);
    return InkWell(
      key: ValueKey('bubble-style-${choice.id}'),
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : accent?.withValues(alpha: 0.35) ??
                      theme.colorScheme.outline.withValues(alpha: 0.25),
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (accent != null)
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      CupertinoIcons.lock_fill,
                      size: 15,
                      color: accent,
                    ),
                  )
                else
                  Icon(
                    selected
                        ? CupertinoIcons.check_mark_circled_solid
                        : CupertinoIcons.circle,
                    color: selected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline,
                    size: 30,
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    choice.label,
                    style: AppTheme.bodyMedium.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (lockedTier != null)
                  _UnlockChip(tier: lockedTier)
                else if (onEdit != null)
                  IconButton(
                    tooltip: 'Edit ${choice.label}',
                    onPressed: onEdit,
                    icon: const Icon(CupertinoIcons.square_pencil, size: 19),
                    color: theme.colorScheme.primary,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: UserBubbleStyleSurface(
                style: choice.style,
                customStyle: choice.customStyle,
                child: ExpandableUserMessageText(
                  text:
                      'This is how your message will look, take a look and '
                      'choose your style',
                  style: UserBubbleStyleSurface.messageTextStyle(
                    context,
                    choice.style,
                    customStyle: choice.customStyle,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Groups the styles by the plan that includes them.
class _TierSectionHeader extends StatelessWidget {
  const _TierSectionHeader({
    required this.tier,
    required this.unlocked,
    required this.onUnlock,
  });

  final PremiumTier tier;
  final bool unlocked;
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final accent = premiumTierAccent(tier);
    final name = PremiumPlanInfo.of(tier).name;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
      child: Row(
        children: [
          if (tier == PremiumTier.free)
            Icon(CupertinoIcons.chat_bubble_2_fill, size: 22, color: muted)
          else
            PremiumTierBadge(tier: tier, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tier == PremiumTier.free ? 'FREE' : name.toUpperCase(),
              style: AppTheme.bodySmall.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
                color: tier == PremiumTier.free ? muted : accent,
              ),
            ),
          ),
          if (unlocked)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  CupertinoIcons.checkmark_seal_fill,
                  size: 14,
                  color: tier == PremiumTier.free ? muted : accent,
                ),
                const SizedBox(width: 4),
                Text(
                  tier == PremiumTier.free ? 'Included' : 'Unlocked',
                  style: AppTheme.bodySmall.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: muted,
                  ),
                ),
              ],
            )
          else
            InkWell(
              key: ValueKey('bubble-style-unlock-${tier.name}'),
              onTap: onUnlock,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: LinearGradient(
                    colors: [accent, premiumTierAccentDeep(tier)],
                  ),
                ),
                child: Text(
                  'Unlock with $name',
                  style: AppTheme.bodySmall.copyWith(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The plan name beside a locked style.
class _UnlockChip extends StatelessWidget {
  const _UnlockChip({required this.tier});

  final PremiumTier tier;

  @override
  Widget build(BuildContext context) {
    final accent = premiumTierAccent(tier);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(CupertinoIcons.lock_fill, size: 11, color: accent),
          const SizedBox(width: 4),
          Text(
            PremiumPlanInfo.of(tier).name,
            style: AppTheme.bodySmall.copyWith(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}
