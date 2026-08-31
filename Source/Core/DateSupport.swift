import Foundation

public enum DateSupport {
    public static func parseDateOnly(_ value: String, calendar: Calendar = .current) -> Date? {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        guard let date = calendar.date(from: components) else { return nil }
        let verified = calendar.dateComponents([.year, .month, .day], from: date)
        guard verified.year == year, verified.month == month, verified.day == day else { return nil }
        return calendar.startOfDay(for: date)
    }

    public static func parseTime(_ value: String) -> DateComponents? {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...23).contains(hour),
              (0...59).contains(minute) else {
            return nil
        }
        return DateComponents(hour: hour, minute: minute)
    }

    public static func applying(time: String?, to date: Date, calendar: Calendar = .current) -> Date? {
        guard let time else { return calendar.startOfDay(for: date) }
        guard let parsed = parseTime(time) else { return nil }
        return calendar.date(
            bySettingHour: parsed.hour ?? 0,
            minute: parsed.minute ?? 0,
            second: 0,
            of: date
        )
    }

    public static func dateOnlyString(_ date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    public static func nextMidnight(after date: Date = Date(), calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? date.addingTimeInterval(86_400)
    }
}

public enum CountdownCalculator {
    public static func daysRemaining(until target: Date, from now: Date = Date(), calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: now)
        let end = calendar.startOfDay(for: target)
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    public static func label(until target: Date, from now: Date = Date(), calendar: Calendar = .current) -> String {
        let days = daysRemaining(until: target, from: now, calendar: calendar)
        return switch days {
        case ..<0: "已过期 \(-days) 天"
        case 0: "今天"
        case 1: "明天"
        default: "还有 \(days) 天"
        }
    }
}
