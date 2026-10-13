import AppIntents
import SwiftUI
import WidgetKit

/// The app's monochrome palette with red expense and green income accents.
struct WidgetPalette {
  let colorScheme: ColorScheme

  var primary: Color { colorScheme == .dark ? .white : .black }
  var secondary: Color { primary.opacity(0.58) }
  var hairline: Color { primary.opacity(0.09) }
  var chip: Color { primary.opacity(0.06) }
  var surface: Color { colorScheme == .dark ? .black : .white }
  var expense: Color { Color(red: 0.93, green: 0.27, blue: 0.27) }
  var income: Color { Color(red: 0.13, green: 0.70, blue: 0.40) }
  let accent = Color(red: 68 / 255, green: 138 / 255, blue: 1.0)
  var markGradientEnd: Color {
    colorScheme == .dark
      ? Color(red: 203 / 255, green: 222 / 255, blue: 1.0)
      : Color(red: 19 / 255, green: 39 / 255, blue: 71 / 255)
  }
}

enum WidgetFont {
  /// Branded display face, used for headline amounts.
  static func display(_ size: CGFloat) -> Font { .custom("Boldonse", size: size) }
  /// The app's body face.
  static func body(_ size: CGFloat) -> Font { .custom("Google Sans", size: size) }
}

enum WidgetFormat {
  static func amount(
    _ value: Double,
    currency: String,
    sign: String = ""
  ) -> String {
    let number = NumberFormatter()
    number.numberStyle = .decimal
    let digits = value.rounded() == value ? 0 : 2
    number.minimumFractionDigits = digits
    number.maximumFractionDigits = digits
    let text = number.string(from: NSNumber(value: value)) ?? String(value)
    if ["$", "€", "£", "₹", "¥"].contains(currency) {
      return "\(sign)\(currency)\(text)"
    }
    return "\(sign)\(text) \(currency)"
  }

  static func month(_ date: Date, relativeTo now: Date) -> String {
    let sameYear = Calendar.current.isDate(date, equalTo: now, toGranularity: .year)
    return sameYear
      ? date.formatted(.dateTime.month(.abbreviated))
      : date.formatted(.dateTime.month(.abbreviated).year(.twoDigits))
  }

  static func day(_ date: Date, relativeTo now: Date) -> String {
    let calendar = Calendar.current
    if calendar.isDate(date, inSameDayAs: now) { return "Today" }
    if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
       calendar.isDate(date, inSameDayAs: yesterday) {
      return "Yesterday"
    }
    return date.formatted(.dateTime.day().month(.abbreviated))
  }

  static func entries(_ value: Int) -> String {
    "\(value) \(value == 1 ? "entry" : "entries")"
  }
}

/// `‹ Oct ›` chip that moves the widget between months in place.
struct MonthSwitcher: View {
  let kind: String
  let entry: BudgetTimelineEntry
  let palette: WidgetPalette

  private var canGoBack: Bool { entry.monthOffset > entry.snapshot.earliestOffset }
  private var canGoForward: Bool { entry.monthOffset < 0 }

  var body: some View {
    HStack(spacing: 0) {
      arrow("chevron.left", step: -1, enabled: canGoBack)
      Text(
        WidgetFormat.month(
          entry.snapshot.monthStart(offset: entry.monthOffset),
          relativeTo: entry.snapshot.now
        )
      )
      .font(WidgetFont.body(11).weight(.semibold))
      .foregroundStyle(palette.primary)
      .lineLimit(1)
      .fixedSize()
      arrow("chevron.right", step: 1, enabled: canGoForward)
    }
    .padding(.horizontal, 2)
    .background(Capsule().fill(palette.chip))
  }

  @ViewBuilder
  private func arrow(_ symbol: String, step: Int, enabled: Bool) -> some View {
    let icon = Image(systemName: symbol)
      .font(.system(size: 9, weight: .bold))
      .frame(width: 20, height: 22)
      .contentShape(Rectangle())
    if enabled {
      Button(intent: ShiftWidgetMonthIntent(widgetKind: kind, step: step)) {
        icon.foregroundStyle(palette.primary)
      }
      .buttonStyle(.plain)
    } else {
      icon.foregroundStyle(palette.primary.opacity(0.2))
    }
  }
}

/// Round tinted badge with an arrow, matching the app's summary card icons.
struct FlowBadge: View {
  let isIncome: Bool
  let palette: WidgetPalette
  var size: CGFloat = 26

  var body: some View {
    let color = isIncome ? palette.income : palette.expense
    Image(systemName: isIncome ? "arrow.down.left" : "arrow.up.right")
      .font(.system(size: size * 0.42, weight: .bold))
      .foregroundStyle(color)
      .frame(width: size, height: size)
      .background(Circle().fill(color.opacity(0.14)))
  }
}

struct BudgetMarkView: View {
  let palette: WidgetPalette

  var body: some View {
    GeometryReader { proxy in
      let size = proxy.size.width
      ZStack {
        Circle()
          .trim(from: 0, to: 0.75)
          .stroke(
            AngularGradient(
              colors: [.clear, palette.accent.opacity(0.65)],
              center: .center
            ),
            style: StrokeStyle(lineWidth: max(1, size * 0.038), lineCap: .round)
          )
          .rotationEffect(.degrees(-90))
        RoundedRectangle(cornerRadius: size * 0.23)
          .fill(
            LinearGradient(
              colors: [palette.primary, palette.markGradientEnd],
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
          .fill(palette.accent)
          .frame(width: size * 0.075, height: size * 0.075)
          .offset(x: size * 0.188, y: -size * 0.277)
        Image(systemName: "sparkle")
          .font(.system(size: size * 0.16, weight: .bold))
          .foregroundStyle(palette.accent)
          .offset(x: size * 0.429, y: -size * 0.429)
      }
    }
  }

  private func markBar(height: CGFloat, width: CGFloat) -> some View {
    Capsule()
      .fill(palette.surface)
      .frame(width: width, height: height)
  }
}

extension View {
  /// The shared widget surface: system background with the app's padding.
  func budgetWidgetSurface(padding: CGFloat = 14) -> some View {
    self
      .padding(padding)
      .containerBackground(for: .widget) {
        Color(uiColor: .systemBackground)
      }
  }
}
