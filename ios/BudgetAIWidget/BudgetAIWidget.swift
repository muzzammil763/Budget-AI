import SwiftUI
import WidgetKit

private enum WidgetStore {
  static let appGroup = "group.com.muzamil.budget.ai"
  static let expenseKey = "budget_ai_widget_month_expense"
  static let incomeKey = "budget_ai_widget_month_income"
  static let latestDescriptionKey = "budget_ai_widget_latest_description"
  static let latestAmountKey = "budget_ai_widget_latest_amount"
  static let latestTypeKey = "budget_ai_widget_latest_type"
  static let previousDescriptionKey = "budget_ai_widget_previous_description"
  static let previousAmountKey = "budget_ai_widget_previous_amount"
  static let previousTypeKey = "budget_ai_widget_previous_type"
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
      previousDescription: defaults?.string(forKey: previousDescriptionKey) ?? "",
      previousAmount: defaults?.double(forKey: previousAmountKey) ?? 0,
      previousType: defaults?.string(forKey: previousTypeKey) ?? "expense",
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
  private let accent = Color(red: 68 / 255, green: 138 / 255, blue: 1.0)
  private var markGradientEnd: Color {
    colorScheme == .dark
      ? Color(red: 203 / 255, green: 222 / 255, blue: 1.0)
      : Color(red: 19 / 255, green: 39 / 255, blue: 71 / 255)
  }

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
      BudgetMarkView(
        accent: accent,
        primary: primary,
        gradientEnd: markGradientEnd,
        surface: colorScheme == .dark ? .black : .white
      )
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
        Text("Current Balance")
          .font(.system(size: 9))
          .foregroundStyle(secondary)
        Text(format(entry.balance))
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
        metric("Income", value: entry.income, color: .green)
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

private struct BudgetMarkView: View {
  let accent: Color
  let primary: Color
  let gradientEnd: Color
  let surface: Color

  var body: some View {
    GeometryReader { proxy in
      let size = proxy.size.width
      ZStack {
        Circle()
          .trim(from: 0, to: 0.75)
          .stroke(
            AngularGradient(
              colors: [.clear, accent.opacity(0.65)],
              center: .center
            ),
            style: StrokeStyle(lineWidth: 1.6, lineCap: .round)
          )
          .rotationEffect(.degrees(-90))
        RoundedRectangle(cornerRadius: size * 0.23)
          .fill(
            LinearGradient(
              colors: [primary, gradientEnd],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
          .frame(width: size * 0.78, height: size * 0.78)
        HStack(alignment: .bottom, spacing: size * 0.0585) {
          markBar(height: size * 0.1872, width: size * 0.1014)
          markBar(height: size * 0.2964, width: size * 0.1014)
          markBar(height: size * 0.4056, width: size * 0.1014)
        }
        .offset(y: size * 0.0156)
        Circle()
          .fill(accent)
          .frame(width: size * 0.075, height: size * 0.075)
          .offset(x: size * 0.188, y: -size * 0.277)
        Image(systemName: "sparkle")
          .font(.system(size: size * 0.16, weight: .bold))
          .foregroundStyle(accent)
          .offset(x: size * 0.429, y: -size * 0.429)
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
    .description("See your current balance, income, spending, and two newest entries.")
    .supportedFamilies([.systemMedium])
    .contentMarginsDisabled()
  }
}
