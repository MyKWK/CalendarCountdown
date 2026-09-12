import Foundation

public struct ProjectedNativeItem: Equatable, Sendable {
    public var url: String
    public var kind: ProjectionKind
    public var appleIdentifier: String
    public var title: String
    public var completed: Bool
    public var due: Date?

    public init(
        url: String,
        kind: ProjectionKind,
        appleIdentifier: String,
        title: String,
        completed: Bool,
        due: Date? = nil
    ) {
        self.url = url
        self.kind = kind
        self.appleIdentifier = appleIdentifier
        self.title = title
        self.completed = completed
        self.due = due
    }
}

public enum NativeReverseAction: Equatable, Sendable {
    case complete(occurrenceID: UUID)
    case reopen(occurrenceID: UUID)
    case checkInHabit(habitID: UUID)
    case undoHabitCheckIn(habitID: UUID)
    case completeMission(missionID: UUID)
    case reopenMission(missionID: UUID)
}

public struct ProjectionPlanItem: Equatable, Sendable {
    public var desired: DesiredProjection
    public var existing: ProjectedNativeItem?
    public var classification: ReconciliationClassification

    public init(
        desired: DesiredProjection,
        existing: ProjectedNativeItem?,
        classification: ReconciliationClassification
    ) {
        self.desired = desired
        self.existing = existing
        self.classification = classification
    }
}

public enum ProjectionReconciler {
    public static func plan(
        desired: [DesiredProjection],
        native: [ProjectedNativeItem]
    ) -> [ProjectionPlanItem] {
        desired.map { item in
            let matches = native.filter { $0.url == item.url && $0.kind == item.projectionKind }
            if matches.count > 1 {
                return ProjectionPlanItem(desired: item, existing: survivor(matches), classification: .conflict)
            }
            if let existing = matches.first {
                let drifted = existing.title != item.title
                    || existing.completed != item.completed
                    || existing.due != item.due
                return ProjectionPlanItem(
                    desired: item,
                    existing: existing,
                    classification: drifted ? .projectionDrift : .projectedCoreChange
                )
            }
            return ProjectionPlanItem(desired: item, existing: nil, classification: .missingProjection)
        }
    }

    public static func reverseActions(
        desired: [DesiredProjection],
        native: [ProjectedNativeItem],
        acceptNativeCompletion: Bool
    ) -> [NativeReverseAction] {
        guard acceptNativeCompletion else { return [] }
        var actions: [NativeReverseAction] = []
        for item in desired where item.projectionKind == .reminder {
            guard let nativeItem = native.first(where: { $0.url == item.url && $0.kind == .reminder }) else {
                continue
            }
            let completedOnApple = nativeItem.completed && !item.completed
            let reopenedOnApple = !nativeItem.completed && item.completed
            guard completedOnApple || reopenedOnApple else { continue }
            switch item.domainType {
            case "habit":
                actions.append(completedOnApple ? .checkInHabit(habitID: item.domainID) : .undoHabitCheckIn(habitID: item.domainID))
            case "mission":
                actions.append(completedOnApple ? .completeMission(missionID: item.domainID) : .reopenMission(missionID: item.domainID))
            default:
                actions.append(completedOnApple ? .complete(occurrenceID: item.domainID) : .reopen(occurrenceID: item.domainID))
            }
        }
        return actions
    }

    public static func survivor(_ items: [ProjectedNativeItem]) -> ProjectedNativeItem? {
        items.sorted { lhs, rhs in
            lhs.appleIdentifier < rhs.appleIdentifier
        }.first
    }
}

public final class InMemoryProjectionStore: @unchecked Sendable {
    public private(set) var items: [ProjectedNativeItem] = []

    public init(items: [ProjectedNativeItem] = []) {
        self.items = items
    }

    public func upsert(_ desired: DesiredProjection) -> ProjectedNativeItem {
        if let index = items.firstIndex(where: { $0.url == desired.url && $0.kind == desired.projectionKind }) {
            items[index].title = desired.title
            items[index].completed = desired.completed
            items[index].due = desired.due
            return items[index]
        }
        let created = ProjectedNativeItem(
            url: desired.url,
            kind: desired.projectionKind,
            appleIdentifier: UUID().uuidString.lowercased(),
            title: desired.title,
            completed: desired.completed,
            due: desired.due
        )
        items.append(created)
        return created
    }

    public func complete(url: String) {
        if let index = items.firstIndex(where: { $0.url == url }) {
            items[index].completed = true
        }
    }

    public func remove(url: String, kind: ProjectionKind) {
        items.removeAll { $0.url == url && $0.kind == kind }
    }
}

extension InMemoryProjectionStore: ProjectionApplying {
    public func nativeItems() async throws -> [ProjectedNativeItem] {
        items
    }

    public func apply(_ desired: DesiredProjection) async throws -> String {
        upsert(desired).appleIdentifier
    }

    public func remove(url: String, kind: ProjectionKind) async throws {
        items.removeAll { $0.url == url && $0.kind == kind }
    }
}
