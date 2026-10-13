import AppIntents
import Foundation
import WidgetKit

/// Keys shared with Flutter's `BudgetHomeWidgetSync` through the App Group.
enum WidgetStore {
  static let appGroup = "group.com.muzamil.budget.ai"
  static let entriesKey = "budget_ai_widget_entries"
  static let expenseKey = "budget_ai_widget_month_expense"
  static let incomeKey = "budget_ai_widget_month_income"
  static let latestDescriptionKey = "budget_ai_widget_latest_description"
  static let latestAmountKey = "budget_ai_widget_latest_amount"
  static let latestTypeKey = "budget_ai_widget_latest_type"
  static let previousDescriptionKey = "budget_ai_widget_previous_description"
  static let previousAmountKey = "budget_ai_widget_previous_amount"
  static let previousTypeKey = "budget_ai_widget_previous_type"
  static let currencyKey = "budget_ai_widget_currency"
  static let monthOffsetPrefix = "budget_ai_widget_month_offset_"

  static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

  static var currency: String {
    defaults?.string(forKey: currencyKey) ?? "USD"
  }

  /// Every actual expense and income entry the app last synced.
  static func entries() -> [WidgetFinanceEntry] {
    guard
      let raw = defaults?.string(forKey: entriesKey),
      let data = raw.data(using: .utf8),
      let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    else {
      return []
    }
    return list.compactMap(WidgetFinanceEntry.init(json:))
  }

  /// Months back from the current month shown by a month-switching widget.
  static func monthOffset(for kind: String) -> Int {
    min(0, defaults?.integer(forKey: monthOffsetPrefix + kind) ?? 0)
  }

  static func shiftMonth(for kind: String, by step: Int) {
    let next = max(-120, min(0, monthOffset(for: kind) + step))
    defaults?.set(next, forKey: monthOffsetPrefix + kind)
  }
}

struct WidgetFinanceEntry {
  let id: String
  let isIncome: Bool
  let date: Date
  let hasTime: Bool
  let description: String
  let amount: Double
  let category: String

  init?(json: [String: Any]) {
    guard
      let id = json["id"] as? String,
      let rawDate = json["date"] as? String,
      let date = WidgetFinanceEntry.parseDate(rawDate),
      let amount = (json["amount"] as? NSNumber)?.doubleValue
    else {
      return nil
    }
    self.id = id
    self.isIncome = (json["type"] as? String) == "income"
    self.date = date
    self.hasTime = json["has_time"] as? Bool ?? false
    self.description = json["description"] as? String ?? ""
    self.amount = amount
    self.category = json["category"] as? String ?? "Other"
  }

  init(
    id: String,
    isIncome: Bool,
    date: Date,
    hasTime: Bool,
    description: String,
    amount: Double,
    category: String
  ) {
    self.id = id
    self.isIncome = isIncome
    self.date = date
    self.hasTime = hasTime
    self.description = description
    self.amount = amount
    self.category = category
  }

  private static let localFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    return formatter
  }()

  /// Flutter writes wall-clock times without a zone, so only the first 19
  /// characters (`yyyy-MM-ddTHH:mm:ss`) matter.
  static func parseDate(_ value: String) -> Date? {
    localFormatter.date(from: String(value.prefix(19)))
  }
}

/// Totals for one calendar month.
struct MonthSummary {
  let month: Date
  let expense: Double
  let income: Double
  let expenseCount: Int
  let incomeCount: Int
}

/// Everything the widgets render, computed once per timeline entry.
struct BudgetSnapshot {
  let entries: [WidgetFinanceEntry]
  let currency: String
  let now: Date

  private var calendar: Calendar { Calendar.current }

  static func load(now: Date = Date()) -> BudgetSnapshot {
    BudgetSnapshot(entries: WidgetStore.entries(), currency: WidgetStore.currency, now: now)
  }

  func monthStart(offset: Int) -> Date {
    let current = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
    return calendar.date(byAdding: .month, value: offset, to: current)!
  }

  func summary(offset: Int) -> MonthSummary {
    let month = monthStart(offset: offset)
    let inMonth = entries.filter {
      calendar.isDate($0.date, equalTo: month, toGranularity: .month)
    }
    let expenses = inMonth.filter { !$0.isIncome }
    let incomes = inMonth.filter(\.isIncome)
    return MonthSummary(
      month: month,
      expense: expenses.reduce(0) { $0 + $1.amount },
      income: incomes.reduce(0) { $0 + $1.amount },
      expenseCount: expenses.count,
      incomeCount: incomes.count
    )
  }

  /// The oldest month offset that still has entries, so the ‹ arrow stops
  /// where the data does.
  var earliestOffset: Int {
    guard let oldest = entries.map(\.date).min() else { return 0 }
    let start = calendar.date(from: calendar.dateComponents([.year, .month], from: oldest))!
    let months = calendar.dateComponents([.month], from: start, to: monthStart(offset: 0)).month ?? 0
    return -max(0, months)
  }

  func recentExpenses(limit: Int) -> [WidgetFinanceEntry] {
    Array(
      entries.filter { !$0.isIncome }
        .sorted { $0.date > $1.date }
        .prefix(limit)
    )
  }

  var todayExpenses: [WidgetFinanceEntry] {
    entries.filter { !$0.isIncome && calendar.isDate($0.date, inSameDayAs: now) }
      .sorted { $0.date > $1.date }
  }

  static let preview: BudgetSnapshot = {
    let now = Date()
    let calendar = Calendar.current
    func day(_ offset: Int, hour: Int = 12) -> Date {
      let base = calendar.date(byAdding: .day, value: offset, to: now)!
      return calendar.date(bySettingHour: hour, minute: 15, second: 0, of: base)!
    }
    let samples: [(Bool, Int, String, Double, String)] = [
      (false, 0, "Groceries", 2_400, "Groceries"),
      (false, 0, "Coffee", 450, "Food"),
      (false, -1, "Fuel", 3_000, "Transportation"),
      (false, -2, "Internet bill", 2_800, "Bills"),
      (false, -3, "Lunch", 1_200, "Food"),
      (true, -5, "Salary", 90_000, "Salary"),
      (false, -32, "Rent", 35_000, "Housing"),
    ]
    let entries = samples.enumerated().map { index, sample in
      WidgetFinanceEntry(
        id: "preview_\(index)",
        isIncome: sample.0,
        date: day(sample.1, hour: 9 + index),
        hasTime: true,
        description: sample.2,
        amount: sample.3,
        category: sample.4
      )
    }
    return BudgetSnapshot(entries: entries, currency: "Rs", now: now)
  }()
}

// MARK: - Timeline

struct BudgetTimelineEntry: TimelineEntry {
  let date: Date
  let snapshot: BudgetSnapshot
  let monthOffset: Int
}

/// One provider for every snapshot-driven widget. [kind] selects which
/// month offset to read for widgets with month arrows.
struct BudgetSnapshotProvider: TimelineProvider {
  let kind: String

  func placeholder(in context: Context) -> BudgetTimelineEntry {
    BudgetTimelineEntry(date: Date(), snapshot: .preview, monthOffset: 0)
  }

  func getSnapshot(
    in context: Context,
    completion: @escaping (BudgetTimelineEntry) -> Void
  ) {
    if context.isPreview {
      completion(placeholder(in: context))
    } else {
      completion(currentEntry())
    }
  }

  func getTimeline(
    in context: Context,
    completion: @escaping (Timeline<BudgetTimelineEntry>) -> Void
  ) {
    let entry = currentEntry()
    // Refresh every 30 minutes and right after midnight, so "today" and
    // the current month roll over on time.
    let calendar = Calendar.current
    let halfHour = calendar.date(byAdding: .minute, value: 30, to: entry.date)!
    let midnight = calendar.startOfDay(
      for: calendar.date(byAdding: .day, value: 1, to: entry.date)!
    )
    completion(Timeline(entries: [entry], policy: .after(min(halfHour, midnight))))
  }

  private func currentEntry() -> BudgetTimelineEntry {
    let snapshot = BudgetSnapshot.load()
    let offset = max(WidgetStore.monthOffset(for: kind), snapshot.earliestOffset)
    return BudgetTimelineEntry(date: Date(), snapshot: snapshot, monthOffset: offset)
  }
}

// MARK: - Month arrows

/// Moves a month-switching widget one month back or forward in place.
/// Hidden from the Shortcuts app; it only backs the widget's ‹ › buttons.
struct ShiftWidgetMonthIntent: AppIntent {
  static let title: LocalizedStringResource = "Change Widget Month"
  static let isDiscoverable = false

  @Parameter(title: "Widget")
  var widgetKind: String

  @Parameter(title: "Step")
  var step: Int

  init() {}

  init(widgetKind: String, step: Int) {
    self.widgetKind = widgetKind
    self.step = step
  }

  func perform() async throws -> some IntentResult {
    WidgetStore.shiftMonth(for: widgetKind, by: step)
    return .result()
  }
}
