/// Home and Lock Screen widget sizes, in the phone's widget grid.
enum HomeWidgetSize {
  small('Small', '2 × 2'),
  medium('Medium', '4 × 2'),
  large('Large', '4 × 4'),
  lockScreen('Lock Screen', 'iPhone');

  const HomeWidgetSize(this.label, this.cells);

  final String label;
  final String cells;
}

/// One native widget the app ships, as shown in the Budget Hub gallery.
class HomeWidgetDefinition {
  const HomeWidgetDefinition({
    required this.id,
    required this.title,
    required this.description,
    required this.size,
    required this.iOSKind,
    this.androidProvider,
  });

  final String id;
  final String title;
  final String description;
  final HomeWidgetSize size;
  final String iOSKind;

  /// The `AppWidgetProvider` class in `BudgetAIWidgetProvider.kt`; null for
  /// widgets Android does not offer.
  final String? androidProvider;

  static const androidPackage = 'com.budgetai.android';

  String? get qualifiedAndroidProvider =>
      androidProvider == null ? null : '$androidPackage.$androidProvider';

  bool get isOnAndroid => androidProvider != null;
}

/// Mirrors `BudgetHomeWidgetSync.iOSWidgetKinds` / `androidWidgetProviders`
/// and the native widget names and descriptions.
const homeWidgetCatalog = <HomeWidgetDefinition>[
  HomeWidgetDefinition(
    id: 'summary',
    title: 'Budget AI',
    description:
        "This month's expenses and income with your two newest expenses.",
    size: HomeWidgetSize.medium,
    iOSKind: 'BudgetAIWidget',
    androidProvider: 'BudgetAIWidgetProvider',
  ),
  HomeWidgetDefinition(
    id: 'expenses',
    title: 'Expenses',
    description: "This month's total expenses. Use ‹ › to see other months.",
    size: HomeWidgetSize.small,
    iOSKind: 'BudgetAIExpenseTotalWidget',
    androidProvider: 'ExpenseTotalWidgetProvider',
  ),
  HomeWidgetDefinition(
    id: 'income',
    title: 'Income',
    description: "This month's total income. Use ‹ › to see other months.",
    size: HomeWidgetSize.small,
    iOSKind: 'BudgetAIIncomeTotalWidget',
    androidProvider: 'IncomeTotalWidgetProvider',
  ),
  HomeWidgetDefinition(
    id: 'balance',
    title: 'Income & Expenses',
    description:
        'Income and expenses side by side. Use ‹ › to see other '
        'months.',
    size: HomeWidgetSize.small,
    iOSKind: 'BudgetAIMonthBalanceWidget',
    androidProvider: 'MonthBalanceWidgetProvider',
  ),
  HomeWidgetDefinition(
    id: 'comparison',
    title: 'This Month vs Last',
    description: "Compare this month's expenses with last month's.",
    size: HomeWidgetSize.small,
    iOSKind: 'BudgetAIMonthComparisonWidget',
    androidProvider: 'MonthComparisonWidgetProvider',
  ),
  HomeWidgetDefinition(
    id: 'recent',
    title: 'Recent Expenses',
    description: 'Your five most recent expenses.',
    size: HomeWidgetSize.medium,
    iOSKind: 'BudgetAIRecentExpensesWidget',
    androidProvider: 'RecentExpensesWidgetProvider',
  ),
  HomeWidgetDefinition(
    id: 'categories',
    title: 'Top Categories',
    description: "Where this month's money went. Use ‹ › to see other months.",
    size: HomeWidgetSize.medium,
    iOSKind: 'BudgetAITopCategoriesWidget',
    androidProvider: 'TopCategoriesWidgetProvider',
  ),
  HomeWidgetDefinition(
    id: 'today',
    title: "Today's Expenses",
    description: "Everything you spent today and the day's total.",
    size: HomeWidgetSize.large,
    iOSKind: 'BudgetAITodayExpensesWidget',
    androidProvider: 'TodayExpensesWidgetProvider',
  ),
  HomeWidgetDefinition(
    id: 'lock',
    title: 'Lock Screen',
    description:
        "This month's spending, income, or today's total on the "
        'Lock Screen.',
    size: HomeWidgetSize.lockScreen,
    iOSKind: 'BudgetAILockScreenWidget',
  ),
];
