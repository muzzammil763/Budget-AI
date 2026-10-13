import SwiftUI
import WidgetKit

// MARK: - Single total (expenses or income)

private struct MonthTotalView: View {
  let kind: String
  let isIncome: Bool
  let entry: BudgetTimelineEntry
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let palette = WidgetPalette(colorScheme: colorScheme)
    let summary = entry.snapshot.summary(offset: entry.monthOffset)
    let total = isIncome ? summary.income : summary.expense
    let count = isIncome ? summary.incomeCount : summary.expenseCount
    let color = isIncome ? palette.income : palette.expense

    VStack(spacing: 0) {
      HStack(alignment: .center) {
        FlowBadge(isIncome: isIncome, palette: palette, size: 24)
        Spacer(minLength: 4)
        MonthSwitcher(kind: kind, entry: entry, palette: palette)
      }
      Spacer(minLength: 6)
      Text(isIncome ? "Income" : "Expenses")
        .font(WidgetFont.body(12).weight(.medium))
        .foregroundStyle(palette.secondary)
      Text(WidgetFormat.amount(total, currency: entry.snapshot.currency))
        .font(WidgetFont.display(24))
        .foregroundStyle(palette.primary)
        .lineLimit(1)
        .minimumScaleFactor(0.4)
        .padding(.top, 6)
      Spacer(minLength: 6)
      Text(WidgetFormat.entries(count))
        .font(WidgetFont.body(11).weight(.medium))
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.12)))
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .budgetWidgetSurface()
    .widgetURL(WidgetLink.finances(month: summary.month))
  }
}

struct ExpenseTotalWidget: Widget {
  static let kind = "BudgetAIExpenseTotalWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(
      kind: Self.kind,
      provider: BudgetSnapshotProvider(kind: Self.kind)
    ) { entry in
      MonthTotalView(kind: Self.kind, isIncome: false, entry: entry)
    }
    .configurationDisplayName("Expenses")
    .description("This month's total expenses. Use ‹ › to see other months.")
    .supportedFamilies([.systemSmall])
    .contentMarginsDisabled()
  }
}

struct IncomeTotalWidget: Widget {
  static let kind = "BudgetAIIncomeTotalWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(
      kind: Self.kind,
      provider: BudgetSnapshotProvider(kind: Self.kind)
    ) { entry in
      MonthTotalView(kind: Self.kind, isIncome: true, entry: entry)
    }
    .configurationDisplayName("Income")
    .description("This month's total income. Use ‹ › to see other months.")
    .supportedFamilies([.systemSmall])
    .contentMarginsDisabled()
  }
}

// MARK: - Income and expenses together

private struct MonthBalanceView: View {
  let entry: BudgetTimelineEntry
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let palette = WidgetPalette(colorScheme: colorScheme)
    let summary = entry.snapshot.summary(offset: entry.monthOffset)
    let largest = max(summary.income, summary.expense, 1)

    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .center) {
        BudgetMarkView(palette: palette)
          .frame(width: 24, height: 24)
        Spacer(minLength: 4)
        MonthSwitcher(kind: MonthBalanceWidget.kind, entry: entry, palette: palette)
      }
      Spacer(minLength: 6)
      row(
        label: "Income",
        value: summary.income,
        fraction: summary.income / largest,
        color: palette.income,
        palette: palette
      )
      Spacer(minLength: 8)
      row(
        label: "Expenses",
        value: summary.expense,
        fraction: summary.expense / largest,
        color: palette.expense,
        palette: palette
      )
    }
    .budgetWidgetSurface()
    .widgetURL(WidgetLink.finances(month: summary.month))
  }

  private func row(
    label: String,
    value: Double,
    fraction: Double,
    color: Color,
    palette: WidgetPalette
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 5) {
        Circle().fill(color).frame(width: 6, height: 6)
        Text(label)
          .font(WidgetFont.body(11).weight(.medium))
          .foregroundStyle(palette.secondary)
      }
      Text(WidgetFormat.amount(value, currency: entry.snapshot.currency))
        .font(WidgetFont.display(15))
        .foregroundStyle(palette.primary)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule().fill(palette.hairline)
          Capsule()
            .fill(color)
            .frame(width: max(4, proxy.size.width * fraction))
        }
      }
      .frame(height: 4)
    }
  }
}

struct MonthBalanceWidget: Widget {
  static let kind = "BudgetAIMonthBalanceWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(
      kind: Self.kind,
      provider: BudgetSnapshotProvider(kind: Self.kind)
    ) { entry in
      MonthBalanceView(entry: entry)
    }
    .configurationDisplayName("Income & Expenses")
    .description("This month's income and expenses side by side. Use ‹ › to see other months.")
    .supportedFamilies([.systemSmall])
    .contentMarginsDisabled()
  }
}
