import Foundation

/// A calendar date without a time-of-day. Encoded as `YYYY-MM-DD`.
public struct LocalDate: Hashable, Sendable, Comparable, Codable, CustomStringConvertible {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public var isoString: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public var description: String { isoString }

    public static func parse(_ value: String) -> LocalDate? {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              (1...9999).contains(year),
              (1...12).contains(month),
              (1...31).contains(day)
        else {
            return nil
        }
        return LocalDate(year: year, month: month, day: day)
    }

    public static func from(_ date: Date, timeZone: TimeZone) -> LocalDate {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return LocalDate(
            year: components.year ?? 0,
            month: components.month ?? 0,
            day: components.day ?? 0
        )
    }

    public func startOfDay(in timeZone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    public func isRepresentable(in timeZone: TimeZone) -> Bool {
        guard let date = startOfDay(in: timeZone) else { return false }
        return LocalDate.from(date, timeZone: timeZone) == self
    }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        if lhs.month != rhs.month { return lhs.month < rhs.month }
        return lhs.day < rhs.day
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let parsed = LocalDate.parse(raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "LocalDate must be YYYY-MM-DD, got \(raw)"
            )
        }
        self = parsed
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(isoString)
    }
}

public enum RFC3339 {
    public static func utcString(from date: Date) -> String {
        makeFormatter(fractional: false).string(from: date)
    }

    public static func parse(_ value: String) -> Date? {
        if let date = makeFormatter(fractional: false).date(from: value) {
            return date
        }
        return makeFormatter(fractional: true).date(from: value)
    }

    public static func parseRequired(_ value: String) throws -> Date {
        guard let date = parse(value) else {
            throw DomainError.validation(
                "无效的 RFC 3339 时间：\(value)。",
                details: ["value": value]
            )
        }
        return date
    }

    private static func makeFormatter(fractional: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = fractional
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return formatter
    }
}

/// Hybrid Logical Clock used for field-level merge ordering.
public struct HybridLogicalTimestamp: Hashable, Sendable, Comparable, Codable {
    public var wallTimeMicros: Int64
    public var logical: UInt32
    public var deviceID: UUID

    public init(wallTimeMicros: Int64, logical: UInt32, deviceID: UUID) {
        self.wallTimeMicros = wallTimeMicros
        self.logical = logical
        self.deviceID = deviceID
    }

    public static func now(deviceID: UUID, at date: Date = Date()) -> HybridLogicalTimestamp {
        HybridLogicalTimestamp(
            wallTimeMicros: micros(from: date),
            logical: 0,
            deviceID: deviceID
        )
    }

    public func incremented(at date: Date = Date(), deviceID: UUID) -> HybridLogicalTimestamp {
        let current = Self.micros(from: date)
        if current > wallTimeMicros {
            return HybridLogicalTimestamp(wallTimeMicros: current, logical: 0, deviceID: deviceID)
        }
        return HybridLogicalTimestamp(
            wallTimeMicros: wallTimeMicros,
            logical: logical &+ 1,
            deviceID: deviceID
        )
    }

    public func receive(
        _ remote: HybridLogicalTimestamp,
        at date: Date = Date(),
        deviceID: UUID
    ) -> HybridLogicalTimestamp {
        let localWall = Self.micros(from: date)
        let maxWall = max(localWall, max(wallTimeMicros, remote.wallTimeMicros))
        if maxWall == localWall && localWall > wallTimeMicros && localWall > remote.wallTimeMicros {
            return HybridLogicalTimestamp(wallTimeMicros: localWall, logical: 0, deviceID: deviceID)
        }
        let nextLogical: UInt32
        if maxWall == wallTimeMicros && maxWall == remote.wallTimeMicros {
            nextLogical = max(logical, remote.logical) &+ 1
        } else if maxWall == wallTimeMicros {
            nextLogical = logical &+ 1
        } else if maxWall == remote.wallTimeMicros {
            nextLogical = remote.logical &+ 1
        } else {
            nextLogical = 0
        }
        return HybridLogicalTimestamp(
            wallTimeMicros: maxWall,
            logical: nextLogical,
            deviceID: deviceID
        )
    }

    public var wireValue: String {
        "\(wallTimeMicros):\(logical):\(deviceID.uuidString.lowercased())"
    }

    public static func parse(_ value: String) -> HybridLogicalTimestamp? {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let wall = Int64(parts[0]),
              let logical = UInt32(parts[1]),
              let deviceID = UUID(uuidString: String(parts[2]))
        else {
            return nil
        }
        return HybridLogicalTimestamp(wallTimeMicros: wall, logical: logical, deviceID: deviceID)
    }

    public static func < (lhs: HybridLogicalTimestamp, rhs: HybridLogicalTimestamp) -> Bool {
        if lhs.wallTimeMicros != rhs.wallTimeMicros {
            return lhs.wallTimeMicros < rhs.wallTimeMicros
        }
        if lhs.logical != rhs.logical {
            return lhs.logical < rhs.logical
        }
        return lhs.deviceID.uuidString.lowercased() < rhs.deviceID.uuidString.lowercased()
    }

    private static func micros(from date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000_000).rounded(.down))
    }
}

public enum Weekday: Int, Codable, CaseIterable, Sendable, Comparable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7

    public var rruleToken: String {
        switch self {
        case .sunday: "SU"
        case .monday: "MO"
        case .tuesday: "TU"
        case .wednesday: "WE"
        case .thursday: "TH"
        case .friday: "FR"
        case .saturday: "SA"
        }
    }

    public static func from(rruleToken: String) -> Weekday? {
        switch rruleToken.uppercased() {
        case "SU": .sunday
        case "MO": .monday
        case "TU": .tuesday
        case "WE": .wednesday
        case "TH": .thursday
        case "FR": .friday
        case "SA": .saturday
        default: nil
        }
    }

    public static func from(calendarWeekday: Int) -> Weekday? {
        Weekday(rawValue: calendarWeekday)
    }

    public static func < (lhs: Weekday, rhs: Weekday) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
