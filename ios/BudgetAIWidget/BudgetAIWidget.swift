import AppIntents
import SwiftUI
import WidgetKit

private enum WidgetStore {
  static let appGroup = "group.com.muzamil.budget.ai"
  static let summariesKey = "budget_ai_widget_month_summaries"
  static let selectedMonthKey = "budget_ai_widget_selected_month"
  static let currencyKey = "budget_ai_widget_currency"

  static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

  static func summaries() -> [MonthSummary] {
    guard
      let raw = defaults?.string(forKey: summariesKey),
      let data = raw.data(using: .utf8),
      let decoded = try? JSONDecoder().decode([MonthSummary].self, from: data)
    else { return [] }
    return decoded
  }

  static func currentMonthKey(date: Date = Date()) -> String {
    let parts = Calendar.current.dateComponents([.year, .month], from: date)
    return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
  }

  static func selectedMonth() -> String {
    let current = currentMonthKey()
    guard
      let saved = defaults?.string(forKey: selectedMonthKey),
      saved <= current,
      saved == current || summaries().contains(where: { $0.month == saved })
    else {
      return current
    }
    return saved
  }

  static func moveSelection(by offset: Int) {
    let current = selectedMonth()
    var candidates = Set(summaries().map(\.month))
    candidates.insert(currentMonthKey())
    let ordered = candidates.sorted(by: >)
    guard let index = ordered.firstIndex(of: current) else { return }
    let target = min(max(index - offset, 0), ordered.count - 1)
    defaults?.set(ordered[target], forKey: selectedMonthKey)
  }

  static func entry(date: Date = Date()) -> BudgetEntry {
    let values = summaries()
    let selected = selectedMonth()
    let summary = values.first(where: { $0.month == selected })
    return BudgetEntry(
      date: date,
      month: selected,
      expense: summary?.expense ?? 0,
      income: summary?.income ?? 0,
      currency: defaults?.string(forKey: currencyKey) ?? "USD",
      canMoveForward: selected < currentMonthKey()
    )
  }
}

private struct MonthSummary: Codable {
  let month: String
  let expense: Double
  let income: Double
}

struct BudgetEntry: TimelineEntry {
  let date: Date
  let month: String
  let expense: Double
  let income: Double
  let currency: String
  let canMoveForward: Bool
}

struct BudgetProvider: TimelineProvider {
  func placeholder(in context: Context) -> BudgetEntry {
    BudgetEntry(
      date: Date(), month: "2026-09", expense: 1_480, income: 3_250,
      currency: "$", canMoveForward: false
    )
  }

  func getSnapshot(in context: Context, completion: @escaping (BudgetEntry) -> Void) {
    completion(WidgetStore.entry())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<BudgetEntry>) -> Void) {
    let entry = WidgetStore.entry()
    let refresh = Calendar.current.date(byAdding: .minute, value: 30, to: entry.date)!
    completion(Timeline(entries: [entry], policy: .after(refresh)))
  }
}

struct ChangeBudgetMonthIntent: AppIntent {
  static let title: LocalizedStringResource = "Change Budget Month"
  static let isDiscoverable = false

  @Parameter(title: "Direction") var direction: Int

  init() {}
  init(direction: Int) { self.direction = direction }

  func perform() async throws -> some IntentResult {
    WidgetStore.moveSelection(by: direction)
    WidgetCenter.shared.reloadTimelines(ofKind: "BudgetAIWidget")
    return .result()
  }
}

private struct BudgetAIWidgetView: View {
  let entry: BudgetEntry
  private let navy = Color(red: 22 / 255, green: 41 / 255, blue: 67 / 255)
  private let green = Color(red: 16 / 255, green: 157 / 255, blue: 87 / 255)
  private let red = Color(red: 238 / 255, green: 63 / 255, blue: 74 / 255)

  var body: some View {
    GeometryReader { proxy in
      let size = min(proxy.size.width, proxy.size.height)
      ZStack(alignment: .topLeading) {
        Image("budget_widget_reference_v2")
          .resizable()
          .scaledToFill()
          .frame(width: proxy.size.width, height: proxy.size.height)
          .clipped()

        Text(entry.month == WidgetStore.currentMonthKey() ? "This Month" : monthName)
          .font(.system(size: size * 0.068, weight: .heavy, design: .rounded))
          .foregroundStyle(navy)
          .minimumScaleFactor(0.72)
          .lineLimit(1)
          .frame(width: size * 0.34, alignment: .leading)
          .position(x: size * 0.46, y: size * 0.12)

        monthControl(size: size)
          .position(x: size * 0.80, y: size * 0.12)

        totalText(title: "Income", amount: entry.income, color: green, size: size)
          .position(x: size * 0.60, y: size * 0.505)

        totalText(title: "Expense", amount: entry.expense, color: red, size: size)
          .position(x: size * 0.60, y: size * 0.735)

        Text("You're doing great!")
          .font(.system(size: size * 0.048, weight: .bold, design: .rounded))
          .foregroundStyle(navy.opacity(0.82))
          .lineLimit(1)
          .position(x: size * 0.59, y: size * 0.925)
      }
    }
    .containerBackground(for: .widget) { Color(red: 0.76, green: 0.92, blue: 0.98) }
  }

  private func monthControl(size: CGFloat) -> some View {
    HStack(spacing: 0) {
      Button(intent: ChangeBudgetMonthIntent(direction: -1)) {
        Image(systemName: "chevron.left")
      }
      .frame(width: size * 0.085, height: size * 0.13)
      Text(shortMonth)
        .font(.system(size: size * 0.048, weight: .bold, design: .rounded))
        .minimumScaleFactor(0.75)
        .lineLimit(1)
      Button(intent: ChangeBudgetMonthIntent(direction: 1)) {
        Image(systemName: "chevron.right").opacity(entry.canMoveForward ? 1 : 0.25)
      }
      .disabled(!entry.canMoveForward)
      .frame(width: size * 0.085, height: size * 0.13)
    }
    .foregroundStyle(.white)
    .font(.system(size: size * 0.046, weight: .bold))
    .frame(width: size * 0.37, height: size * 0.13)
    .background(.black.opacity(0.70), in: Capsule())
    .shadow(color: .black.opacity(0.18), radius: size * 0.018, y: size * 0.01)
  }

  private func totalText(
    title: String,
    amount: Double,
    color: Color,
    size: CGFloat
  ) -> some View {
    VStack(alignment: .leading, spacing: -size * 0.006) {
      Text(title)
        .font(.system(size: size * 0.058, weight: .heavy, design: .rounded))
        .foregroundStyle(navy)
      Text(format(amount))
        .font(.system(size: size * 0.105, weight: .heavy, design: .rounded))
        .minimumScaleFactor(0.46)
        .lineLimit(1)
        .foregroundStyle(color)
    }
    .frame(width: size * 0.60, alignment: .leading)
  }

  private var monthDate: Date? {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter.date(from: entry.month)
  }

  private var monthName: String {
    monthDate?.formatted(.dateTime.month(.abbreviated)) ?? entry.month
  }

  private var shortMonth: String {
    monthDate?.formatted(.dateTime.month(.abbreviated).year(.twoDigits)) ?? entry.month
  }

  private func format(_ amount: Double) -> String {
    let number = NumberFormatter()
    number.numberStyle = .decimal
    number.maximumFractionDigits = amount.rounded() == amount ? 0 : 2
    let value = number.string(from: NSNumber(value: amount)) ?? String(amount)
    return ["$", "€", "£", "₹", "¥"].contains(entry.currency)
      ? "\(entry.currency)\(value)" : "\(value) \(entry.currency)"
  }
}

@main
struct BudgetAIWidget: Widget {
  let kind = "BudgetAIWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: BudgetProvider()) { entry in
      BudgetAIWidgetView(entry: entry)
        .widgetURL(URL(string: "budgetai://widget?homeWidget"))
    }
    .configurationDisplayName("Budget AI Monthly")
    .description("Browse monthly income and expenses from your Home Screen.")
    .supportedFamilies([.systemSmall])
    .contentMarginsDisabled()
  }
}
