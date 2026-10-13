import SwiftUI
import WidgetKit

/// The original wide widget reads the precomputed keys Flutter writes.
private enum WideWidgetStore {
  static func entry(date: Date = Date()) -> BudgetEntry {
    let defaults = WidgetStore.defaults
    return BudgetEntry(
      date: date,
      expense: defaults?.double(forKey: WidgetStore.expenseKey) ?? 0,
      income: defaults?.double(forKey: WidgetStore.incomeKey) ?? 0,
      latestDescription: defaults?.string(forKey: WidgetStore.latestDescriptionKey) ?? "No entries yet",
      latestAmount: defaults?.double(forKey: WidgetStore.latestAmountKey) ?? 0,
      latestType: defaults?.string(forKey: WidgetStore.latestTypeKey) ?? "expense",
      previousDescription: defaults?.string(forKey: WidgetStore.previousDescriptionKey) ?? "",
      previousAmount: defaults?.double(forKey: WidgetStore.previousAmountKey) ?? 0,
      previousType: defaults?.string(forKey: WidgetStore.previousTypeKey) ?? "expense",
      currency: WidgetStore.currency
    )
  }
}

struct BudgetEntry: TimelineEntry {
  let date: Date
  let expense: Double
  let income: Double
  let latestDescription: String
  let latestAmount: Double
  let latestType: String
  let previousDescription: String
  let previousAmount: Double
  let previousType: String
  let currency: String

  var balance: Double { income - expense }
}

struct BudgetProvider: TimelineProvider {
  func placeholder(in context: Context) -> BudgetEntry {
    BudgetEntry(
      date: Date(),
      expense: 42_500,
      income: 90_000,
      latestDescription: "Groceries",
      latestAmount: 2_400,
      latestType: "expense",
      previousDescription: "Salary",
      previousAmount: 90_000,
      previousType: "income",
      currency: "Rs"
    )
  }

  func getSnapshot(
    in context: Context,
    completion: @escaping (BudgetEntry) -> Void
  ) {
    completion(WideWidgetStore.entry())
  }

  func getTimeline(
    in context: Context,
    completion: @escaping (Timeline<BudgetEntry>) -> Void
  ) {
    let entry = WideWidgetStore.entry()
    let refresh = Calendar.current.date(byAdding: .minute, value: 30, to: entry.date)!
    completion(Timeline(entries: [entry], policy: .after(refresh)))
  }
}

private struct BudgetAIWidgetView: View {
  let entry: BudgetEntry
  @Environment(\.colorScheme) private var colorScheme

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
      Text(entry.date.formatted(.dateTime.month(.wide)))
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(primary)
    }
  }

  private var summary: some View {
    HStack(spacing: 16) {
      VStack(alignment: .leading, spacing: 5) {
        Text("Total expenses")
          .font(.system(size: 9))
          .foregroundStyle(secondary)
        Text(format(entry.expense))
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
        metric("Spent", value: entry.expense, color: .red)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func metric(_ label: String, value: Double, color: Color) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 4) {
        Circle().fill(color).frame(width: 5, height: 5)
        Text(label)
      }
      .font(.system(size: 9))
      .foregroundStyle(secondary)
      Text(format(value))
        .font(.system(size: 13))
        .minimumScaleFactor(0.65)
        .lineLimit(1)
        .foregroundStyle(primary)
    }
  }

  private var recentEntries: some View {
    VStack(spacing: 2) {
      recentEntry(
        description: entry.latestDescription,
        amount: entry.latestAmount,
        type: entry.latestType
      )
      if entry.previousAmount > 0 {
        recentEntry(
          description: entry.previousDescription,
          amount: entry.previousAmount,
          type: entry.previousType
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
    if ["$", "€", "£", "₹", "¥"].contains(entry.currency) {
      return "\(sign)\(entry.currency)\(value)"
    }
    return "\(sign)\(value) \(entry.currency)"
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
    StaticConfiguration(kind: kind, provider: BudgetProvider()) { entry in
      BudgetAIWidgetView(entry: entry)
    }
    .configurationDisplayName("Budget AI")
    .description("See your monthly spending and two newest expenses.")
    .supportedFamilies([.systemMedium])
    .contentMarginsDisabled()
  }
}
