import SwiftUI
import WidgetKit

private enum WidgetStore {
  static let appGroup = "group.com.muzamil.budget.ai"
  static let expenseKey = "budget_ai_widget_month_expense"
  static let incomeKey = "budget_ai_widget_month_income"
  static let latestDescriptionKey = "budget_ai_widget_latest_description"
  static let latestAmountKey = "budget_ai_widget_latest_amount"
  static let latestTypeKey = "budget_ai_widget_latest_type"
  static let currencyKey = "budget_ai_widget_currency"

  static func entry(date: Date = Date()) -> BudgetEntry {
    let defaults = UserDefaults(suiteName: appGroup)
    return BudgetEntry(
      date: date,
      expense: defaults?.double(forKey: expenseKey) ?? 0,
      income: defaults?.double(forKey: incomeKey) ?? 0,
      latestDescription: defaults?.string(forKey: latestDescriptionKey) ?? "No entries yet",
      latestAmount: defaults?.double(forKey: latestAmountKey) ?? 0,
      latestType: defaults?.string(forKey: latestTypeKey) ?? "expense",
      currency: defaults?.string(forKey: currencyKey) ?? "USD"
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
      currency: "Rs"
    )
  }

  func getSnapshot(
    in context: Context,
    completion: @escaping (BudgetEntry) -> Void
  ) {
    completion(WidgetStore.entry())
  }

  func getTimeline(
    in context: Context,
    completion: @escaping (Timeline<BudgetEntry>) -> Void
  ) {
    let entry = WidgetStore.entry()
    let refresh = Calendar.current.date(byAdding: .minute, value: 30, to: entry.date)!
    completion(Timeline(entries: [entry], policy: .after(refresh)))
  }
}

private struct BudgetAIWidgetView: View {
  let entry: BudgetEntry
  @Environment(\.widgetFamily) private var family
  @Environment(\.colorScheme) private var colorScheme

  private var primary: Color { colorScheme == .dark ? .white : .black }
  private var secondary: Color { primary.opacity(0.62) }
  private let accent = Color(red: 0.16, green: 0.42, blue: 1.0)

  var body: some View {
    VStack(alignment: .leading, spacing: family == .systemSmall ? 8 : 12) {
      header
      if family == .systemSmall {
        smallContent
      } else {
        mediumContent
      }
    }
    .padding(16)
    .containerBackground(for: .widget) {
      Color(uiColor: .systemBackground)
    }
  }

  private var header: some View {
    HStack(spacing: 7) {
      ZStack {
        Circle().fill(accent)
        Image(systemName: "waveform")
          .font(.system(size: 10, weight: .bold))
          .foregroundStyle(.white)
      }
      .frame(width: 23, height: 23)
      Text("BUDGET AI")
        .font(.system(size: 11, weight: .black, design: .rounded))
        .tracking(0.8)
        .foregroundStyle(primary)
      Spacer(minLength: 2)
      Image(systemName: "mic.fill")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(accent)
    }
  }

  private var smallContent: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("THIS MONTH")
        .font(.system(size: 9, weight: .bold, design: .rounded))
        .tracking(0.5)
        .foregroundStyle(secondary)
      Text(format(entry.balance, signed: true))
        .font(.system(size: 22, weight: .bold, design: .rounded))
        .minimumScaleFactor(0.65)
        .lineLimit(1)
        .foregroundStyle(primary)
      Spacer(minLength: 0)
      Label("Say “Add expense…”", systemImage: "waveform")
        .font(.system(size: 9, weight: .semibold, design: .rounded))
        .lineLimit(1)
        .foregroundStyle(accent)
    }
  }

  private var mediumContent: some View {
    HStack(spacing: 14) {
      VStack(alignment: .leading, spacing: 5) {
        Text("MONTHLY BALANCE")
          .font(.system(size: 9, weight: .bold, design: .rounded))
          .tracking(0.5)
          .foregroundStyle(secondary)
        Text(format(entry.balance, signed: true))
          .font(.system(size: 24, weight: .bold, design: .rounded))
          .minimumScaleFactor(0.65)
          .lineLimit(1)
          .foregroundStyle(primary)
        HStack(spacing: 8) {
          summaryPill("IN", value: entry.income, color: .green)
          summaryPill("OUT", value: entry.expense, color: .red)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Rectangle()
        .fill(primary.opacity(0.09))
        .frame(width: 1)

      VStack(alignment: .leading, spacing: 5) {
        Text("ADD BY VOICE")
          .font(.system(size: 9, weight: .bold, design: .rounded))
          .tracking(0.5)
          .foregroundStyle(secondary)
        Text("“Add an expense in Budget AI”")
          .font(.system(size: 12, weight: .semibold, design: .rounded))
          .foregroundStyle(primary)
          .lineLimit(3)
        Text("Ask Siri")
          .font(.system(size: 10, weight: .bold, design: .rounded))
          .foregroundStyle(accent)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func summaryPill(_ label: String, value: Double, color: Color) -> some View {
    HStack(spacing: 3) {
      Circle().fill(color).frame(width: 5, height: 5)
      Text("\(label) \(format(value))")
        .lineLimit(1)
    }
    .font(.system(size: 9, weight: .semibold, design: .rounded))
    .foregroundStyle(secondary)
  }

  private func format(_ amount: Double, signed: Bool = false) -> String {
    let number = NumberFormatter()
    number.numberStyle = .decimal
    number.maximumFractionDigits = amount.rounded() == amount ? 0 : 2
    let sign = signed && amount > 0 ? "+" : ""
    let value = number.string(from: NSNumber(value: amount)) ?? String(amount)
    if ["$", "€", "£", "₹", "¥"].contains(entry.currency) {
      return "\(sign)\(entry.currency)\(value)"
    }
    return "\(sign)\(value) \(entry.currency)"
  }
}

@main
struct BudgetAIWidget: Widget {
  let kind = "BudgetAIWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: BudgetProvider()) { entry in
      BudgetAIWidgetView(entry: entry)
    }
    .configurationDisplayName("Budget AI")
    .description("See your monthly budget and learn the Siri voice command.")
    .supportedFamilies([.systemSmall, .systemMedium])
    .contentMarginsDisabled()
  }
}
