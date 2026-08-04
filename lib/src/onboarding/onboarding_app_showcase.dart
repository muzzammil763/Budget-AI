import 'dart:async';
import 'dart:math' as math;

import 'package:budget_ai/src/chat/chat_empty_state.dart';
import 'package:budget_ai/src/chat/chat_loading_widgets.dart';
import 'package:budget_ai/src/chat/chat_response_markdown.dart';
import 'package:budget_ai/src/helpers/app_button.dart';
import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/helpers/budget_mark.dart';
import 'package:budget_ai/src/helpers/pill_nav_bar.dart';
import 'package:budget_ai/src/helpers/responsive_info_sheet.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';

enum _DemoFlow { chat, finances, insights }

/// Three live miniature app flows used by the first onboarding page.
///
/// The content is deliberately hardcoded and isolated from app services. It
/// demonstrates the real interaction patterns without changing user data,
/// calling an AI provider, or depending on recorded video playback.
class OnboardingAppShowcase extends StatefulWidget {
  const OnboardingAppShowcase({super.key, this.showDynamicIsland = false});

  final bool showDynamicIsland;

  @override
  State<OnboardingAppShowcase> createState() => _OnboardingAppShowcaseState();
}

class _OnboardingAppShowcaseState extends State<OnboardingAppShowcase> {
  static const _demoFrameCount = 360;
  static const _demoFrameInterval = Duration(microseconds: 33333);

  final ValueNotifier<double> _demoProgress = ValueNotifier(0);
  Timer? _demoTimer;

  int _front = 0;
  int _left = 1;
  int _right = 2;

  @override
  void initState() {
    super.initState();
    // The previews are deliberately capped at 30 FPS. Rebuilding three dense
    // miniature app screens at the device refresh rate (often 120 Hz on iOS)
    // costs considerably more while looking effectively identical at this
    // size.
    _demoTimer = Timer.periodic(_demoFrameInterval, (timer) {
      _demoProgress.value = (timer.tick % _demoFrameCount) / _demoFrameCount;
    });
  }

  @override
  void dispose() {
    _demoTimer?.cancel();
    _demoProgress.dispose();
    super.dispose();
  }

  void _bringToFront(int item) {
    if (item == _front) return;
    HapticFeedback.lightImpact();
    setState(() {
      if (item == _left) {
        _left = _front;
      } else {
        _right = _front;
      }
      _front = item;
    });
  }

  @override
  Widget build(BuildContext context) {
    final height = (MediaQuery.sizeOf(context).height * 0.36).clamp(
      215.0,
      380.0,
    );
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const phoneAspect = 180 / 390;
          final areaHeight = constraints.maxHeight;
          var cardHeight = areaHeight * 0.98;
          var cardWidth = cardHeight * phoneAspect;
          final maxWidth = constraints.maxWidth * 0.36;
          if (cardWidth > maxWidth) {
            cardWidth = maxWidth;
            cardHeight = cardWidth / phoneAspect;
          }
          final sideShift = cardWidth * 0.85;
          return Stack(
            alignment: Alignment.center,
            children: [
              _buildCard(_left, cardWidth, cardHeight, -sideShift, areaHeight),
              _buildCard(_right, cardWidth, cardHeight, sideShift, areaHeight),
              _buildCard(_front, cardWidth, cardHeight, 0, areaHeight),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCard(
    int item,
    double width,
    double height,
    double dx,
    double areaHeight,
  ) {
    final theme = Theme.of(context);
    final isFront = item == _front;
    final rotation = isFront ? 0.0 : (dx < 0 ? -0.22 : 0.22);
    final scale = isFront ? 1.0 : 0.8;
    final dy = isFront ? 0.0 : areaHeight * 0.05;
    final bezel = width * 0.012;
    final frameColor = theme.brightness == Brightness.dark
        ? Colors.white
        : Colors.black;

    return AnimatedContainer(
      key: ValueKey(item),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeInOutCubic,
      transformAlignment: Alignment.center,
      transform: Matrix4.identity()
        ..translateByDouble(dx, dy, 0, 1)
        ..rotateZ(rotation)
        ..scaleByDouble(scale, scale, scale, 1),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _bringToFront(item),
        child: Container(
          width: width + bezel * 2,
          height: height + bezel * 2,
          padding: EdgeInsets.all(bezel),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: frameColor,
            borderRadius: BorderRadius.circular(16 + bezel),
            border: Border.all(color: frameColor, width: 1.2),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              fit: StackFit.expand,
              children: [
                RepaintBoundary(
                  child: _MiniDemo(
                    flow: _DemoFlow.values[item],
                    progress: _demoProgress,
                  ),
                ),
                if (widget.showDynamicIsland)
                  Positioned(
                    top: width * 0.04,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        width: width * 0.3,
                        height: width * 0.085,
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(100),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniDemo extends StatelessWidget {
  const _MiniDemo({required this.flow, required this.progress});

  final _DemoFlow flow;
  final ValueListenable<double> progress;

  @override
  Widget build(BuildContext context) {
    final content = switch (flow) {
      _DemoFlow.chat => ValueListenableBuilder<double>(
        valueListenable: progress,
        // Keep the real empty state mounted as the progress value changes. It
        // has its own intro animation and prompt-card tree, so updating that
        // whole subtree from the showcase clock would be wasted work.
        child: ChatEmptyState(onPromptTap: (_) {}),
        builder: (context, value, emptyState) =>
            _ChatDemo(progress: value, emptyState: emptyState!),
      ),
      _DemoFlow.finances => ValueListenableBuilder<double>(
        valueListenable: progress,
        builder: (context, value, _) => _FinancesDemo(progress: value),
      ),
      _DemoFlow.insights => _InsightsDemo(progress: progress),
    };
    const designSize = Size(390, 844);
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: designSize.width,
        height: designSize.height,
        child: content,
      ),
    );
  }
}

double _interval(
  double value,
  double start,
  double end, {
  Curve curve = Curves.easeInOutCubic,
}) => curve.transform(((value - start) / (end - start)).clamp(0.0, 1.0));

double _window(
  double value,
  double enterStart,
  double enterEnd,
  double exitStart,
  double exitEnd,
) =>
    (_interval(value, enterStart, enterEnd) -
            _interval(value, exitStart, exitEnd))
        .clamp(0.0, 1.0);

class _ChatDemo extends StatelessWidget {
  const _ChatDemo({required this.progress, required this.emptyState});

  static const question = 'Build me a 50/30/20 budget';
  static const answer = '''### Your 50/30/20 budget

Based on a **\$5,000 monthly income**:

- **Needs — \$2,500**
  Housing, utilities, groceries, transport and minimum debt payments.

- **Wants — \$1,500**
  Dining out, entertainment, shopping, hobbies and subscriptions.

- **Savings — \$1,000**
  Emergency savings, investments and extra debt payments.

That gives you a weekly needs limit of about **\$577** and a wants limit of **\$346**.

Start by automating the \$1,000 savings transfer on payday, then track the other two buckets as you spend.

You’re ready to start budgeting.''';
  static const _answerChunkSize = 12;
  final double progress;
  final Widget emptyState;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final typing = _interval(progress, 0.14, 0.32, curve: Curves.linear);
    final submitted = _interval(progress, 0.33, 0.37);
    final streaming = _interval(progress, 0.42, 0.76, curve: Curves.linear);
    final reset = _interval(progress, 0.93, 1);
    final conversationOpacity = (submitted * (1 - reset)).clamp(0.0, 1.0);
    final emptyOpacity = ((1 - submitted) + reset).clamp(0.0, 1.0);
    final typedQuestion = question.substring(
      0,
      (question.length * typing).round(),
    );
    final rawAnswerLength = (answer.length * streaming).round();
    // Markdown parsing and layout is substantially heavier than plain text.
    // Reveal it in small visual chunks so the parser is not rerun for every
    // individual character.
    final answerLength = streaming >= 1
        ? answer.length
        : (rawAnswerLength ~/ _answerChunkSize) * _answerChunkSize;
    final typedAnswer = answer.substring(0, answerLength);
    final isWorking = progress >= 0.34 && progress < 0.79;
    final sendPress = math.sin(
      _interval(progress, 0.315, 0.34, curve: Curves.linear) * math.pi,
    );

    return ColoredBox(
      color: colors.surface,
      child: Stack(
        children: [
          Positioned.fill(
            child: Opacity(opacity: emptyOpacity, child: emptyState),
          ),
          Positioned.fill(
            child: Opacity(
              opacity: conversationOpacity,
              child: ListView(
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.only(top: 108, bottom: 112),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 12),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        constraints: const BoxConstraints(maxWidth: 320),
                        decoration: BoxDecoration(
                          color: colors.primary,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(4),
                            topRight: Radius.circular(16),
                            bottomLeft: Radius.circular(16),
                            bottomRight: Radius.circular(4),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 30,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Text(
                          question,
                          style: TextStyle(
                            color: colors.onPrimary,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (typedAnswer.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: ChatResponseMarkdown(
                        text: typedAnswer,
                        isStreaming: false,
                        onLinkTap: (_, _) async {},
                      ),
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 100,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    colors.surface,
                    colors.surface.withValues(alpha: 0.5),
                    colors.surface.withValues(alpha: 0),
                  ],
                  stops: const [0, 0.5, 1],
                ),
              ),
            ),
          ),
          const Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Row(
              children: [
                _ChatChromeButton(icon: CupertinoIcons.line_horizontal_3),
                Spacer(),
                _ChatChromeButton(icon: CupertinoIcons.settings),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Container(
                height: 64,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      colors.surface.withValues(alpha: 0),
                      colors.surface.withValues(alpha: 0.5),
                      colors.surface,
                    ],
                    stops: const [0, 0.5, 1],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 32,
            right: 32,
            bottom: 32,
            child: _ChatComposer(
              text: conversationOpacity > 0.5 ? '' : typedQuestion,
              isWorking: isWorking && reset < 0.5,
              sendPress: sendPress,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatChromeButton extends StatelessWidget {
  const _ChatChromeButton({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 56,
      height: 48,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: theme.brightness == Brightness.dark
              ? theme.colorScheme.onSurface.withValues(alpha: 0.25)
              : theme.colorScheme.onSurface.withValues(alpha: 0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Icon(icon, color: theme.colorScheme.onSurface, size: 28),
    );
  }
}

class _ChatComposer extends StatelessWidget {
  const _ChatComposer({
    required this.text,
    required this.isWorking,
    required this.sendPress,
  });

  final String text;
  final bool isWorking;
  final double sendPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return ChatWorkingComposerFrame(
      isWorking: isWorking,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: isWorking
                ? Colors.transparent
                : theme.brightness == Brightness.dark
                ? colors.outline.withValues(alpha: 0.2)
                : colors.outline.withValues(alpha: 0.06),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          child: isWorking
              ? Row(
                  key: const ValueKey('working'),
                  children: [
                    const SizedBox.square(
                      dimension: 44,
                      child: ChatBudgetLoadingIndicator(size: 44),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(child: ChatWorkingWord(fontSize: 18)),
                  ],
                )
              : Row(
                  key: const ValueKey('normal'),
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: Icon(
                        CupertinoIcons.plus,
                        size: 28,
                        color: colors.onSurface,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                text.isEmpty ? 'Ask Budget AI' : text,
                                maxLines: 1,
                                overflow: TextOverflow.clip,
                                style: TextStyle(
                                  color: text.isEmpty
                                      ? colors.onSurfaceVariant.withValues(
                                          alpha: 0.72,
                                        )
                                      : colors.onSurface,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            if (text.isNotEmpty)
                              Container(
                                width: 1.5,
                                height: 19,
                                margin: const EdgeInsets.only(left: 1),
                                color: colors.primary,
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Transform.scale(
                      scale: 1 - sendPress * 0.12,
                      child: Opacity(
                        opacity: text.isEmpty ? 0.65 : 1,
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: text.isEmpty
                                ? colors.primary.withValues(alpha: 0.16)
                                : colors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            CupertinoIcons.arrow_up,
                            color: text.isEmpty
                                ? colors.primary.withValues(alpha: 0.56)
                                : colors.onPrimary,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _FinancesDemo extends StatelessWidget {
  const _FinancesDemo({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final expenseSheet = _window(progress, 0.06, 0.11, 0.23, 0.28);
    final incomeSheet = _window(progress, 0.31, 0.36, 0.48, 0.53);
    final deleteSwipe = _interval(progress, 0.57, 0.64);
    final deleteSheet = _window(progress, 0.64, 0.69, 0.81, 0.85);
    final deleted = _interval(progress, 0.85, 0.9);

    return ColoredBox(
      color: colors.surface,
      child: Stack(
        children: [
          Column(
            children: [
              const _ScreenAppBar(
                title: 'Finances',
                trailing: BudgetMarkIcon(size: 28),
              ),
              PillNavBar(
                items: const ['Overall', 'Jul 2026', 'Jun 2026'],
                selectedIndex: 1,
                onSelected: (_) {},
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ClipRect(
                  child: Column(
                    children: [
                      const _FinanceBalanceCard(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 112),
                        child: Column(
                          children: [
                            const _FinanceDayHeader(
                              day: 'TODAY',
                              expense: '-\$128.60',
                            ),
                            ClipRect(
                              child: Align(
                                alignment: Alignment.topCenter,
                                heightFactor: 1 - deleted,
                                child: Opacity(
                                  opacity: 1 - deleted,
                                  child: Stack(
                                    alignment: Alignment.centerRight,
                                    children: [
                                      Positioned.fill(
                                        child: Align(
                                          alignment: Alignment.centerRight,
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                              right: 18,
                                              bottom: 8,
                                            ),
                                            child: Icon(
                                              CupertinoIcons.trash,
                                              color: colors.error,
                                            ),
                                          ),
                                        ),
                                      ),
                                      Transform.translate(
                                        offset: Offset(-390 * deleteSwipe, 0),
                                        child: const _FinanceEntryPill(
                                          letter: 'G',
                                          title: 'Weekly groceries',
                                          subtitle: 'Groceries · 10:42 AM',
                                          amount: '-\$86.40',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const _FinanceEntryPill(
                              letter: 'T',
                              title: 'Taxi to work',
                              subtitle: 'Transport · 8:15 AM',
                              amount: '-\$42.20',
                            ),
                            const SizedBox(height: 4),
                            const _FinanceDayHeader(
                              day: 'YESTERDAY',
                              income: '+\$5,000',
                              expense: '-\$1,356',
                            ),
                            const _FinanceEntryPill(
                              letter: 'S',
                              title: 'Monthly salary',
                              subtitle: 'Salary · Income',
                              amount: '+\$5,000',
                              income: true,
                            ),
                            const _FinanceEntryPill(
                              letter: 'R',
                              title: 'Apartment rent',
                              subtitle: 'Housing',
                              amount: '-\$1,200',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            left: 32,
            right: 32,
            bottom: 32,
            child: _FinanceSearchBar(colors: colors),
          ),
          if (expenseSheet > 0)
            _FinanceDetailsSheet(
              progress: expenseSheet,
              isIncome: false,
              amount: '-\$86.40',
              title: 'Weekly groceries',
              category: 'Groceries',
            ),
          if (incomeSheet > 0)
            _FinanceDetailsSheet(
              progress: incomeSheet,
              isIncome: true,
              amount: '+\$5,000',
              title: 'Monthly salary',
              category: 'Salary',
            ),
          if (deleteSheet > 0) _DeleteFinanceSheet(progress: deleteSheet),
        ],
      ),
    );
  }
}

class _FinanceSearchBar extends StatelessWidget {
  const _FinanceSearchBar({required this.colors});

  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: colors.outline.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              CupertinoIcons.search,
              size: 24,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Text(
              'Search finances',
              style: TextStyle(
                color: colors.onSurfaceVariant.withValues(alpha: 0.72),
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(width: 44),
        ],
      ),
    );
  }
}

class _FinanceDetailsSheet extends StatelessWidget {
  const _FinanceDetailsSheet({
    required this.progress,
    required this.isIncome,
    required this.amount,
    required this.title,
    required this.category,
  });

  final double progress;
  final bool isIncome;
  final String amount;
  final String title;
  final String category;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = isIncome ? Colors.green : theme.colorScheme.error;
    return _AnimatedPreviewSheet(
      progress: progress,
      travel: 700,
      child: ResponsiveInfoSheet(
        title: isIncome ? 'Income Details' : 'Expense Details',
        headerIcon: Icon(
          isIncome
              ? CupertinoIcons.arrow_down_left
              : CupertinoIcons.arrow_up_right,
          size: 32,
          color: AppTheme.readableOn(accent),
        ),
        gradientColors: [accent, accent.withValues(alpha: 0.78)],
        contentWidgets: [
          Center(
            child: Text(
              amount,
              textAlign: TextAlign.center,
              style: AppTheme.headingLarge.copyWith(
                color: accent,
                fontSize: 28,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: AppTheme.headingSmall.copyWith(
                color: theme.colorScheme.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _SheetDetailRow(
            icon: CupertinoIcons.tag,
            label: 'Category',
            value: category,
          ),
          const _SheetDetailRow(
            icon: CupertinoIcons.calendar,
            label: 'Date',
            value: '17 Jul 2026',
          ),
          const _SheetDetailRow(
            icon: CupertinoIcons.time,
            label: 'Logged',
            value: '17 Jul · 10:42 AM',
          ),
          _SheetDetailRow(
            icon: isIncome
                ? CupertinoIcons.arrow_down_circle
                : CupertinoIcons.arrow_up_circle,
            label: 'Type',
            value: isIncome ? 'Income' : 'Expense',
          ),
        ],
      ),
    );
  }
}

class _AnimatedPreviewSheet extends StatelessWidget {
  const _AnimatedPreviewSheet({
    required this.progress,
    required this.travel,
    required this.child,
  });

  final double progress;
  final double travel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Theme.of(
          context,
        ).colorScheme.scrim.withValues(alpha: progress * 0.38),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Transform.translate(
            offset: Offset(0, travel * (1 - progress)),
            child: Opacity(
              opacity: progress,
              child: IgnorePointer(child: child),
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetDetailRow extends StatelessWidget {
  const _SheetDetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(icon, color: colors.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: colors.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: colors.onSurface,
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeleteFinanceSheet extends StatelessWidget {
  const _DeleteFinanceSheet({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = theme.colorScheme.error;
    return _AnimatedPreviewSheet(
      progress: progress,
      travel: 520,
      child: ResponsiveInfoSheet(
        title: 'Delete Finance Entry?',
        headerIcon: Icon(
          CupertinoIcons.trash,
          size: 30,
          color: AppTheme.readableOn(error),
        ),
        gradientColors: [error, error.withValues(alpha: 0.78)],
        contentWidgets: [
          Text(
            'Delete "Weekly groceries" (\$86.40)?',
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
                  onPressed: () {},
                ),
              ),
              Expanded(
                child: AppButton(text: 'Delete', isRed: true, onPressed: () {}),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScreenAppBar extends StatelessWidget {
  const _ScreenAppBar({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Icon(
              Icons.arrow_back_ios_new,
              size: 20,
              color: colors.onSurface,
            ),
          ),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: colors.onSurface,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(width: 56, child: Center(child: trailing)),
        ],
      ),
    );
  }
}

class _FinanceBalanceCard extends StatelessWidget {
  const _FinanceBalanceCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final onCard = AppTheme.readableOn(colors.primary);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primary,
            Color.lerp(colors.primary, AppTheme.highlight, 0.28)!,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CURRENT BALANCE',
            style: TextStyle(
              color: onCard.withValues(alpha: 0.68),
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '\$2,840.00',
            style: AppTheme.headingLarge.copyWith(
              color: onCard,
              fontSize: 20,
              fontWeight: FontWeight.w600,
              fontFamily: 'Boldonse',
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _BalanceMetric(
                  icon: CupertinoIcons.arrow_down_left,
                  label: 'INCOME',
                  amount: '\$5,000',
                  amountColor: Colors.green,
                  onCard: onCard,
                ),
              ),
              Container(
                width: 1,
                height: 38,
                margin: const EdgeInsets.symmetric(horizontal: 14),
                color: onCard.withValues(alpha: 0.2),
              ),
              Expanded(
                child: _BalanceMetric(
                  icon: CupertinoIcons.arrow_up_right,
                  label: 'EXPENSE',
                  amount: '\$2,160',
                  amountColor: Colors.red,
                  onCard: onCard,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BalanceMetric extends StatelessWidget {
  const _BalanceMetric({
    required this.icon,
    required this.label,
    required this.amount,
    required this.amountColor,
    required this.onCard,
  });

  final IconData icon;
  final String label;
  final String amount;
  final Color amountColor;
  final Color onCard;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: onCard, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: onCard,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                amount,
                style: TextStyle(
                  color: amountColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FinanceDayHeader extends StatelessWidget {
  const _FinanceDayHeader({
    required this.day,
    this.income,
    required this.expense,
  });

  final String day;
  final String? income;
  final String expense;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 8),
      child: Row(
        children: [
          Text(
            day,
            style: TextStyle(
              color: colors.primary,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 1,
              color: colors.onSurface.withValues(alpha: 0.1),
            ),
          ),
          if (income != null) ...[
            const SizedBox(width: 12),
            Text(
              income!,
              style: const TextStyle(
                color: Colors.green,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
          const SizedBox(width: 12),
          Text(
            expense,
            style: const TextStyle(
              color: Colors.red,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _FinanceEntryPill extends StatelessWidget {
  const _FinanceEntryPill({
    required this.letter,
    required this.title,
    required this.subtitle,
    required this.amount,
    this.income = false,
  });

  final String letter;
  final String title;
  final String subtitle;
  final String amount;
  final bool income;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: colors.onSurface.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(100),
            ),
            child: Text(
              letter,
              style: TextStyle(
                color: colors.onPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  style: TextStyle(
                    color: colors.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            amount,
            style: TextStyle(
              color: income ? Colors.green : Colors.red,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightsDemo extends StatefulWidget {
  const _InsightsDemo({required this.progress});

  final ValueListenable<double> progress;

  @override
  State<_InsightsDemo> createState() => _InsightsDemoState();
}

class _InsightsDemoState extends State<_InsightsDemo> {
  final ScrollController _scrollController = ScrollController();
  bool _scrollScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.progress.addListener(_handleProgress);
    _scheduleScroll();
  }

  @override
  void didUpdateWidget(covariant _InsightsDemo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.progress != widget.progress) {
      oldWidget.progress.removeListener(_handleProgress);
      widget.progress.addListener(_handleProgress);
      _scheduleScroll();
    }
  }

  @override
  void dispose() {
    widget.progress.removeListener(_handleProgress);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleProgress() => _scheduleScroll();

  double get _scrollFraction {
    final value = widget.progress.value;
    if (value < 0.08) return 0;
    if (value < 0.62) return _interval(value, 0.08, 0.62);
    if (value < 0.78) return 1;
    return 1 - _interval(value, 0.78, 0.98);
  }

  void _scheduleScroll() {
    if (_scrollScheduled) return;
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (!mounted || !_scrollController.hasClients) return;
      final maxScroll = _scrollController.position.maxScrollExtent;
      final target = maxScroll * _scrollFraction;
      if ((_scrollController.offset - target).abs() < 1) return;
      _scrollController.jumpTo(target);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colors.surface,
      child: Column(
        children: [
          const _ScreenAppBar(title: 'Finance Insights'),
          PillNavBar(
            items: const ['Overall', 'Jul 2026', 'Jun 2026', 'May 2026'],
            selectedIndex: 0,
            onSelected: (_) {},
          ),
          Expanded(
            child: RepaintBoundary(
              child: ListView(
                controller: _scrollController,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.all(12),
                // This miniature report scrolls automatically after an initial
                // pause. Keep the complete report laid out so scrolling down
                // does not construct each chart/card as it enters the viewport.
                // The return trip was already smooth because those children
                // had been built by then.
                scrollCacheExtent: const ScrollCacheExtent.viewport(8),
                children: const [
                  _InsightsHeroCard(),
                  SizedBox(height: 12),
                  _IncomeExpenseCard(),
                  SizedBox(height: 12),
                  _InsightsMetricGrid(),
                  SizedBox(height: 12),
                  _MomentumCard(),
                  SizedBox(height: 12),
                  _SpendingHeatmapCard(),
                  SizedBox(height: 12),
                  _BudgetSignalsCard(),
                  SizedBox(height: 12),
                  _HighlightsCard(),
                  SizedBox(height: 12),
                  _CategoryBreakdownCard(),
                  SizedBox(height: 12),
                  _DailyTrendsCard(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightsHeroCard extends StatelessWidget {
  const _InsightsHeroCard();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final onCard = AppTheme.readableOn(colors.primary);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primary,
            Color.lerp(colors.primary, AppTheme.highlight, 0.28)!,
          ],
        ),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: colors.primary.withValues(alpha: 0.18),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: onCard.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(32),
                ),
                child: Icon(Icons.insights_rounded, color: onCard, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'From 01 Jan 2026 To Today',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: onCard.withValues(alpha: 0.72),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '\$4,862.60',
            style: AppTheme.headingLarge.copyWith(
              color: onCard,
              fontSize: 32,
              fontWeight: FontWeight.w500,
              fontFamily: 'Boldonse',
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Total spent until today',
            style: TextStyle(
              color: onCard.withValues(alpha: 0.72),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: const [
              Expanded(child: _HeroStat('28', 'Entries')),
              Expanded(child: _HeroStat('19', 'Active days')),
              Expanded(child: _HeroStat('\$174', 'Daily avg')),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat(this.value, this.label);

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final onCard = AppTheme.readableOn(Theme.of(context).colorScheme.primary);
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: onCard,
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: TextStyle(
            color: onCard.withValues(alpha: 0.62),
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

BoxDecoration _insightDecoration(ThemeData theme) => BoxDecoration(
  color: theme.colorScheme.surface,
  borderRadius: BorderRadius.circular(32),
  border: Border.all(color: theme.dividerColor.withValues(alpha: 0.18)),
  boxShadow: [
    BoxShadow(
      color: Colors.black.withValues(
        alpha: theme.brightness == Brightness.dark ? 0.16 : 0.05,
      ),
      blurRadius: 14,
      offset: const Offset(0, 6),
    ),
  ],
);

class _IncomeExpenseCard extends StatelessWidget {
  const _IncomeExpenseCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _insightDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _InsightTitle('INCOME VS EXPENSES'),
          const SizedBox(height: 12),
          Row(
            children: [
              const Expanded(
                child: _IncomeColumn(
                  label: 'THIS MONTH',
                  income: '+\$5,000',
                  expense: '-\$2,160',
                  net: '+\$2,840',
                ),
              ),
              Container(
                width: 1,
                height: 92,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                color: theme.dividerColor.withValues(alpha: 0.18),
              ),
              const Expanded(
                child: _IncomeColumn(
                  label: 'ALL TIME',
                  income: '+\$9,800',
                  expense: '-\$4,862',
                  net: '+\$4,937',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IncomeColumn extends StatelessWidget {
  const _IncomeColumn({
    required this.label,
    required this.income,
    required this.expense,
    required this.net,
  });

  final String label;
  final String income;
  final String expense;
  final String net;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: colors.onSurfaceVariant,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        _MoneyRow('Income', income, Colors.green),
        const SizedBox(height: 6),
        _MoneyRow('Expenses', expense, Colors.red),
        const SizedBox(height: 6),
        _MoneyRow('Net', net, Colors.green),
      ],
    );
  }
}

class _MoneyRow extends StatelessWidget {
  const _MoneyRow(this.label, this.value, this.color);

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 12.5,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _InsightsMetricGrid extends StatelessWidget {
  const _InsightsMetricGrid();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(
          child: _InsightMetric(Icons.today_rounded, 'Today', '\$128.60'),
        ),
        SizedBox(width: 8),
        Expanded(
          child: _InsightMetric(
            Icons.view_week_rounded,
            'This week',
            '\$486.40',
          ),
        ),
      ],
    );
  }
}

class _InsightMetric extends StatelessWidget {
  const _InsightMetric(this.icon, this.label, this.value);

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 98,
      padding: const EdgeInsets.all(16),
      decoration: _insightDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.primary, size: 20),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MomentumCard extends StatelessWidget {
  const _MomentumCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _insightDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _InsightTitle('MOMENTUM'),
          const SizedBox(height: 14),
          Row(
            children: const [
              Expanded(child: _CircularMetric('Month time', 0.55, '55%')),
              Expanded(child: _CircularMetric('Week share', 0.38, '38%')),
              Expanded(child: _CircularMetric('Active days', 0.68, '68%')),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'JUL VS PREVIOUS MONTH',
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: 0.72,
              minHeight: 8,
              color: theme.colorScheme.primary,
              backgroundColor: theme.colorScheme.primary.withValues(
                alpha: 0.12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CircularMetric extends StatelessWidget {
  const _CircularMetric(this.label, this.value, this.center);

  final String label;
  final double value;
  final String center;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        SizedBox(
          width: 74,
          height: 74,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 74,
                height: 74,
                child: CircularProgressIndicator(
                  value: value,
                  strokeWidth: 8,
                  strokeCap: StrokeCap.round,
                  color: colors.primary,
                  backgroundColor: colors.primary.withValues(alpha: 0.12),
                ),
              ),
              Text(
                center,
                style: TextStyle(
                  color: colors.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: colors.onSurfaceVariant,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _SpendingHeatmapCard extends StatelessWidget {
  const _SpendingHeatmapCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final empty = theme.colorScheme.surfaceContainerHighest.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.34 : 0.58,
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _insightDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: _InsightTitle('SPENDING ACTIVITY')),
              Text(
                'Last 12 months',
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Darker squares mean heavier spending days. Blank days mean nothing was tracked.',
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 11.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 24,
                child: Column(
                  children: const [
                    SizedBox(height: 15, child: Text('M')),
                    SizedBox(height: 15),
                    SizedBox(height: 15, child: Text('W')),
                    SizedBox(height: 15),
                    SizedBox(height: 15, child: Text('F')),
                    SizedBox(height: 30),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    for (var week = 0; week < 20; week++)
                      Expanded(
                        child: Column(
                          children: [
                            for (var day = 0; day < 7; day++)
                              Container(
                                height: 12,
                                margin: const EdgeInsets.only(
                                  right: 2,
                                  bottom: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: (week * 7 + day) % 5 == 0
                                      ? empty
                                      : primary.withValues(
                                          alpha:
                                              0.22 + ((week + day) % 4) * 0.19,
                                        ),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                'Less',
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
              const SizedBox(width: 6),
              for (var index = 0; index < 5; index++)
                Container(
                  width: 12,
                  height: 12,
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    color: index == 0
                        ? empty
                        : primary.withValues(alpha: 0.2 + index * 0.2),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              Text(
                'More',
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BudgetSignalsCard extends StatelessWidget {
  const _BudgetSignalsCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _insightDecoration(theme),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InsightTitle('BUDGET SIGNALS'),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _SignalTile(
                  Icons.show_chart_rounded,
                  'Projected month',
                  '\$3,780',
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: _SignalTile(
                  Icons.nights_stay_outlined,
                  'No-spend days',
                  '8/17',
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _SignalTile(Icons.category_outlined, 'Housing', '49%'),
              ),
              SizedBox(width: 8),
              Expanded(
                child: _SignalTile(
                  Icons.check_circle_outline_rounded,
                  'Tracking cadence',
                  '68%',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SignalTile extends StatelessWidget {
  const _SignalTile(this.icon, this.label, this.value);

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      height: 112,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: colors.primary.withValues(alpha: 0.13)),
        borderRadius: BorderRadius.circular(32),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colors.primary, size: 20),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: colors.onSurface,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _HighlightsCard extends StatelessWidget {
  const _HighlightsCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _insightDecoration(theme),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InsightTitle('HIGHLIGHTS'),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _HighlightTile(
                  CupertinoIcons.flame_fill,
                  'Most spent day',
                  '\$1,286',
                  '01 JUL 2026',
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: _HighlightTile(
                  Icons.stacked_line_chart_rounded,
                  'July peak',
                  '\$1,286',
                  '01 JUL 2026',
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _HighlightTile(
                  Icons.view_week_rounded,
                  'Most spent week',
                  '\$1,842',
                  'From 29 JUN 2026',
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: _HighlightTile(
                  CupertinoIcons.arrow_up_circle_fill,
                  'Largest expense',
                  '\$1,200',
                  'Apartment rent',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HighlightTile extends StatelessWidget {
  const _HighlightTile(this.icon, this.label, this.value, this.caption);

  final IconData icon;
  final String label;
  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      height: 126,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colors.primary, size: 20),
          const Spacer(),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: colors.onSurface,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 9),
          ),
        ],
      ),
    );
  }
}

class _CategoryBreakdownCard extends StatelessWidget {
  const _CategoryBreakdownCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _insightDecoration(theme),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InsightTitle('CATEGORY BREAKDOWN'),
          SizedBox(height: 14),
          _CategoryBar('Housing', '\$2,400 · 49%', 1),
          SizedBox(height: 12),
          _CategoryBar('Groceries', '\$860 · 18%', 0.36),
          SizedBox(height: 12),
          _CategoryBar('Transport', '\$585 · 12%', 0.24),
          SizedBox(height: 12),
          _CategoryBar('Subscriptions', '\$410 · 8%', 0.17),
          SizedBox(height: 12),
          _CategoryBar('Dining', '\$342 · 7%', 0.14),
          SizedBox(height: 12),
          _CategoryBar('Shopping', '\$265 · 5%', 0.11),
        ],
      ),
    );
  }
}

class _InsightTitle extends StatelessWidget {
  const _InsightTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: Theme.of(context).colorScheme.primary,
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 1,
      ),
    );
  }
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar(this.label, this.amount, this.value);

  final String label;
  final String amount;
  final double value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: colors.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              amount,
              style: TextStyle(
                color: colors.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 8,
            color: colors.primary,
            backgroundColor: colors.primary.withValues(alpha: 0.1),
          ),
        ),
      ],
    );
  }
}

class _DailyTrendsCard extends StatelessWidget {
  const _DailyTrendsCard();

  static const values = [0.24, 0.58, 0.36, 0.82, 0.44, 0.68, 0.31];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _insightDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: _InsightTitle('LAST 7 DAYS')),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.primary,
                ),
              ),
              const SizedBox(width: 5),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.outline.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 154,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var index = 0; index < values.length; index++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            height: 118 * values[index],
                            decoration: BoxDecoration(
                              color: colors.primary.withValues(
                                alpha: index == 3 ? 1 : 0.28,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][index],
                            style: TextStyle(
                              color: colors.onSurfaceVariant,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Swipe for last 30 days',
              style: TextStyle(
                color: colors.onSurfaceVariant,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
