import AppIntents
import Foundation
import WidgetKit

@available(iOS 16.0, *)
private enum BudgetSharedStore {
  static let appGroup = "group.com.muzamil.budget.ai"
  static let widgetKind = "BudgetAIWidget"
  static let financeChangedNotification =
    "com.muzamil.budget.ai.financeEntriesChanged" as CFString

  static let entriesKey = "budget_ai_widget_entries"
  static let pendingEntriesKey = "budget_ai_pending_entries"
  static let monthExpenseKey = "budget_ai_widget_month_expense"
  static let monthIncomeKey = "budget_ai_widget_month_income"
  static let latestDescriptionKey = "budget_ai_widget_latest_description"
  static let latestAmountKey = "budget_ai_widget_latest_amount"
  static let latestTypeKey = "budget_ai_widget_latest_type"
  static let currencyKey = "budget_ai_widget_currency"
  static let lastUpdatedKey = "budget_ai_widget_last_updated"

  static func addEntry(
    type: String,
    amount: Double,
    details: String
  ) throws -> String {
    guard let defaults = UserDefaults(suiteName: appGroup) else {
      throw BudgetShortcutError.appGroupUnavailable
    }

    let now = Date()
    let normalizedDetails = titleCase(details)
    let entry: [String: Any] = [
      "id": "siri_\(UUID().uuidString.lowercased())",
      "type": type,
      "date": iso8601(now),
      "has_time": true,
      "description": normalizedDetails,
      "amount": amount,
      "category": category(for: normalizedDetails, type: type),
      "created_at": iso8601(now),
    ]

    var allEntries = decodeEntries(defaults.string(forKey: entriesKey))
    allEntries.append(entry)
    var pendingEntries = decodeEntries(
      defaults.string(forKey: pendingEntriesKey)
    )
    pendingEntries.append(entry)

    defaults.set(encodeEntries(allEntries), forKey: entriesKey)
    defaults.set(encodeEntries(pendingEntries), forKey: pendingEntriesKey)
    defaults.set(normalizedDetails, forKey: latestDescriptionKey)
    defaults.set(amount, forKey: latestAmountKey)
    defaults.set(type, forKey: latestTypeKey)
    defaults.set(iso8601(now), forKey: lastUpdatedKey)
    updateMonthlyTotals(entries: allEntries, defaults: defaults, now: now)

    WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    CFNotificationCenterPostNotification(
      CFNotificationCenterGetDarwinNotifyCenter(),
      CFNotificationName(financeChangedNotification),
      nil,
      nil,
      true
    )
    let currency = defaults.string(forKey: currencyKey) ?? "USD"
    return formattedAmount(amount, currency: currency)
  }

  private static func decodeEntries(_ raw: String?) -> [[String: Any]] {
    guard
      let raw,
      let data = raw.data(using: .utf8),
      let value = try? JSONSerialization.jsonObject(with: data),
      let entries = value as? [[String: Any]]
    else {
      return []
    }
    return entries
  }

  private static func encodeEntries(_ entries: [[String: Any]]) -> String {
    guard
      let data = try? JSONSerialization.data(withJSONObject: entries),
      let value = String(data: data, encoding: .utf8)
    else {
      return "[]"
    }
    return value
  }

  private static func updateMonthlyTotals(
    entries: [[String: Any]],
    defaults: UserDefaults,
    now: Date
  ) {
    let calendar = Calendar.current
    var expense = 0.0
    var income = 0.0

    for entry in entries {
      guard
        let rawDate = entry["date"] as? String,
        let date = parseDate(rawDate),
        calendar.isDate(date, equalTo: now, toGranularity: .month),
        calendar.isDate(date, equalTo: now, toGranularity: .year),
        let amount = entry["amount"] as? NSNumber
      else {
        continue
      }
      if entry["type"] as? String == "income" {
        income += amount.doubleValue
      } else {
        expense += amount.doubleValue
      }
    }

    defaults.set(expense, forKey: monthExpenseKey)
    defaults.set(income, forKey: monthIncomeKey)
  }

  private static func titleCase(_ value: String) -> String {
    value
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .split(whereSeparator: { $0.isWhitespace })
      .map { word in
        let lower = word.lowercased()
        return lower.prefix(1).uppercased() + lower.dropFirst()
      }
      .joined(separator: " ")
  }

  private static func category(for details: String, type: String) -> String {
    let value = details.lowercased()
    if type == "income" {
      if value.contains("salary") { return "Salary" }
      if value.contains("freelance") { return "Freelance" }
      if value.contains("bonus") { return "Bonus" }
      if value.contains("refund") { return "Refund" }
      return details
    }
    if value.contains("grocery") || value.contains("food") {
      return "Groceries"
    }
    if value.contains("fuel") || value.contains("petrol") || value.contains("gas") {
      return "Transportation"
    }
    if value.contains("bill") || value.contains("electric") || value.contains("internet") {
      return "Bills"
    }
    if value.contains("medicine") || value.contains("doctor") || value.contains("health") {
      return "Healthcare"
    }
    return details
  }

  private static func iso8601(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }

  private static func parseDate(_ value: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
  }

  private static func formattedAmount(_ amount: Double, currency: String) -> String {
    let number = NumberFormatter()
    number.numberStyle = .decimal
    number.maximumFractionDigits = amount.rounded() == amount ? 0 : 2
    let value = number.string(from: NSNumber(value: amount)) ?? String(amount)
    if ["$", "€", "£", "₹", "¥"].contains(currency) {
      return "\(currency)\(value)"
    }
    return "\(value) \(currency)"
  }
}

@available(iOS 16.0, *)
private enum BudgetShortcutError: Error, CustomLocalizedStringResourceConvertible {
  case appGroupUnavailable

  var localizedStringResource: LocalizedStringResource {
    switch self {
    case .appGroupUnavailable:
      return "Budget AI's shared storage is unavailable. Open the app once and try again."
    }
  }
}

@available(iOS 16.0, *)
struct AddBudgetExpenseIntent: AppIntent {
  static let title: LocalizedStringResource = "Add Budget Expense"
  static let description = IntentDescription(
    "Adds an expense to Budget AI without opening the app."
  )
  static let openAppWhenRun = false

  @Parameter(
    title: "Amount",
    description: "The amount spent",
    requestValueDialog: "How much was it?"
  )
  var amount: Double

  @Parameter(
    title: "Description",
    description: "What the expense was for",
    requestValueDialog: "What was it for?"
  )
  var details: String

  static var parameterSummary: some ParameterSummary {
    Summary("Add \(\.$amount) for \(\.$details)")
  }

  init() {}

  func perform() async throws -> some IntentResult & ProvidesDialog {
    guard amount > 0 else {
      return .result(dialog: "Tell me an amount greater than zero.")
    }
    let cleanDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanDetails.isEmpty else {
      return .result(dialog: "Tell me what the expense was for.")
    }
    let displayAmount = try BudgetSharedStore.addEntry(
      type: "expense",
      amount: amount,
      details: cleanDetails
    )
    return .result(
      dialog: IntentDialog(
        stringLiteral: "Added \(displayAmount) for \(cleanDetails) to Budget AI."
      )
    )
  }
}

@available(iOS 16.0, *)
struct AddBudgetIncomeIntent: AppIntent {
  static let title: LocalizedStringResource = "Add Budget Income"
  static let description = IntentDescription(
    "Adds income to Budget AI without opening the app."
  )
  static let openAppWhenRun = false

  @Parameter(
    title: "Amount",
    description: "The amount received",
    requestValueDialog: "How much did you receive?"
  )
  var amount: Double

  @Parameter(
    title: "Description",
    description: "Where the income came from",
    requestValueDialog: "Where did it come from?"
  )
  var details: String

  static var parameterSummary: some ParameterSummary {
    Summary("Add \(\.$amount) income from \(\.$details)")
  }

  init() {}

  func perform() async throws -> some IntentResult & ProvidesDialog {
    guard amount > 0 else {
      return .result(dialog: "Tell me an amount greater than zero.")
    }
    let cleanDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanDetails.isEmpty else {
      return .result(dialog: "Tell me where the income came from.")
    }
    let displayAmount = try BudgetSharedStore.addEntry(
      type: "income",
      amount: amount,
      details: cleanDetails
    )
    return .result(
      dialog: IntentDialog(
        stringLiteral: "Added \(displayAmount) income from \(cleanDetails) to Budget AI."
      )
    )
  }
}

@available(iOS 16.0, *)
struct BudgetAIShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: AddBudgetExpenseIntent(),
      phrases: [
        "Add an expense in \(.applicationName)",
        "Log spending in \(.applicationName)",
      ],
      shortTitle: "Add Expense",
      systemImageName: "minus.circle.fill"
    )
    AppShortcut(
      intent: AddBudgetIncomeIntent(),
      phrases: [
        "Add income in \(.applicationName)",
        "Log money received in \(.applicationName)",
      ],
      shortTitle: "Add Income",
      systemImageName: "plus.circle.fill"
    )
  }
}
