import SwiftUI
import WidgetKit

private struct BudgetAIWidgetView: View {
  let entry: BudgetTimelineEntry
  @Environment(\.colorScheme) private var colorScheme

  private var month: MonthSummary { entry.snapshot.summary(offset: 0) }

  private var primary: Color { colorScheme == .dark ? .white : .black }
  private var secondary: Color { primary.opacity(0.62) }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      header
      summary
      recentEntries
    }
    .padding(16)
    .containerBackground(for: .widget) {
      Color(uiColor: .systemBackground)
    }
  }

  private var header: some View {
    HStack(spacing: 10) {
      BudgetMarkView(palette: WidgetPalette(colorScheme: colorScheme))
        .frame(width: 42, height: 42)
      Text("Budget AI")
        .font(.custom("Boldonse", size: 12))
        .foregroundStyle(primary)
      Spacer()
      Text(entry.snapshot.now.formatted(.dateTime.month(.wide)))
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(primary)
    }
  }

  private var summary: some View {
    HStack(spacing: 16) {
      VStack(alignment: .leading, spacing: 5) {
        Text("Expenses this month")
          .font(.system(size: 9))
          .foregroundStyle(secondary)
        Text(format(month.expense))
          .font(.custom("Boldonse", size: 20))
          .minimumScaleFactor(0.65)
          .lineLimit(1)
          .foregroundStyle(primary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Rectangle()
        .fill(primary.opacity(0.09))
        .frame(width: 1)

      HStack(spacing: 18) {
        metric("Income", value: format(month.income), color: .green)
        metric("Entries", value: "\(month.expenseCount + month.incomeCount)", color: primary.opacity(0.35))
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func metric(_ label: String, value: String, color: Color) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 4) {
        Circle().fill(color).frame(width: 5, height: 5)
        Text(label)
      }
      .font(.system(size: 9))
      .foregroundStyle(secondary)
      Text(value)
        .font(.system(size: 13))
        .minimumScaleFactor(0.65)
        .lineLimit(1)
        .foregroundStyle(primary)
    }
  }

  private var recentEntries: some View {
    let recent = entry.snapshot.recentExpenses(limit: 2)
    return VStack(spacing: 2) {
      if recent.isEmpty {
        recentEntry(description: "No entries yet", amount: 0, type: "expense")
      }
      ForEach(recent, id: \.id) { expense in
        recentEntry(
          description: expense.description.isEmpty ? expense.category : expense.description,
          amount: expense.amount,
          type: "expense"
        )
      }
    }
  }

  private func recentEntry(
    description: String,
    amount: Double,
    type: String
  ) -> some View {
    HStack(spacing: 6) {
      Text(description)
        .font(.system(size: 10))
        .lineLimit(1)
        .foregroundStyle(primary)
      Spacer(minLength: 4)
      if amount > 0 {
        Text(format(amount, signed: true, isIncome: type == "income"))
          .font(.system(size: 10))
          .lineLimit(1)
          .foregroundStyle(type == "income" ? .green : .red)
      }
    }
  }

  private func format(
    _ amount: Double,
    signed: Bool = false,
    isIncome: Bool = true
  ) -> String {
    let number = NumberFormatter()
    number.numberStyle = .decimal
    number.maximumFractionDigits = amount.rounded() == amount ? 0 : 2
    let sign = signed && amount > 0 ? (isIncome ? "+" : "−") : ""
    let value = number.string(from: NSNumber(value: amount)) ?? String(amount)
    let currency = entry.snapshot.currency
    if ["$", "€", "£", "₹", "¥"].contains(currency) {
      return "\(sign)\(currency)\(value)"
    }
    return "\(sign)\(value) \(currency)"
  }
}

@main
struct BudgetAIWidgets: WidgetBundle {
  var body: some Widget {
    BudgetAIWidget()
    ExpenseTotalWidget()
    IncomeTotalWidget()
    MonthBalanceWidget()
    RecentExpensesWidget()
    TodayExpensesWidget()
    MonthComparisonWidget()
  }
}

struct BudgetAIWidget: Widget {
  let kind = "BudgetAIWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: BudgetSnapshotProvider(kind: kind)) { entry in
      BudgetAIWidgetView(entry: entry)
    }
    .configurationDisplayName("Budget AI")
    .description("This month's expenses and income with your two newest expenses.")
    .supportedFamilies([.systemMedium])
    .contentMarginsDisabled()
  }
}
