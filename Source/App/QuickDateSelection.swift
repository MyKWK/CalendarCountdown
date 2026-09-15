import SwiftUI

/// A date-only control that keeps common planning choices one click away and
/// reserves the calendar for dates that actually need browsing.
struct QuickDateSelection: View {
    let title: String
    @Binding var selection: Date
    var showsTime: Bool = false

    @State private var showingCalendar = false

    init(_ title: String, selection: Binding<Date>, showsTime: Bool = false) {
        self.title = title
        _selection = selection
        self.showsTime = showsTime
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text(selection, format: .dateTime.year().month().day().weekday())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                shortcutButton("今天", date: Date())
                shortcutButton("明天", date: QuickDateSelection.tomorrow())
                shortcutButton("下周一", date: QuickDateSelection.nextMonday())
                Button("日历选择") { showingCalendar = true }
                    .accessibilityIdentifier("quick-date-calendar-button")
            }
            .buttonStyle(.bordered)

            if showsTime {
                DatePicker("具体时间", selection: $selection, displayedComponents: .hourAndMinute)
            }
        }
        .sheet(isPresented: $showingCalendar) {
            ScrollableCalendarSheet(selection: $selection)
        }
    }

    private func shortcutButton(_ title: String, date: Date) -> some View {
        Button(title) { selection = Self.applyingDate(date, to: selection) }
    }

    static func tomorrow(calendar: Calendar = .current, now: Date = Date()) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
    }

    /// "下周一" means the next Monday. When today is Monday, it deliberately
    /// advances seven days instead of selecting today again.
    static func nextMonday(calendar: Calendar = .current, now: Date = Date()) -> Date {
        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: today)
        let monday = 2 // Gregorian Calendar weekday: Sunday = 1, Monday = 2.
        let offset = (monday - weekday + 7) % 7
        return calendar.date(byAdding: .day, value: offset == 0 ? 7 : offset, to: today) ?? today
    }

    static func applyingDate(_ date: Date, to original: Date, calendar: Calendar = .current) -> Date {
        let time = calendar.dateComponents([.hour, .minute, .second], from: original)
        return calendar.date(
            bySettingHour: time.hour ?? 0,
            minute: time.minute ?? 0,
            second: time.second ?? 0,
            of: date
        ) ?? date
    }
}

private struct ScrollableCalendarSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: Date
    @State private var visibleMonth: Date

    private let calendar: Calendar
    private let months: [Date]

    init(selection: Binding<Date>) {
        _selection = selection
        var calendar = Calendar.current
        calendar.locale = .current
        self.calendar = calendar
        let selectedMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: selection.wrappedValue)) ?? selection.wrappedValue
        _visibleMonth = State(initialValue: selectedMonth)
        months = (-24...60).compactMap { offset in
            calendar.date(byAdding: .month, value: offset, to: selectedMonth)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("选择日期").font(.title3.weight(.semibold))
                    Text("上下滚动浏览不同月份")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 24) {
                        ForEach(months, id: \.self) { month in
                            MonthCalendar(month: month, selection: $selection, calendar: calendar)
                                .id(month)
                        }
                    }
                    .padding(20)
                }
                .onAppear {
                    proxy.scrollTo(visibleMonth, anchor: .top)
                }
            }
        }
        .frame(width: 520, height: 680)
        .accessibilityIdentifier("scrollable-calendar-sheet")
    }
}

private struct MonthCalendar: View {
    let month: Date
    @Binding var selection: Date
    let calendar: Calendar

    private var weekdaySymbols: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let offset = calendar.firstWeekday - 1
        return Array(symbols[offset...]) + Array(symbols[..<offset])
    }

    private var days: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: month),
              let first = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) else {
            return []
        }
        let firstWeekday = calendar.component(.weekday, from: first)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: leading) + range.compactMap {
            calendar.date(byAdding: .day, value: $0 - 1, to: first)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(month, format: .dateTime.year().month(.wide))
                .font(.headline)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 8) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                    if let date {
                        Button {
                            selection = QuickDateSelection.applyingDate(date, to: selection, calendar: calendar)
                        } label: {
                            Text("\(calendar.component(.day, from: date))")
                                .frame(maxWidth: .infinity, minHeight: 32)
                        }
                        .buttonStyle(CalendarDayButtonStyle(
                            isSelected: calendar.isDate(date, inSameDayAs: selection),
                            isToday: calendar.isDateInToday(date)
                        ))
                        .accessibilityLabel(date.formatted(date: .long, time: .omitted))
                    } else {
                        Color.clear.frame(height: 32)
                    }
                }
            }
        }
    }
}

private struct CalendarDayButtonStyle: ButtonStyle {
    let isSelected: Bool
    let isToday: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isSelected ? Color.white : (isToday ? Color.accentColor : Color.primary))
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isToday && !isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}
