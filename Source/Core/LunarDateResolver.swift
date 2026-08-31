import Foundation

public enum LunarDateResolver {
    public static func dates(
        month: Int,
        day: Int,
        leapMonthPolicy: LunarLeapMonthPolicy,
        invalidDayPolicy: InvalidLunarDayPolicy,
        inGregorianYear year: Int,
        timeZone: TimeZone = .current
    ) -> [Date] {
        let leapFlags: [Bool]
        switch leapMonthPolicy {
        case .regularOnly: leapFlags = [false]
        case .leapOnly: leapFlags = [true]
        case .both: leapFlags = [false, true]
        }

        return leapFlags.flatMap { leap in
            resolveAll(
                month: month,
                day: day,
                isLeapMonth: leap,
                invalidDayPolicy: invalidDayPolicy,
                inGregorianYear: year,
                timeZone: timeZone
            )
        }.sorted()
    }

    private static func resolveAll(
        month: Int,
        day: Int,
        isLeapMonth: Bool,
        invalidDayPolicy: InvalidLunarDayPolicy,
        inGregorianYear year: Int,
        timeZone: TimeZone
    ) -> [Date] {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = timeZone
        var chinese = Calendar(identifier: .chinese)
        chinese.timeZone = timeZone

        guard let start = gregorian.date(from: DateComponents(year: year, month: 1, day: 1)),
              let end = gregorian.date(from: DateComponents(year: year + 1, month: 1, day: 1)) else {
            return []
        }

        var cursor = start
        var candidatesByLunarYear: [Int: (highestDay: Int, lastDate: Date, exactDate: Date?)] = [:]

        while cursor < end {
            let components = chinese.dateComponents([.year, .month, .day, .isLeapMonth], from: cursor)
            let leapMatches = (components.isLeapMonth ?? false) == isLeapMonth
            if components.month == month,
               leapMatches,
               let lunarYear = components.year,
               let candidateDay = components.day {
                var candidate = candidatesByLunarYear[lunarYear]
                    ?? (highestDay: 0, lastDate: cursor, exactDate: nil)
                if candidateDay == day {
                    candidate.exactDate = gregorian.startOfDay(for: cursor)
                }
                if candidateDay > candidate.highestDay {
                    candidate.highestDay = candidateDay
                    candidate.lastDate = cursor
                }
                candidatesByLunarYear[lunarYear] = candidate
            }
            guard let next = gregorian.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        return candidatesByLunarYear.values.compactMap { candidate in
            if let exactDate = candidate.exactDate { return exactDate }
            guard invalidDayPolicy == .clampToMonthEnd, candidate.highestDay < day else { return nil }
            return gregorian.startOfDay(for: candidate.lastDate)
        }.sorted()
    }
}
