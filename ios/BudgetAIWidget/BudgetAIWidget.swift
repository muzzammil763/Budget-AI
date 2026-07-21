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
  @Environment(\.colorScheme) private var colorScheme

  private var primary: Color { colorScheme == .dark ? .white : .black }
  private var secondary: Color { primary.opacity(0.62) }
  private let accent = Color(red: 0.16, green: 0.42, blue: 1.0)

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      header
      summary
      latestEntry
    }
    .padding(16)
    .containerBackground(for: .widget) {
      Color(uiColor: .systemBackground)
    }
  }

  private var header: some View {
    HStack(spacing: 10) {
      BudgetMarkView(
        accent: accent,
        primary: primary,
        surface: colorScheme == .dark ? .black : .white
      )
        .frame(width: 36, height: 36)
      VStack(alignment: .leading, spacing: 1) {
        Text("BUDGET AI")
          .font(.system(size: 12, weight: .black, design: .rounded))
          .tracking(0.8)
          .foregroundStyle(primary)
        Text("SMART FINANCE OVERVIEW")
          .font(.system(size: 8, weight: .bold, design: .rounded))
          .tracking(0.45)
          .foregroundStyle(secondary)
      }
      Spacer()
      Text(entry.date.formatted(.dateTime.month(.wide)))
        .font(.system(size: 10, weight: .bold, design: .rounded))
        .foregroundStyle(accent)
    }
  }

  private var summary: some View {
    HStack(spacing: 16) {
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
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Rectangle()
        .fill(primary.opacity(0.09))
        .frame(width: 1)

      HStack(spacing: 18) {
        metric("INCOME", value: entry.income, color: .green)
        metric("SPENT", value: entry.expense, color: .red)
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
      .font(.system(size: 8, weight: .bold, design: .rounded))
      .foregroundStyle(secondary)
      Text(format(value))
        .font(.system(size: 13, weight: .bold, design: .rounded))
        .minimumScaleFactor(0.65)
        .lineLimit(1)
        .foregroundStyle(primary)
    }
  }

  private var latestEntry: some View {
    HStack(spacing: 6) {
      Text("LATEST")
        .font(.system(size: 8, weight: .bold, design: .rounded))
        .tracking(0.4)
        .foregroundStyle(secondary)
      Text(entry.latestDescription)
        .font(.system(size: 10, weight: .semibold, design: .rounded))
        .lineLimit(1)
        .foregroundStyle(primary)
      Spacer(minLength: 4)
      if entry.latestAmount > 0 {
        Text(format(entry.latestAmount, signed: true, isIncome: entry.latestType == "income"))
          .font(.system(size: 10, weight: .bold, design: .rounded))
          .lineLimit(1)
          .foregroundStyle(entry.latestType == "income" ? .green : .red)
      }
    }
    .padding(.horizontal, 9)
    .padding(.vertical, 6)
    .background(primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
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

private struct BudgetMarkView: View {
  let accent: Color
  let primary: Color
  let surface: Color

  var body: some View {
    GeometryReader { proxy in
      let size = proxy.size.width
      ZStack {
        Circle()
          .stroke(
            AngularGradient(
              colors: [.clear, accent.opacity(0.7), .clear],
              center: .center
            ),
            lineWidth: 1.2
          )
        RoundedRectangle(cornerRadius: size * 0.23)
          .fill(
            LinearGradient(
              colors: [primary, accent.opacity(0.84)],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
          .frame(width: size * 0.78, height: size * 0.78)
        HStack(alignment: .bottom, spacing: size * 0.055) {
          markBar(height: size * 0.18, width: size * 0.10)
          markBar(height: size * 0.28, width: size * 0.10)
          markBar(height: size * 0.39, width: size * 0.10)
        }
        .offset(y: size * 0.075)
        Circle()
          .fill(accent)
          .frame(width: size * 0.075, height: size * 0.075)
          .offset(x: size * 0.15, y: -size * 0.19)
        Image(systemName: "sparkle")
          .font(.system(size: size * 0.16, weight: .bold))
          .foregroundStyle(accent)
          .offset(x: size * 0.34, y: -size * 0.34)
      }
    }
  }

  private func markBar(height: CGFloat, width: CGFloat) -> some View {
    Capsule()
      .fill(surface)
      .frame(width: width, height: height)
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
    .description("See your monthly balance, income, spending, and latest entry.")
    .supportedFamilies([.systemMedium])
    .contentMarginsDisabled()
  }
}
