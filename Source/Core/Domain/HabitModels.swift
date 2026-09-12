import Foundation

public enum HabitMetric: String, Codable, CaseIterable, Sendable {
    case binary
    case count
    case quantity
}

public enum HabitCompletionPolicy: String, Codable, CaseIterable, Sendable {
    case reachTarget
    case manualComplete
}

public enum HabitScheduleKind: String, Codable, CaseIterable, Sendable {
    case daily
    case selectedWeekdays
    case weeklyN
    case monthlyN
    case custom
}

public struct HabitSchedule: Equatable, Codable, Sendable {
    public var kind: HabitScheduleKind
    public var weekdays: [Weekday]
    public var timesPerPeriod: Int
    public var customRule: String?

    public init(
        kind: HabitScheduleKind,
        weekdays: [Weekday] = [],
        timesPerPeriod: Int = 1,
        customRule: String? = nil
    ) {
        self.kind = kind
        self.weekdays = weekdays
        self.timesPerPeriod = timesPerPeriod
        self.customRule = customRule
    }

    public static var daily: HabitSchedule {
        HabitSchedule(kind: .daily)
    }

    public func validated() throws -> HabitSchedule {
        var copy = self
        copy.weekdays = Array(Set(weekdays)).sorted()
        switch copy.kind {
        case .selectedWeekdays:
            guard !copy.weekdays.isEmpty else {
                throw DomainError.validation("按星期打卡至少选择一天。")
            }
        case .weeklyN, .monthlyN:
            guard copy.timesPerPeriod >= 1 else {
                throw DomainError.validation("周期目标次数必须大于或等于 1。")
            }
        case .custom:
            guard !(copy.customRule?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) else {
                throw DomainError.validation("自定义习惯规则不能为空。")
            }
        case .daily:
            break
        }
        return copy
    }
}

public enum HabitPeriodDisposition: String, Codable, CaseIterable, Sendable {
    case open
    case completed
    case skipped
}

public enum CheckInSource: String, Codable, CaseIterable, Sendable {
    case app
    case cli
    case mcp
    case appleCompletion
    case importBundle
    case system
}

public struct HabitDefinition: Equatable, Codable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var markdownDescription: String?
    public var metric: HabitMetric
    public var targetValue: Decimal
    public var unit: String?
    public var schedule: HabitSchedule
    public var activeFrom: LocalDate
    public var activeUntil: LocalDate?
    public var reminderTimes: [String]
    public var allowBackfillDays: Int
    public var completionPolicy: HabitCompletionPolicy
    public var projectionPolicy: ProjectionPolicy
    public var missionID: UUID?
    public var createdAt: Date
    public var updatedAt: Date
    public var revision: Int64
    public var modifiedByDevice: UUID
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        markdownDescription: String? = nil,
        metric: HabitMetric,
        targetValue: Decimal = 1,
        unit: String? = nil,
        schedule: HabitSchedule = .daily,
        activeFrom: LocalDate,
        activeUntil: LocalDate? = nil,
        reminderTimes: [String] = [],
        allowBackfillDays: Int = 1,
        completionPolicy: HabitCompletionPolicy = .reachTarget,
        projectionPolicy: ProjectionPolicy = .none,
        missionID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        revision: Int64 = 1,
        modifiedByDevice: UUID,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.markdownDescription = markdownDescription
        self.metric = metric
        self.targetValue = targetValue
        self.unit = unit
        self.schedule = schedule
        self.activeFrom = activeFrom
        self.activeUntil = activeUntil
        self.reminderTimes = reminderTimes
        self.allowBackfillDays = allowBackfillDays
        self.completionPolicy = completionPolicy
        self.projectionPolicy = projectionPolicy
        self.missionID = missionID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.revision = revision
        self.modifiedByDevice = modifiedByDevice
        self.deletedAt = deletedAt
    }

    public var defaultIncrement: Decimal {
        switch metric {
        case .binary: 1
        case .count: 1
        case .quantity: targetValue
        }
    }

    public func validated() throws -> HabitDefinition {
        var copy = self
        copy.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.markdownDescription = markdownDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.unit = unit?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !copy.title.isEmpty else {
            throw DomainError.validation("习惯标题不能为空。")
        }
        guard copy.targetValue > 0 else {
            throw DomainError.validation("习惯目标必须大于 0。")
        }
        if copy.metric == .binary {
            copy.targetValue = 1
            copy.unit = nil
        }
        copy.schedule = try copy.schedule.validated()
        if let until = copy.activeUntil, until < copy.activeFrom {
            throw DomainError.validation("习惯结束日期不能早于开始日期。")
        }
        guard (0...366).contains(copy.allowBackfillDays) else {
            throw DomainError.validation("补打天数必须在 0 到 366 之间。")
        }
        for time in copy.reminderTimes {
            guard DateSupport.parseTime(time) != nil else {
                throw DomainError.validation("无效的提醒时间：\(time)。")
            }
        }
        return copy
    }
}

public struct HabitPeriod: Equatable, Codable, Sendable {
    public var habitID: UUID
    public var periodKey: String
    public var targetValueSnapshot: Decimal
    public var disposition: HabitPeriodDisposition
    public var completedAt: Date?
    public var updatedAt: Date
    public var revision: Int64
    public var modifiedByDevice: UUID
    public var deletedAt: Date?

    public init(
        habitID: UUID,
        periodKey: String,
        targetValueSnapshot: Decimal,
        disposition: HabitPeriodDisposition = .open,
        completedAt: Date? = nil,
        updatedAt: Date = Date(),
        revision: Int64 = 1,
        modifiedByDevice: UUID,
        deletedAt: Date? = nil
    ) {
        self.habitID = habitID
        self.periodKey = periodKey
        self.targetValueSnapshot = targetValueSnapshot
        self.disposition = disposition
        self.completedAt = completedAt
        self.updatedAt = updatedAt
        self.revision = revision
        self.modifiedByDevice = modifiedByDevice
        self.deletedAt = deletedAt
    }
}

public struct CheckInRecord: Equatable, Codable, Identifiable, Sendable {
    public var id: UUID
    public var habitID: UUID
    public var periodKey: String
    public var value: Decimal
    public var unit: String?
    public var effectiveAt: Date
    public var recordedAt: Date
    public var source: CheckInSource
    public var note: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var revision: Int64
    public var modifiedByDevice: UUID
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        habitID: UUID,
        periodKey: String,
        value: Decimal,
        unit: String? = nil,
        effectiveAt: Date,
        recordedAt: Date = Date(),
        source: CheckInSource = .app,
        note: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        revision: Int64 = 1,
        modifiedByDevice: UUID,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.habitID = habitID
        self.periodKey = periodKey
        self.value = value
        self.unit = unit
        self.effectiveAt = effectiveAt
        self.recordedAt = recordedAt
        self.source = source
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.revision = revision
        self.modifiedByDevice = modifiedByDevice
        self.deletedAt = deletedAt
    }
}

public struct HabitStats: Equatable, Codable, Sendable {
    public var currentStreak: Int
    public var longestStreak: Int
    public var weekCompletionRate: Double?
    public var monthCompletionRate: Double?
    public var totalValue: Decimal
    public var averageValue: Decimal
    public var heatMap: [String: Decimal]

    public init(
        currentStreak: Int,
        longestStreak: Int,
        weekCompletionRate: Double?,
        monthCompletionRate: Double?,
        totalValue: Decimal,
        averageValue: Decimal,
        heatMap: [String: Decimal]
    ) {
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.weekCompletionRate = weekCompletionRate
        self.monthCompletionRate = monthCompletionRate
        self.totalValue = totalValue
        self.averageValue = averageValue
        self.heatMap = heatMap
    }
}

public struct HabitPeriodEvaluation: Equatable, Sendable {
    public var periodKey: String
    public var target: Decimal
    public var actual: Decimal
    public var isRestDay: Bool
    public var isSkipped: Bool
    public var isSuccess: Bool
    public var isFailure: Bool
}

public enum HabitStatisticsEngine {
    public static func periodKey(
        for date: Date,
        schedule: HabitSchedule,
        timeZone: TimeZone
    ) -> String? {
        let local = LocalDate.from(date, timeZone: timeZone)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4

        switch schedule.kind {
        case .daily:
            return local.isoString
        case .selectedWeekdays:
            guard let weekday = Weekday.from(calendarWeekday: calendar.component(.weekday, from: date)),
                  schedule.weekdays.contains(weekday)
            else {
                return nil
            }
            return local.isoString
        case .weeklyN, .custom:
            let week = calendar.component(.weekOfYear, from: date)
            let year = calendar.component(.yearForWeekOfYear, from: date)
            return String(format: "%04d-W%02d", year, week)
        case .monthlyN:
            return String(format: "%04d-%02d", local.year, local.month)
        }
    }

    public static func isRestDay(
        date: Date,
        schedule: HabitSchedule,
        timeZone: TimeZone
    ) -> Bool {
        periodKey(for: date, schedule: schedule, timeZone: timeZone) == nil
    }

    public static func expectedPeriodKeys(
        from start: LocalDate,
        to end: LocalDate,
        schedule: HabitSchedule,
        timeZone: TimeZone
    ) -> [String] {
        guard let startDate = start.startOfDay(in: timeZone),
              let endDate = end.startOfDay(in: timeZone),
              startDate <= endDate
        else {
            return []
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var keys: [String] = []
        var seen = Set<String>()
        var cursor = startDate
        while cursor <= endDate {
            if let key = periodKey(for: cursor, schedule: schedule, timeZone: timeZone),
               seen.insert(key).inserted {
                keys.append(key)
            }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor.addingTimeInterval(86_400)
        }
        return keys
    }

    public static func evaluate(
        habit: HabitDefinition,
        periodKey: String,
        checkIns: [CheckInRecord],
        period: HabitPeriod?,
        timeZone: TimeZone
    ) -> HabitPeriodEvaluation {
        let liveCheckIns = checkIns.filter { $0.deletedAt == nil && $0.periodKey == periodKey }
        let actual = liveCheckIns.reduce(Decimal(0)) { $0 + $1.value }
        let target = period?.targetValueSnapshot ?? habit.targetValue
        let skipped = period?.disposition == .skipped
        let reached = actual >= target
        let success: Bool
        switch habit.completionPolicy {
        case .reachTarget:
            success = skipped ? false : (period?.disposition == .completed || reached)
        case .manualComplete:
            success = period?.disposition == .completed
        }
        return HabitPeriodEvaluation(
            periodKey: periodKey,
            target: target,
            actual: actual,
            isRestDay: false,
            isSkipped: skipped,
            isSuccess: success && !skipped,
            isFailure: !success && !skipped
        )
    }

    public static func remainingToTarget(target: Decimal, actual: Decimal) -> Decimal {
        max(0, target - actual)
    }

    public static func stats(
        habit: HabitDefinition,
        periods: [HabitPeriodEvaluation],
        checkIns: [CheckInRecord],
        now: Date,
        timeZone: TimeZone
    ) -> HabitStats {
        let ordered = periods.filter { !$0.isRestDay }
        let (current, longest) = streaks(from: ordered)
        let localNow = LocalDate.from(now, timeZone: timeZone)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? now
        let weekKeys = Set(
            expectedPeriodKeys(
                from: LocalDate.from(weekStart, timeZone: timeZone),
                to: localNow,
                schedule: habit.schedule,
                timeZone: timeZone
            )
        )
        let monthKeys = Set(
            expectedPeriodKeys(
                from: LocalDate.from(monthStart, timeZone: timeZone),
                to: localNow,
                schedule: habit.schedule,
                timeZone: timeZone
            )
        )

        func rate(for keys: Set<String>) -> Double? {
            let relevant = ordered.filter { keys.contains($0.periodKey) && !$0.isSkipped }
            guard !relevant.isEmpty else { return nil }
            let success = relevant.filter(\.isSuccess).count
            return Double(success) / Double(relevant.count)
        }

        let live = checkIns.filter { $0.deletedAt == nil }
        let total = live.reduce(Decimal(0)) { $0 + $1.value }
        let average: Decimal
        if live.isEmpty {
            average = 0
        } else {
            average = total / Decimal(live.count)
        }
        var heat: [String: Decimal] = [:]
        for item in live {
            heat[item.periodKey, default: 0] += item.value
        }

        return HabitStats(
            currentStreak: current,
            longestStreak: longest,
            weekCompletionRate: rate(for: weekKeys),
            monthCompletionRate: rate(for: monthKeys),
            totalValue: total,
            averageValue: average,
            heatMap: heat
        )
    }

    public static func streaks(from periods: [HabitPeriodEvaluation]) -> (current: Int, longest: Int) {
        let countable = periods.filter { !$0.isRestDay && !$0.isSkipped }
        var longest = 0
        var run = 0
        for period in countable {
            if period.isSuccess {
                run += 1
                longest = max(longest, run)
            } else {
                run = 0
            }
        }
        var current = 0
        for period in countable.reversed() {
            if period.isSuccess {
                current += 1
            } else {
                break
            }
        }
        return (current, longest)
    }
}
