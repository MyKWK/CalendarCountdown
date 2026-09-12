#if os(macOS)
import AppKit
import CalendarCountdownCore
import Combine
import SwiftUI

@MainActor
final class StatusBarOverviewSettings: ObservableObject {
    enum Keys {
        static let countdown = "statusBar.overview.countdown.enabled"
        static let mission = "statusBar.overview.mission.enabled"
        static let tasks = "statusBar.overview.todayTasks.enabled"
        static let selectedMission = "statusBar.overview.selectedMissionID"
    }

    private let defaults: UserDefaults

    @Published var showCountdown: Bool {
        didSet { defaults.set(showCountdown, forKey: Keys.countdown) }
    }

    @Published var showMissionProgress: Bool {
        didSet { defaults.set(showMissionProgress, forKey: Keys.mission) }
    }

    @Published var showTodayTasks: Bool {
        didSet { defaults.set(showTodayTasks, forKey: Keys.tasks) }
    }

    @Published var selectedMissionID: UUID? {
        didSet {
            if let selectedMissionID {
                defaults.set(selectedMissionID.uuidString, forKey: Keys.selectedMission)
            } else {
                defaults.removeObject(forKey: Keys.selectedMission)
            }
        }
    }

    var state: StatusBarOverviewState {
        StatusBarOverviewState(
            showCountdown: showCountdown,
            showMissionProgress: showMissionProgress,
            showTodayTasks: showTodayTasks,
            selectedMissionID: selectedMissionID
        )
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedID = defaults.string(forKey: Keys.selectedMission).flatMap(UUID.init(uuidString:))
        let migrated = StatusBarOverviewState.migrated(
            countdown: defaults.object(forKey: Keys.countdown) == nil
                ? nil
                : defaults.bool(forKey: Keys.countdown),
            mission: defaults.object(forKey: Keys.mission) == nil
                ? nil
                : defaults.bool(forKey: Keys.mission),
            tasks: defaults.object(forKey: Keys.tasks) == nil
                ? nil
                : defaults.bool(forKey: Keys.tasks),
            selectedMissionID: storedID
        )
        showCountdown = migrated.showCountdown
        showMissionProgress = migrated.showMissionProgress
        showTodayTasks = migrated.showTodayTasks
        selectedMissionID = migrated.selectedMissionID
        defaults.set(showCountdown, forKey: Keys.countdown)
        defaults.set(showMissionProgress, forKey: Keys.mission)
        defaults.set(showTodayTasks, forKey: Keys.tasks)
    }

    func resolveSelectedMission(among missions: [MissionDefinition]) {
        let resolved = StatusBarMissionPresentation.resolvedID(selectedMissionID, among: missions)
        if resolved != selectedMissionID {
            selectedMissionID = resolved
        }
    }
}
#endif
