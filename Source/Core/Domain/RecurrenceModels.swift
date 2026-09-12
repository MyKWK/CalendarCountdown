import Foundation

public enum RecurrenceMode: String, Codable, CaseIterable, Sendable {
    case fixedSchedule
    case afterCompletion
}

public enum RecurrenceFrequency: String, Codable, CaseIterable, Sendable {
    case daily
    case weekly
    case monthly
    case yearly
}

public enum RecurrenceEnd: Equatable, Sendable {
    case never
    case afterOccurrences(Int)
    case onDate(LocalDate)
}

public enum InvalidDatePolicy: String, Codable, CaseIterable, Sendable {
    case clampToMonthEnd
    case skip
}

public struct RecurrenceHorizon: Equatable, Sendable {
    public var minimumFutureCount: Int
    public var minimumFutureDays: Int

    public init(minimumFutureCount: Int = 10, minimumFutureDays: Int = 30) {
        self.minimumFutureCount = minimumFutureCount
        self.minimumFutureDays = minimumFutureDays
    }

    public static let `default` = RecurrenceHorizon()
}

public struct RecurrenceSpec: Equatable, Codable, Sendable {
    public var mode: RecurrenceMode
    public var frequency: RecurrenceFrequency
    public var interval: Int
    public var weekdays: [Weekday]?
    public var monthDays: [Int]?
    public var months: [Int]?
    public var setPositions: [Int]?
    public var end: RecurrenceEnd
    public var timeZoneIdentifier: String
    public var firstWeekday: Weekday
    public var invalidDatePolicy: InvalidDatePolicy

    public init(
        mode: RecurrenceMode,
        frequency: RecurrenceFrequency,
        interval: Int = 1,
        weekdays: [Weekday]? = nil,
        monthDays: [Int]? = nil,
        months: [Int]? = nil,
        setPositions: [Int]? = nil,
        end: RecurrenceEnd = .never,
        timeZoneIdentifier: String,
        firstWeekday: Weekday = .monday,
        invalidDatePolicy: InvalidDatePolicy = .clampToMonthEnd
    ) {
        self.mode = mode
        self.frequency = frequency
        self.interval = interval
        self.weekdays = weekdays
        self.monthDays = monthDays
        self.months = months
        self.setPositions = setPositions
        self.end = end
        self.timeZoneIdentifier = timeZoneIdentifier
        self.firstWeekday = firstWeekday
        self.invalidDatePolicy = invalidDatePolicy
    }

    public var isInfinite: Bool {
        if case .never = end { return true }
        return false
    }

    public var plannedCount: Int? {
        switch end {
        case .never:
            nil
        case let .afterOccurrences(count):
            count
        case .onDate:
            nil
        }
    }

    public func validated() throws -> RecurrenceSpec {
        var copy = self
        copy.weekdays = weekdays.map { Array(Set($0)).sorted() }
        copy.monthDays = monthDays.map { Array(Set($0)).sorted() }
        copy.months = months.map { Array(Set($0)).sorted() }
        copy.setPositions = setPositions.map { Array(Set($0)).sorted() }

        guard copy.interval >= 1 else {
            throw DomainError.validation("循环间隔必须大于或等于 1。")
        }
        guard TimeZone(identifier: copy.timeZoneIdentifier) != nil else {
            throw DomainError.validation(
                "无效的 IANA 时区：\(copy.timeZoneIdentifier)。",
                details: ["timeZone": copy.timeZoneIdentifier]
            )
        }
        if let monthDays = copy.monthDays, !monthDays.allSatisfy({ (1...31).contains($0) }) {
            throw DomainError.validation("monthDays 必须在 1 到 31 之间。")
        }
        if let months = copy.months, !months.allSatisfy({ (1...12).contains($0) }) {
            throw DomainError.validation("months 必须在 1 到 12 之间。")
        }
        if let positions = copy.setPositions, positions.contains(where: { $0 == 0 || abs($0) > 5 }) {
            throw DomainError.validation("setPositions 必须是非 0 且绝对值不超过 5 的整数。")
        }
        switch copy.end {
        case .never:
            break
        case let .afterOccurrences(count):
            guard count >= 1 else {
                throw DomainError.validation("循环次数必须大于或等于 1。")
            }
        case let .onDate(date):
            guard let timeZone = TimeZone(identifier: copy.timeZoneIdentifier),
                  date.isRepresentable(in: timeZone)
            else {
                throw DomainError.validation("循环结束日期无效：\(date.isoString)。")
            }
        }
        return copy
    }
}

extension RecurrenceEnd: Codable {
    private enum Kind: String, Codable {
        case never
        case afterOccurrences
        case onDate
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case count
        case date
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .never:
            self = .never
        case .afterOccurrences:
            self = .afterOccurrences(try container.decode(Int.self, forKey: .count))
        case .onDate:
            self = .onDate(try container.decode(LocalDate.self, forKey: .date))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .never:
            try container.encode(Kind.never, forKey: .kind)
        case let .afterOccurrences(count):
            try container.encode(Kind.afterOccurrences, forKey: .kind)
            try container.encode(count, forKey: .count)
        case let .onDate(date):
            try container.encode(Kind.onDate, forKey: .kind)
            try container.encode(date, forKey: .date)
        }
    }
}

public enum RecurrenceRuleCodec {
    public static func rrule(from spec: RecurrenceSpec) -> String {
        var parts = [
            "FREQ=\(spec.frequency.rawValue.uppercased())",
            "INTERVAL=\(spec.interval)"
        ]
        if let weekdays = spec.weekdays, !weekdays.isEmpty {
            parts.append("BYDAY=" + weekdays.map(\.rruleToken).joined(separator: ","))
        }
        if let monthDays = spec.monthDays, !monthDays.isEmpty {
            parts.append("BYMONTHDAY=" + monthDays.map(String.init).joined(separator: ","))
        }
        if let months = spec.months, !months.isEmpty {
            parts.append("BYMONTH=" + months.map(String.init).joined(separator: ","))
        }
        if let positions = spec.setPositions, !positions.isEmpty {
            parts.append("BYSETPOS=" + positions.map(String.init).joined(separator: ","))
        }
        switch spec.end {
        case .never:
            break
        case let .afterOccurrences(count):
            parts.append("COUNT=\(count)")
        case let .onDate(date):
            parts.append("UNTIL=\(date.isoString.replacingOccurrences(of: "-", with: ""))")
        }
        if spec.mode == .afterCompletion {
            parts.append("X-CC-MODE=AFTER-COMPLETION")
        }
        return parts.joined(separator: ";")
    }

    public static func spec(
        from rrule: String,
        timeZoneIdentifier: String,
        firstWeekday: Weekday = .monday,
        invalidDatePolicy: InvalidDatePolicy = .clampToMonthEnd
    ) throws -> RecurrenceSpec {
        var frequency: RecurrenceFrequency?
        var interval = 1
        var weekdays: [Weekday]?
        var monthDays: [Int]?
        var months: [Int]?
        var setPositions: [Int]?
        var end = RecurrenceEnd.never
        var mode = RecurrenceMode.fixedSchedule

        for piece in rrule.split(separator: ";") {
            let parts = piece.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let key = parts[0].uppercased()
            let value = parts[1]
            switch key {
            case "FREQ":
                frequency = RecurrenceFrequency(rawValue: value.lowercased())
            case "INTERVAL":
                interval = Int(value) ?? 1
            case "BYDAY":
                weekdays = value.split(separator: ",").compactMap { Weekday.from(rruleToken: String($0)) }
            case "BYMONTHDAY":
                monthDays = value.split(separator: ",").compactMap { Int($0) }
            case "BYMONTH":
                months = value.split(separator: ",").compactMap { Int($0) }
            case "BYSETPOS":
                setPositions = value.split(separator: ",").compactMap { Int($0) }
            case "COUNT":
                if let count = Int(value) {
                    end = .afterOccurrences(count)
                }
            case "UNTIL":
                let digits = value.filter(\.isNumber)
                if digits.count >= 8,
                   let date = LocalDate.parse(
                    "\(digits.prefix(4))-\(digits.dropFirst(4).prefix(2))-\(digits.dropFirst(6).prefix(2))"
                   ) {
                    end = .onDate(date)
                }
            case "X-CC-MODE":
                if value.uppercased() == "AFTER-COMPLETION" {
                    mode = .afterCompletion
                }
            default:
                break
            }
        }

        guard let frequency else {
            throw DomainError.validation("RRULE 缺少 FREQ。", details: ["rrule": rrule])
        }
        return try RecurrenceSpec(
            mode: mode,
            frequency: frequency,
            interval: interval,
            weekdays: weekdays,
            monthDays: monthDays,
            months: months,
            setPositions: setPositions,
            end: end,
            timeZoneIdentifier: timeZoneIdentifier,
            firstWeekday: firstWeekday,
            invalidDatePolicy: invalidDatePolicy
        ).validated()
    }
}
