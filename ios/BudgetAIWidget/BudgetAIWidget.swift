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
    ZStack {
      Image("budget_widget_landscape").resizable().scaledToFill()
      VStack(spacing: 10) {
        header
        Spacer(minLength: 0)
        totalCard(title: "Income", amount: entry.income, color: green, symbol: "arrow.up.right")
        totalCard(title: "Expense", amount: entry.expense, color: red, symbol: "arrow.down.right")
      }
      .padding(14)
    }
    .containerBackground(for: .widget) { Color(red: 0.76, green: 0.92, blue: 0.98) }
  }

  private var header: some View {
    HStack(alignment: .top, spacing: 8) {
      VStack(alignment: .leading, spacing: 2) {
        Text(entry.month == WidgetStore.currentMonthKey() ? "This Month" : monthName)
          .font(.system(size: 19, weight: .heavy, design: .rounded))
          .foregroundStyle(navy)
        Text("Small steps. Brighter tomorrows.")
          .font(.system(size: 9, weight: .medium, design: .rounded))
          .foregroundStyle(navy.opacity(0.72))
      }
      Spacer(minLength: 2)
      monthControl
    }
  }

  private var monthControl: some View {
    HStack(spacing: 1) {
      Button(intent: ChangeBudgetMonthIntent(direction: -1)) {
        Image(systemName: "chevron.left")
      }
      Text(shortMonth)
        .font(.system(size: 10, weight: .semibold, design: .rounded))
        .lineLimit(1)
      Button(intent: ChangeBudgetMonthIntent(direction: 1)) {
        Image(systemName: "chevron.right").opacity(entry.canMoveForward ? 1 : 0.25)
      }
      .disabled(!entry.canMoveForward)
    }
    .foregroundStyle(.white)
    .padding(.horizontal, 6)
    .frame(height: 30)
    .background(.black.opacity(0.72), in: Capsule())
  }

  private func totalCard(title: String, amount: Double, color: Color, symbol: String) -> some View {
    HStack(spacing: 10) {
      ZStack {
        Circle().fill(color.gradient)
        Image(systemName: symbol)
          .font(.system(size: 17, weight: .heavy))
          .foregroundStyle(.white)
      }
      .frame(width: 40, height: 40)
      VStack(alignment: .leading, spacing: 0) {
        Text(title)
          .font(.system(size: 11, weight: .bold, design: .rounded))
          .foregroundStyle(navy)
        Text(format(amount))
          .font(.system(size: 21, weight: .heavy, design: .rounded))
          .minimumScaleFactor(0.58)
          .lineLimit(1)
          .foregroundStyle(color)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 12)
    .frame(maxWidth: .infinity, minHeight: 58)
    .background(.white.opacity(0.90), in: RoundedRectangle(cornerRadius: 20))
    .shadow(color: navy.opacity(0.12), radius: 5, y: 3)
  }

  private var monthDate: Date? {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter.date(from: entry.month)
  }

  private var monthName: String {
    monthDate?.formatted(.dateTime.month(.wide).year()) ?? entry.month
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
