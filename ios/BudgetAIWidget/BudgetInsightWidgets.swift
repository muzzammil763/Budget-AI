import SwiftUI
import WidgetKit

// MARK: - Top categories

private struct TopCategoriesView: View {
  let entry: BudgetTimelineEntry
  @Environment(\.colorScheme) private var colorScheme

  private let maxRows = 4

  var body: some View {
    let palette = WidgetPalette(colorScheme: colorScheme)
    let month = entry.snapshot.monthStart(offset: entry.monthOffset)
    let categories = entry.snapshot.categories(offset: entry.monthOffset)
    let total = categories.reduce(0) { $0 + $1.amount }
    let largest = categories.first?.amount ?? 1

    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 8) {
        BudgetMarkView(palette: palette)
          .frame(width: 22, height: 22)
        Text("Top categories")
          .font(WidgetFont.body(14).weight(.semibold))
          .foregroundStyle(palette.primary)
        Spacer(minLength: 4)
        MonthSwitcher(kind: TopCategoriesWidget.kind, entry: entry, palette: palette)
      }
      .padding(.bottom, 8)

      if categories.isEmpty {
        VStack(spacing: 6) {
          Image(systemName: "chart.bar")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(palette.primary.opacity(0.25))
          Text("No expenses this month")
            .font(WidgetFont.body(12).weight(.medium))
            .foregroundStyle(palette.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        VStack(spacing: 0) {
          ForEach(Array(categories.prefix(maxRows).enumerated()), id: \.offset) { _, category in
            row(
              name: category.name,
              amount: category.amount,
              share: category.amount / max(total, 1),
              fraction: category.amount / max(largest, 1),
              palette: palette
            )
            .frame(maxHeight: .infinity)
          }
        }
      }
    }
    .budgetWidgetSurface(padding: 13)
    .widgetURL(WidgetLink.insights(month: month))
  }

  private func row(
    name: String,
    amount: Double,
    share: Double,
    fraction: Double,
    palette: WidgetPalette
  ) -> some View {
    VStack(spacing: 3) {
      HStack(spacing: 6) {
        Text(name)
          .font(WidgetFont.body(12).weight(.medium))
          .foregroundStyle(palette.primary)
          .lineLimit(1)
        Spacer(minLength: 4)
        Text(WidgetFormat.amount(amount, currency: entry.snapshot.currency))
          .font(WidgetFont.body(12).weight(.semibold))
          .foregroundStyle(palette.primary)
          .lineLimit(1)
        Text(share.formatted(.percent.precision(.fractionLength(0))))
          .font(WidgetFont.body(10).weight(.medium))
          .foregroundStyle(palette.secondary)
          .frame(width: 30, alignment: .trailing)
      }
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule().fill(palette.hairline)
          Capsule()
            .fill(palette.expense)
            .frame(width: max(4, proxy.size.width * fraction))
        }
      }
      .frame(height: 4)
    }
  }
}

struct TopCategoriesWidget: Widget {
  static let kind = "BudgetAITopCategoriesWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(
      kind: Self.kind,
      provider: BudgetSnapshotProvider(kind: Self.kind)
    ) { entry in
      TopCategoriesView(entry: entry)
    }
    .configurationDisplayName("Top Categories")
    .description("Where this month's money went. Use ‹ › to see other months.")
    .supportedFamilies([.systemMedium])
    .contentMarginsDisabled()
  }
}

// MARK: - Lock Screen

private struct LockScreenView: View {
  let entry: BudgetTimelineEntry
  @Environment(\.widgetFamily) private var family

  var body: some View {
    let snapshot = entry.snapshot
    let current = snapshot.summary(offset: 0)
    switch family {
    case .accessoryCircular:
      circular(current: current, previous: snapshot.summary(offset: -1))
    case .accessoryRectangular:
      rectangular(current: current)
    default:
      inline
    }
  }

  /// This month's spending; the ring fills against last month's total.
  private func circular(current: MonthSummary, previous: MonthSummary) -> some View {
    let limit = max(previous.expense, current.expense, 1)
    return Gauge(value: current.expense, in: 0...limit) {
      Text("Spent")
    } currentValueLabel: {
      Text(compact(current.expense))
        .font(.system(size: 13, weight: .semibold))
        .minimumScaleFactor(0.6)
    }
    .gaugeStyle(.accessoryCircularCapacity)
    .widgetAccentable()
    .containerBackground(for: .widget) { AccessoryWidgetBackground() }
    .widgetURL(WidgetLink.finances())
  }

  private func rectangular(current: MonthSummary) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(current.month.formatted(.dateTime.month(.wide)))
        .font(.system(size: 13, weight: .bold))
        .widgetAccentable()
      Label {
        Text(WidgetFormat.amount(current.expense, currency: entry.snapshot.currency))
      } icon: {
        Image(systemName: "arrow.up.right")
      }
      .font(.system(size: 13, weight: .medium))
      Label {
        Text(WidgetFormat.amount(current.income, currency: entry.snapshot.currency))
      } icon: {
        Image(systemName: "arrow.down.left")
      }
      .font(.system(size: 13, weight: .medium))
      .foregroundStyle(.secondary)
    }
    .lineLimit(1)
    .minimumScaleFactor(0.7)
    .frame(maxWidth: .infinity, alignment: .leading)
    .containerBackground(for: .widget) { Color.clear }
    .widgetURL(WidgetLink.finances())
  }

  private var inline: some View {
    let today = entry.snapshot.todayExpenses.reduce(0) { $0 + $1.amount }
    return Text("Today \(WidgetFormat.amount(today, currency: entry.snapshot.currency)) spent")
      .containerBackground(for: .widget) { Color.clear }
      .widgetURL(WidgetLink.finances())
  }

  /// Short amounts for the small ring, e.g. 42.5K or 1.2M.
  private func compact(_ value: Double) -> String {
    value.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
  }
}

struct BudgetLockScreenWidget: Widget {
  static let kind = "BudgetAILockScreenWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(
      kind: Self.kind,
      provider: BudgetSnapshotProvider(kind: Self.kind)
    ) { entry in
      LockScreenView(entry: entry)
    }
    .configurationDisplayName("Budget AI")
    .description("This month's spending, income, or today's total on the Lock Screen.")
    .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
  }
}
