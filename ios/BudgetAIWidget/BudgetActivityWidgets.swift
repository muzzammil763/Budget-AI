import SwiftUI
import WidgetKit

/// One expense line: description, day or time, and a red amount.
private struct ExpenseRow: View {
  let entry: WidgetFinanceEntry
  let detail: String
  let currency: String
  let palette: WidgetPalette

  var body: some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 1) {
        Text(entry.description.isEmpty ? entry.category : entry.description)
          .font(WidgetFont.body(13).weight(.medium))
          .foregroundStyle(palette.primary)
          .lineLimit(1)
        Text(detail)
          .font(WidgetFont.body(10))
          .foregroundStyle(palette.secondary)
          .lineLimit(1)
      }
      Spacer(minLength: 6)
      Text(WidgetFormat.amount(entry.amount, currency: currency, sign: "−"))
        .font(WidgetFont.body(13).weight(.semibold))
        .foregroundStyle(palette.expense)
        .lineLimit(1)
        .layoutPriority(1)
    }
  }
}

private struct WidgetHeader: View {
  let title: String
  let trailing: String
  let palette: WidgetPalette

  var body: some View {
    HStack(spacing: 8) {
      BudgetMarkView(palette: palette)
        .frame(width: 24, height: 24)
      Text(title)
        .font(WidgetFont.body(14).weight(.semibold))
        .foregroundStyle(palette.primary)
      Spacer(minLength: 4)
      Text(trailing)
        .font(WidgetFont.body(11).weight(.medium))
        .foregroundStyle(palette.secondary)
        .lineLimit(1)
    }
  }
}

private struct EmptyMessage: View {
  let symbol: String
  let text: String
  let palette: WidgetPalette

  var body: some View {
    VStack(spacing: 6) {
      Image(systemName: symbol)
        .font(.system(size: 22, weight: .semibold))
        .foregroundStyle(palette.primary.opacity(0.25))
      Text(text)
        .font(WidgetFont.body(12).weight(.medium))
        .foregroundStyle(palette.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

// MARK: - Recent expenses

private struct RecentExpensesView: View {
  let entry: BudgetTimelineEntry
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let palette = WidgetPalette(colorScheme: colorScheme)
    let recent = entry.snapshot.recentExpenses(limit: 5)

    VStack(alignment: .leading, spacing: 0) {
      WidgetHeader(title: "Recent expenses", trailing: "Last 5", palette: palette)
        .padding(.bottom, 6)
      if recent.isEmpty {
        EmptyMessage(symbol: "tray", text: "No expenses yet", palette: palette)
      } else {
        VStack(spacing: 0) {
          ForEach(recent, id: \.id) { expense in
            compactRow(expense, palette: palette)
              .frame(maxHeight: .infinity)
          }
        }
      }
    }
    .budgetWidgetSurface(padding: 13)
  }

  /// Single-line rows so five fit in the medium height.
  private func compactRow(_ expense: WidgetFinanceEntry, palette: WidgetPalette) -> some View {
    HStack(spacing: 8) {
      Text(expense.description.isEmpty ? expense.category : expense.description)
        .font(WidgetFont.body(12).weight(.medium))
        .foregroundStyle(palette.primary)
        .lineLimit(1)
      Spacer(minLength: 4)
      Text(WidgetFormat.day(expense.date, relativeTo: entry.snapshot.now))
        .font(WidgetFont.body(10))
        .foregroundStyle(palette.secondary)
        .lineLimit(1)
      Text(WidgetFormat.amount(expense.amount, currency: entry.snapshot.currency, sign: "−"))
        .font(WidgetFont.body(12).weight(.semibold))
        .foregroundStyle(palette.expense)
        .lineLimit(1)
        .frame(minWidth: 64, alignment: .trailing)
    }
  }
}

struct RecentExpensesWidget: Widget {
  static let kind = "BudgetAIRecentExpensesWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(
      kind: Self.kind,
      provider: BudgetSnapshotProvider(kind: Self.kind)
    ) { entry in
      RecentExpensesView(entry: entry)
    }
    .configurationDisplayName("Recent Expenses")
    .description("Your five most recent expenses.")
    .supportedFamilies([.systemMedium])
    .contentMarginsDisabled()
  }
}

// MARK: - Today

private struct TodayExpensesView: View {
  let entry: BudgetTimelineEntry
  @Environment(\.colorScheme) private var colorScheme

  private let maxRows = 6

  var body: some View {
    let palette = WidgetPalette(colorScheme: colorScheme)
    let today = entry.snapshot.todayExpenses
    let total = today.reduce(0) { $0 + $1.amount }

    VStack(alignment: .leading, spacing: 0) {
      WidgetHeader(
        title: "Today",
        trailing: entry.snapshot.now.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)),
        palette: palette
      )
      VStack(alignment: .leading, spacing: 4) {
        Text("Spent today")
          .font(WidgetFont.body(12).weight(.medium))
          .foregroundStyle(palette.secondary)
        Text(WidgetFormat.amount(total, currency: entry.snapshot.currency))
          .font(WidgetFont.display(30))
          .foregroundStyle(palette.primary)
          .lineLimit(1)
          .minimumScaleFactor(0.45)
        Text(WidgetFormat.entries(today.count))
          .font(WidgetFont.body(11).weight(.medium))
          .foregroundStyle(palette.expense)
          .padding(.horizontal, 10)
          .padding(.vertical, 3)
          .background(Capsule().fill(palette.expense.opacity(0.12)))
          .padding(.top, 2)
      }
      .padding(.top, 14)
      .padding(.bottom, 12)

      Rectangle().fill(palette.hairline).frame(height: 1)

      if today.isEmpty {
        EmptyMessage(symbol: "checkmark.seal", text: "No expenses today", palette: palette)
      } else {
        VStack(spacing: 10) {
          ForEach(today.prefix(maxRows), id: \.id) { expense in
            ExpenseRow(
              entry: expense,
              detail: expense.hasTime
                ? expense.date.formatted(.dateTime.hour().minute())
                : expense.category,
              currency: entry.snapshot.currency,
              palette: palette
            )
          }
          if today.count > maxRows {
            Text("+\(today.count - maxRows) more")
              .font(WidgetFont.body(11).weight(.medium))
              .foregroundStyle(palette.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        .padding(.top, 12)
        Spacer(minLength: 0)
      }
    }
    .budgetWidgetSurface(padding: 16)
  }
}

struct TodayExpensesWidget: Widget {
  static let kind = "BudgetAITodayExpensesWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(
      kind: Self.kind,
      provider: BudgetSnapshotProvider(kind: Self.kind)
    ) { entry in
      TodayExpensesView(entry: entry)
    }
    .configurationDisplayName("Today's Expenses")
    .description("Everything you spent today and the day's total.")
    .supportedFamilies([.systemLarge])
    .contentMarginsDisabled()
  }
}

// MARK: - This month vs last month

private struct MonthComparisonView: View {
  let entry: BudgetTimelineEntry
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let palette = WidgetPalette(colorScheme: colorScheme)
    let current = entry.snapshot.summary(offset: 0)
    let previous = entry.snapshot.summary(offset: -1)
    let largest = max(current.expense, previous.expense, 1)

    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("vs last month")
          .font(WidgetFont.body(12).weight(.semibold))
          .foregroundStyle(palette.primary)
        Spacer(minLength: 4)
        changeBadge(current: current.expense, previous: previous.expense, palette: palette)
      }
      Spacer(minLength: 8)
      HStack(alignment: .bottom, spacing: 12) {
        bar(summary: previous, fraction: previous.expense / largest, isCurrent: false, palette: palette)
        bar(summary: current, fraction: current.expense / largest, isCurrent: true, palette: palette)
      }
    }
    .budgetWidgetSurface()
  }

  private func bar(
    summary: MonthSummary,
    fraction: Double,
    isCurrent: Bool,
    palette: WidgetPalette
  ) -> some View {
    VStack(spacing: 5) {
      Text(WidgetFormat.amount(summary.expense, currency: entry.snapshot.currency))
        .font(WidgetFont.body(11).weight(.semibold))
        .foregroundStyle(palette.primary)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
      GeometryReader { proxy in
        VStack {
          Spacer(minLength: 0)
          RoundedRectangle(cornerRadius: 7)
            .fill(isCurrent ? palette.primary : palette.primary.opacity(0.16))
            .frame(height: max(8, proxy.size.height * fraction))
        }
      }
      Text(WidgetFormat.month(summary.month, relativeTo: entry.snapshot.now))
        .font(WidgetFont.body(11).weight(.medium))
        .foregroundStyle(isCurrent ? palette.primary : palette.secondary)
    }
    .frame(maxWidth: .infinity)
  }

  @ViewBuilder
  private func changeBadge(current: Double, previous: Double, palette: WidgetPalette) -> some View {
    if previous > 0 {
      let change = (current - previous) / previous
      // Spending more than last month is the warning case.
      let color = change > 0 ? palette.expense : palette.income
      HStack(spacing: 2) {
        Image(systemName: change > 0 ? "arrow.up" : "arrow.down")
          .font(.system(size: 8, weight: .bold))
        Text(abs(change).formatted(.percent.precision(.fractionLength(0))))
          .font(WidgetFont.body(10).weight(.semibold))
      }
      .foregroundStyle(color)
      .padding(.horizontal, 6)
      .padding(.vertical, 3)
      .background(Capsule().fill(color.opacity(0.12)))
    }
  }
}

struct MonthComparisonWidget: Widget {
  static let kind = "BudgetAIMonthComparisonWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(
      kind: Self.kind,
      provider: BudgetSnapshotProvider(kind: Self.kind)
    ) { entry in
      MonthComparisonView(entry: entry)
    }
    .configurationDisplayName("This Month vs Last")
    .description("Compare this month's expenses with last month's.")
    .supportedFamilies([.systemSmall])
    .contentMarginsDisabled()
  }
}
