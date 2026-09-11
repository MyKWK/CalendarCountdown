import Foundation

public struct PlannedOccurrenceDraft: Equatable, Sendable {
    public var occurrenceKey: String
    public var plannedStart: Date?
    public var plannedDue: Date

    public init(occurrenceKey: String, plannedStart: Date?, plannedDue: Date) {
        self.occurrenceKey = occurrenceKey
        self.plannedStart = plannedStart
        self.plannedDue = plannedDue
    }
}

public enum RecurrenceEngine {
    public static func occurrenceKey(seriesID: UUID, plannedDue: Date) -> String {
        "\(seriesID.uuidString.lowercased())@\(RFC3339.utcString(from: plannedDue))"
    }

    public static func undatedOccurrenceKey(seriesID: UUID) -> String {
        "\(seriesID.uuidString.lowercased())@undated"
    }

    public static func gregorianCalendar(
        timeZoneIdentifier: String,
        firstWeekday: Weekday = .monday
    ) throws -> Calendar {
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else {
            throw DomainError.validation(
                "无效的 IANA 时区：\(timeZoneIdentifier)。",
                details: ["timeZone": timeZoneIdentifier]
            )
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = firstWeekday.rawValue
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    public static func materializeFixedSchedule(
        seriesID: UUID,
        spec rawSpec: RecurrenceSpec,
        firstDue: Date,
        firstStart: Date?,
        now: Date,
        horizon: RecurrenceHorizon = .default
    ) throws -> [PlannedOccurrenceDraft] {
        let spec = try rawSpec.validated()
        let calendar = try gregorianCalendar(
            timeZoneIdentifier: spec.timeZoneIdentifier,
            firstWeekday: spec.firstWeekday
        )
        let dues = try dueDates(
            spec: spec,
            firstDue: firstDue,
            now: now,
            horizon: horizon,
            calendar: calendar
        )
        let duration = firstStart.map { firstDue.timeIntervalSince($0) }
        return dues.map { due in
            PlannedOccurrenceDraft(
                occurrenceKey: occurrenceKey(seriesID: seriesID, plannedDue: due),
                plannedStart: duration.map { due.addingTimeInterval(-$0) },
                plannedDue: due
            )
        }
    }

    public static func plannedOccurrenceCount(
        spec: RecurrenceSpec?,
        firstDue: Date?
    ) throws -> Int? {
        guard let rawSpec = spec else { return 1 }
        let spec = try rawSpec.validated()
        switch spec.end {
        case .never:
            return nil
        case let .afterOccurrences(count):
            return count
        case .onDate:
            guard let firstDue else { return nil }
            let calendar = try gregorianCalendar(
                timeZoneIdentifier: spec.timeZoneIdentifier,
                firstWeekday: spec.firstWeekday
            )
            return try dueDates(
                spec: spec,
                firstDue: firstDue,
                now: firstDue,
                horizon: RecurrenceHorizon(minimumFutureCount: 1_000, minimumFutureDays: 40_000),
                calendar: calendar
            ).count
        }
    }

    public static func nextAfterCompletion(
        spec rawSpec: RecurrenceSpec,
        completedAt: Date,
        previousDue: Date?
    ) throws -> Date? {
        let spec = try rawSpec.validated()
        let calendar = try gregorianCalendar(
            timeZoneIdentifier: spec.timeZoneIdentifier,
            firstWeekday: spec.firstWeekday
        )
        let wall = calendar.dateComponents([.hour, .minute, .second], from: previousDue ?? completedAt)
        guard var next = addInterval(
            spec.frequency,
            interval: spec.interval,
            to: completedAt,
            calendar: calendar
        ) else {
            return nil
        }
        next = applyWallClock(wall, to: next, calendar: calendar)

        if spec.frequency == .weekly, let weekdays = spec.weekdays, !weekdays.isEmpty {
            next = nextMatchingWeekday(onOrAfter: next, weekdays: weekdays, wall: wall, calendar: calendar)
        }

        if spec.frequency == .monthly || spec.frequency == .yearly {
            let referenceDay = calendar.component(.day, from: previousDue ?? completedAt)
            if let aligned = applyDayOfMonth(
                referenceDay,
                to: next,
                policy: spec.invalidDatePolicy,
                wall: wall,
                calendar: calendar
            ) {
                next = aligned
            } else if spec.invalidDatePolicy == .skip {
                next = skipForward(
                    from: next,
                    spec: spec,
                    referenceDay: referenceDay,
                    wall: wall,
                    calendar: calendar
                ) ?? next
            }
        }

        if case let .onDate(until) = spec.end {
            let local = LocalDate.from(next, timeZone: calendar.timeZone)
            if local > until {
                return nil
            }
        }
        return next
    }

    public static func dueDates(
        spec rawSpec: RecurrenceSpec,
        firstDue: Date,
        now: Date,
        horizon: RecurrenceHorizon,
        calendar: Calendar
    ) throws -> [Date] {
        let spec = try rawSpec.validated()
        let maxCount: Int?
        let untilDate: LocalDate?
        switch spec.end {
        case .never:
            maxCount = nil
            untilDate = nil
        case let .afterOccurrences(count):
            maxCount = count
            untilDate = nil
        case let .onDate(date):
            maxCount = nil
            untilDate = date
        }

        let horizonDate = calendar.date(
            byAdding: .day,
            value: horizon.minimumFutureDays,
            to: now
        ) ?? now

        var dates: [Date] = []
        var period = 0
        let maxPeriods = 20_000
        while period < maxPeriods {
            let candidates = try datesForPeriod(
                period,
                spec: spec,
                firstDue: firstDue,
                calendar: calendar
            )
            for candidate in candidates {
                if candidate < firstDue { continue }
                if let untilDate, LocalDate.from(candidate, timeZone: calendar.timeZone) > untilDate {
                    return dates
                }
                if dates.last == candidate { continue }
                dates.append(candidate)
                if let maxCount, dates.count >= maxCount {
                    return dates
                }
            }

            if maxCount == nil && untilDate == nil {
                let last = dates.last ?? firstDue
                let futureCount = dates.filter { $0 >= now }.count
                if last >= horizonDate && futureCount >= horizon.minimumFutureCount {
                    return dates
                }
            } else if let last = dates.last, let untilDate {
                if LocalDate.from(last, timeZone: calendar.timeZone) >= untilDate {
                    return dates
                }
            }
            period += 1
            if dates.isEmpty && period > 400 {
                break
            }
        }
        return dates
    }

    private static func datesForPeriod(
        _ period: Int,
        spec: RecurrenceSpec,
        firstDue: Date,
        calendar: Calendar
    ) throws -> [Date] {
        let wall = calendar.dateComponents([.hour, .minute, .second], from: firstDue)
        switch spec.frequency {
        case .daily:
            guard let date = calendar.date(
                byAdding: .day,
                value: period * spec.interval,
                to: firstDue
            ) else {
                return []
            }
            return [applyWallClock(wall, to: date, calendar: calendar)]

        case .weekly:
            return weeklyDates(
                period: period,
                spec: spec,
                firstDue: firstDue,
                wall: wall,
                calendar: calendar
            )

        case .monthly:
            return monthlyDates(
                period: period,
                spec: spec,
                firstDue: firstDue,
                wall: wall,
                calendar: calendar
            )

        case .yearly:
            return yearlyDates(
                period: period,
                spec: spec,
                firstDue: firstDue,
                wall: wall,
                calendar: calendar
            )
        }
    }

    private static func weeklyDates(
        period: Int,
        spec: RecurrenceSpec,
        firstDue: Date,
        wall: DateComponents,
        calendar: Calendar
    ) -> [Date] {
        guard period % spec.interval == 0 else { return [] }
        let weekIndex = period
        guard let weekStart = startOfWeek(
            containing: calendar.date(byAdding: .weekOfYear, value: weekIndex, to: firstDue) ?? firstDue,
            calendar: calendar
        ) else {
            return []
        }
        let weekdays = spec.weekdays?.isEmpty == false
            ? spec.weekdays!
            : [Weekday.from(calendarWeekday: calendar.component(.weekday, from: firstDue)) ?? .monday]
        return weekdays.compactMap { weekday in
            dateOnWeekday(weekday, weekStart: weekStart, wall: wall, calendar: calendar)
        }
        .sorted()
    }

    private static func monthlyDates(
        period: Int,
        spec: RecurrenceSpec,
        firstDue: Date,
        wall: DateComponents,
        calendar: Calendar
    ) -> [Date] {
        guard let monthAnchor = calendar.date(byAdding: .month, value: period * spec.interval, to: firstDue) else {
            return []
        }
        return datesInMonth(
            containing: monthAnchor,
            spec: spec,
            firstDue: firstDue,
            wall: wall,
            calendar: calendar
        )
    }

    private static func yearlyDates(
        period: Int,
        spec: RecurrenceSpec,
        firstDue: Date,
        wall: DateComponents,
        calendar: Calendar
    ) -> [Date] {
        guard let yearAnchor = calendar.date(byAdding: .year, value: period * spec.interval, to: firstDue) else {
            return []
        }
        let months = spec.months?.isEmpty == false
            ? spec.months!
            : [calendar.component(.month, from: firstDue)]
        return months.flatMap { month -> [Date] in
            var components = calendar.dateComponents([.year], from: yearAnchor)
            components.month = month
            components.day = 1
            guard let monthStart = calendar.date(from: components) else { return [] }
            return datesInMonth(
                containing: monthStart,
                spec: spec,
                firstDue: firstDue,
                wall: wall,
                calendar: calendar
            )
        }
        .sorted()
    }

    private static func datesInMonth(
        containing monthAnchor: Date,
        spec: RecurrenceSpec,
        firstDue: Date,
        wall: DateComponents,
        calendar: Calendar
    ) -> [Date] {
        if let positions = spec.setPositions, !positions.isEmpty, let weekdays = spec.weekdays, !weekdays.isEmpty {
            let matching = matchingWeekdaysInMonth(
                containing: monthAnchor,
                weekdays: weekdays,
                wall: wall,
                calendar: calendar
            )
            return positions.compactMap { position in
                if position > 0 {
                    let index = position - 1
                    return matching.indices.contains(index) ? matching[index] : nil
                }
                if position < 0 {
                    let index = matching.count + position
                    return matching.indices.contains(index) ? matching[index] : nil
                }
                return nil
            }
        }

        let days: [Int]
        if let monthDays = spec.monthDays, !monthDays.isEmpty {
            days = monthDays
        } else {
            days = [calendar.component(.day, from: firstDue)]
        }
        return days.compactMap { day in
            applyDayOfMonth(
                day,
                to: monthAnchor,
                policy: spec.invalidDatePolicy,
                wall: wall,
                calendar: calendar
            )
        }
        .sorted()
    }

    private static func matchingWeekdaysInMonth(
        containing monthAnchor: Date,
        weekdays: [Weekday],
        wall: DateComponents,
        calendar: Calendar
    ) -> [Date] {
        guard let interval = calendar.dateInterval(of: .month, for: monthAnchor) else { return [] }
        var dates: [Date] = []
        var cursor = interval.start
        while cursor < interval.end {
            if let weekday = Weekday.from(calendarWeekday: calendar.component(.weekday, from: cursor)),
               weekdays.contains(weekday) {
                dates.append(applyWallClock(wall, to: cursor, calendar: calendar))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return dates
    }

    private static func applyDayOfMonth(
        _ day: Int,
        to monthAnchor: Date,
        policy: InvalidDatePolicy,
        wall: DateComponents,
        calendar: Calendar
    ) -> Date? {
        guard let interval = calendar.dateInterval(of: .month, for: monthAnchor),
              let range = calendar.range(of: .day, in: .month, for: interval.start)
        else {
            return nil
        }
        let resolvedDay: Int
        if day <= range.count {
            resolvedDay = day
        } else if policy == .clampToMonthEnd {
            resolvedDay = range.count
        } else {
            return nil
        }
        var components = calendar.dateComponents([.year, .month], from: interval.start)
        components.day = resolvedDay
        components.hour = wall.hour ?? 0
        components.minute = wall.minute ?? 0
        components.second = wall.second ?? 0
        if let exact = calendar.date(from: components) {
            return exact
        }
        return applyWallClock(wall, to: interval.start, calendar: calendar)
    }

    private static func applyWallClock(
        _ wall: DateComponents,
        to date: Date,
        calendar: Calendar
    ) -> Date {
        let dayStart = calendar.startOfDay(for: date)
        if let exact = calendar.date(
            bySettingHour: wall.hour ?? 0,
            minute: wall.minute ?? 0,
            second: wall.second ?? 0,
            of: dayStart
        ) {
            return exact
        }
        return calendar.date(
            byAdding: DateComponents(hour: wall.hour ?? 0, minute: wall.minute ?? 0),
            to: dayStart
        ) ?? dayStart
    }

    private static func startOfWeek(containing date: Date, calendar: Calendar) -> Date? {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start
    }

    private static func dateOnWeekday(
        _ weekday: Weekday,
        weekStart: Date,
        wall: DateComponents,
        calendar: Calendar
    ) -> Date? {
        let offset = (weekday.rawValue - calendar.firstWeekday + 7) % 7
        guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: weekStart)) else {
            return nil
        }
        return applyWallClock(wall, to: day, calendar: calendar)
    }

    private static func addInterval(
        _ frequency: RecurrenceFrequency,
        interval: Int,
        to date: Date,
        calendar: Calendar
    ) -> Date? {
        switch frequency {
        case .daily:
            calendar.date(byAdding: .day, value: interval, to: date)
        case .weekly:
            calendar.date(byAdding: .weekOfYear, value: interval, to: date)
        case .monthly:
            calendar.date(byAdding: .month, value: interval, to: date)
        case .yearly:
            calendar.date(byAdding: .year, value: interval, to: date)
        }
    }

    private static func nextMatchingWeekday(
        onOrAfter date: Date,
        weekdays: [Weekday],
        wall: DateComponents,
        calendar: Calendar
    ) -> Date {
        var cursor = date
        for _ in 0..<8 {
            if let weekday = Weekday.from(calendarWeekday: calendar.component(.weekday, from: cursor)),
               weekdays.contains(weekday) {
                return applyWallClock(wall, to: cursor, calendar: calendar)
            }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor
        }
        return applyWallClock(wall, to: date, calendar: calendar)
    }

    private static func skipForward(
        from date: Date,
        spec: RecurrenceSpec,
        referenceDay: Int,
        wall: DateComponents,
        calendar: Calendar
    ) -> Date? {
        var cursor = date
        for _ in 0..<24 {
            guard let next = addInterval(spec.frequency, interval: spec.interval, to: cursor, calendar: calendar) else {
                return nil
            }
            if let aligned = applyDayOfMonth(
                referenceDay,
                to: next,
                policy: .skip,
                wall: wall,
                calendar: calendar
            ) {
                return aligned
            }
            cursor = next
        }
        return nil
    }
}
