import Foundation

public enum MissionStatus: String, Codable, CaseIterable, Sendable {
    case draft
    case active
    case paused
    case completed
    case archived
}

public struct MissionDefinition: Equatable, Codable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var markdownDescription: String?
    public var color: String
    public var icon: String
    public var status: MissionStatus
    public var targetDate: LocalDate?
    public var defaultWorkload: WorkloadPoints
    public var sortKey: String
    public var createdAt: Date
    public var updatedAt: Date
    public var revision: Int64
    public var modifiedByDevice: UUID
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        markdownDescription: String? = nil,
        color: String = "#5B8DEF",
        icon: String = "flag.fill",
        status: MissionStatus = .active,
        targetDate: LocalDate? = nil,
        defaultWorkload: WorkloadPoints = .one,
        sortKey: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        revision: Int64 = 1,
        modifiedByDevice: UUID,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.markdownDescription = markdownDescription
        self.color = color
        self.icon = icon
        self.status = status
        self.targetDate = targetDate
        self.defaultWorkload = defaultWorkload
        self.sortKey = sortKey
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.revision = revision
        self.modifiedByDevice = modifiedByDevice
        self.deletedAt = deletedAt
    }

    public func validated() throws -> MissionDefinition {
        var copy = self
        copy.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.markdownDescription = markdownDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.color = color.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.icon = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !copy.title.isEmpty else {
            throw DomainError.validation("使命标题不能为空。")
        }
        if copy.sortKey.isEmpty {
            copy.sortKey = RFC3339.utcString(from: copy.createdAt) + copy.id.uuidString.lowercased()
        }
        return copy
    }
}

public struct OccurrenceContribution: Equatable, Sendable {
    public var seriesID: UUID
    public var occurrenceID: UUID
    public var title: String
    public var workload: WorkloadPoints
    public var status: TaskOccurrenceStatus
    public var isFinitePlan: Bool
    public var includeInProgress: Bool
    public var exclusionReason: String?

    public init(
        seriesID: UUID,
        occurrenceID: UUID,
        title: String,
        workload: WorkloadPoints,
        status: TaskOccurrenceStatus,
        isFinitePlan: Bool,
        includeInProgress: Bool,
        exclusionReason: String? = nil
    ) {
        self.seriesID = seriesID
        self.occurrenceID = occurrenceID
        self.title = title
        self.workload = workload
        self.status = status
        self.isFinitePlan = isFinitePlan
        self.includeInProgress = includeInProgress
        self.exclusionReason = exclusionReason
    }
}

public struct ContinuitySnapshot: Equatable, Codable, Sendable {
    public var windowDays: Int
    public var expectedCount: Int
    public var completedCount: Int
    public var currentStreak: Int
    public var label: String?

    public init(
        windowDays: Int = 30,
        expectedCount: Int,
        completedCount: Int,
        currentStreak: Int,
        label: String? = nil
    ) {
        self.windowDays = windowDays
        self.expectedCount = expectedCount
        self.completedCount = completedCount
        self.currentStreak = currentStreak
        self.label = label
    }

    public var rate: Double? {
        guard expectedCount > 0 else { return nil }
        return Double(completedCount) / Double(expectedCount)
    }
}

public struct MissionContributionRow: Equatable, Codable, Sendable {
    public var seriesID: UUID
    public var occurrenceID: UUID?
    public var title: String
    public var workload: Int
    public var status: String
    public var countsTowardProgress: Bool
    public var reasonIfExcluded: String?

    public init(
        seriesID: UUID,
        occurrenceID: UUID? = nil,
        title: String,
        workload: Int,
        status: String,
        countsTowardProgress: Bool,
        reasonIfExcluded: String? = nil
    ) {
        self.seriesID = seriesID
        self.occurrenceID = occurrenceID
        self.title = title
        self.workload = workload
        self.status = status
        self.countsTowardProgress = countsTowardProgress
        self.reasonIfExcluded = reasonIfExcluded
    }
}

public struct DilutionExplanation: Equatable, Codable, Sendable {
    public var previousDone: Int
    public var previousTotal: Int
    public var currentDone: Int
    public var currentTotal: Int

    public var previousRatio: Double? {
        guard previousTotal > 0 else { return nil }
        return Double(previousDone) / Double(previousTotal)
    }

    public var currentRatio: Double? {
        guard currentTotal > 0 else { return nil }
        return Double(currentDone) / Double(currentTotal)
    }
}

public struct MissionProgressBreakdown: Equatable, Codable, Sendable {
    public var totalPoints: Int
    public var donePoints: Int
    public var openPoints: Int
    public var progress: Double?
    public var excludedInfiniteSeriesCount: Int
    public var contributions: [MissionContributionRow]
    public var dilution: DilutionExplanation?
    public var continuity: ContinuitySnapshot?

    public var isUnplanned: Bool { totalPoints == 0 }

    public var displayPercent: Double? {
        progress.map { ($0 * 1000).rounded() / 10 }
    }
}

public enum ProgressCalculator {
    public static func breakdown(
        from contributions: [OccurrenceContribution],
        previous: (done: Int, total: Int)? = nil,
        continuity: ContinuitySnapshot? = nil
    ) -> MissionProgressBreakdown {
        var total = 0
        var done = 0
        var open = 0
        var infiniteSeries = Set<UUID>()
        var rows: [MissionContributionRow] = []

        for item in contributions {
            if !item.isFinitePlan {
                infiniteSeries.insert(item.seriesID)
            }
            let points = item.workload.rawValue
            if item.includeInProgress {
                total += points
                if item.status.countsAsDone {
                    done += points
                } else if item.status == .open {
                    open += points
                }
            }
            rows.append(
                MissionContributionRow(
                    seriesID: item.seriesID,
                    occurrenceID: item.occurrenceID,
                    title: item.title,
                    workload: points,
                    status: item.status.rawValue,
                    countsTowardProgress: item.includeInProgress,
                    reasonIfExcluded: item.exclusionReason
                )
            )
        }

        let progress: Double?
        if total == 0 {
            progress = nil
        } else {
            progress = min(1, max(0, Double(done) / Double(total)))
        }

        let dilution = previous.map {
            DilutionExplanation(
                previousDone: $0.done,
                previousTotal: $0.total,
                currentDone: done,
                currentTotal: total
            )
        }

        return MissionProgressBreakdown(
            totalPoints: total,
            donePoints: done,
            openPoints: open,
            progress: progress,
            excludedInfiniteSeriesCount: infiniteSeries.count,
            contributions: rows,
            dilution: dilution,
            continuity: continuity
        )
    }

    public static func contribution(
        series: TaskSeries,
        occurrence: TaskOccurrence
    ) -> OccurrenceContribution {
        let finite = !series.isInfinite
        let includeInProgress = finite
            && occurrence.disposition != .excludedFromProgress
            && occurrence.deletedAt == nil
            && series.deletedAt == nil
        let reason: String?
        if series.isInfinite {
            reason = "无限循环不进入成果进度分母，只计入持续性。"
        } else if occurrence.disposition == .excludedFromProgress {
            reason = "已从使命统计中排除。"
        } else if includeInProgress {
            reason = nil
        } else {
            reason = "未纳入进度。"
        }
        return OccurrenceContribution(
            seriesID: series.id,
            occurrenceID: occurrence.id,
            title: occurrence.displayTitle(seriesTitle: series.title),
            workload: series.workload,
            status: occurrence.status,
            isFinitePlan: finite,
            includeInProgress: includeInProgress,
            exclusionReason: reason
        )
    }
}
