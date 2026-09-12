import Foundation

public enum StatusBarOverviewKind: String, CaseIterable, Sendable {
    case countdown
    case mission
    case todayTasks
}

public struct StatusBarOverviewState: Equatable, Sendable {
    public var showCountdown: Bool
    public var showMissionProgress: Bool
    public var showTodayTasks: Bool
    public var selectedMissionID: UUID?

    public init(
        showCountdown: Bool,
        showMissionProgress: Bool,
        showTodayTasks: Bool,
        selectedMissionID: UUID? = nil
    ) {
        self.showCountdown = showCountdown
        self.showMissionProgress = showMissionProgress
        self.showTodayTasks = showTodayTasks
        self.selectedMissionID = selectedMissionID
    }

    public static let legacyCountdownOnly = StatusBarOverviewState(
        showCountdown: true,
        showMissionProgress: false,
        showTodayTasks: false,
        selectedMissionID: nil
    )

    public var enabledKinds: [StatusBarOverviewKind] {
        var kinds: [StatusBarOverviewKind] = []
        if showCountdown { kinds.append(.countdown) }
        if showMissionProgress { kinds.append(.mission) }
        if showTodayTasks { kinds.append(.todayTasks) }
        return kinds
    }

    /// Missing keys mean a pre-1.0.7 user: keep only the countdown item.
    public static func migrated(
        countdown: Bool?,
        mission: Bool?,
        tasks: Bool?,
        selectedMissionID: UUID?
    ) -> StatusBarOverviewState {
        if countdown == nil, mission == nil, tasks == nil {
            return StatusBarOverviewState(
                showCountdown: true,
                showMissionProgress: false,
                showTodayTasks: false,
                selectedMissionID: selectedMissionID
            )
        }
        return StatusBarOverviewState(
            showCountdown: countdown ?? false,
            showMissionProgress: mission ?? false,
            showTodayTasks: tasks ?? false,
            selectedMissionID: selectedMissionID
        )
    }
}

public enum StatusBarItemRegistry {
    public static func reconcile(
        desired: Set<StatusBarOverviewKind>,
        existingCounts: [StatusBarOverviewKind: Int]
    ) -> (create: [StatusBarOverviewKind], remove: [StatusBarOverviewKind: Int]) {
        var create: [StatusBarOverviewKind] = []
        var remove: [StatusBarOverviewKind: Int] = [:]
        for kind in StatusBarOverviewKind.allCases {
            let have = max(0, existingCounts[kind, default: 0])
            let want = desired.contains(kind) ? 1 : 0
            if have < want {
                create.append(kind)
            } else if have > want {
                remove[kind] = have - want
            }
        }
        return (create, remove)
    }
}

public enum StatusBarTodaySemantics {
    public static func isRemainingToday(
        status: TaskOccurrenceStatus,
        plannedDue: Date?,
        plannedStart: Date?,
        isOverdue: Bool,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        guard status == .open else { return false }
        guard plannedDue != nil || plannedStart != nil else { return false }
        if let plannedDue {
            return calendar.isDate(plannedDue, inSameDayAs: now) || isOverdue
        }
        if let plannedStart {
            return calendar.isDate(plannedStart, inSameDayAs: now)
        }
        return false
    }

    public static func remainingCount(
        views: [TaskOccurrenceView],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        views.filter { view in
            isRemainingToday(
                status: view.occurrence.status,
                plannedDue: view.occurrence.plannedDue,
                plannedStart: view.occurrence.plannedStart,
                isOverdue: view.occurrence.isOverdue(now: now),
                now: now,
                calendar: calendar
            )
        }.count
    }
}

public enum StatusBarMissionPresentation {
    public static func resolvedID(
        _ selected: UUID?,
        among missions: [MissionDefinition]
    ) -> UUID? {
        MissionSelection.resolvedID(selected, among: missions)
    }

    public static func percentText(progress: Double?) -> String {
        guard let progress else { return "—" }
        return "\(Int((progress * 100).rounded()))%"
    }
}

/// Monochrome menu-bar mission glyph. Colors stay on mission cards/editors only.
public struct StatusBarMissionArtworkSpec: Equatable, Sendable {
    public enum Style: String, Equatable, Sendable {
        case waterOrb
        case progressRing
    }

    public var style: Style
    public var fillRatio: Double
    public var side: Double
    public var lineWidth: Double

    public static let menuBarSides: [Double] = [18, 20, 22]
    public static let menuBarDefaultSide: Double = 20
    public static let minimumWaterReadableSide: Double = 18

    public init(style: Style, fillRatio: Double, side: Double, lineWidth: Double) {
        self.style = style
        self.fillRatio = fillRatio
        self.side = side
        self.lineWidth = lineWidth
    }

    public static func make(progress: Double?, side: Double = menuBarDefaultSide) -> StatusBarMissionArtworkSpec {
        let clampedSide = max(1, side)
        let fill = clampedFill(progress)
        let lineWidth = max(1.25, min(2, clampedSide * 0.1))
        let style: Style = clampedSide + 0.001 >= minimumWaterReadableSide ? .waterOrb : .progressRing
        return StatusBarMissionArtworkSpec(
            style: style,
            fillRatio: fill,
            side: clampedSide,
            lineWidth: lineWidth
        )
    }

    public static func clampedFill(_ progress: Double?) -> Double {
        guard let progress else { return 0 }
        return min(1, max(0, progress))
    }

    public var usesTemplateRendering: Bool { true }
    public var usesMissionColor: Bool { false }

    public var contentInset: Double { lineWidth }

    public var innerSide: Double { max(0, side - contentInset * 2) }

    /// Bottom-origin water column inside the circular container.
    public var waterFillHeight: Double { innerSide * fillRatio }

    public var waterRect: (x: Double, y: Double, width: Double, height: Double) {
        (
            x: contentInset,
            y: contentInset,
            width: innerSide,
            height: waterFillHeight
        )
    }

    /// Ring sweep, starting at the top and moving clockwise.
    public var ringSweepDegrees: Double { fillRatio * 360 }
}
