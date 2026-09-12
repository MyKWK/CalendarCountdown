import Foundation

/// Resolves UI selection after a mission is deleted or missing.
public enum MissionSelection: Sendable {
    public static func resolvedID(
        _ selected: UUID?,
        among missions: [MissionDefinition]
    ) -> UUID? {
        guard let selected else { return nil }
        return missions.contains(where: { $0.id == selected && $0.deletedAt == nil })
            ? selected
            : nil
    }

    public static func featured(among missions: [MissionDefinition]) -> MissionDefinition? {
        missions.first(where: { $0.status == .active && $0.deletedAt == nil })
            ?? missions.first(where: { $0.deletedAt == nil })
    }

    public static func resolvedRoute(
        _ route: AppRoute?,
        among missions: [MissionDefinition]
    ) -> AppRoute? {
        guard let route else { return nil }
        if case let .mission(id) = route, resolvedID(id, among: missions) == nil {
            return .section(.missions)
        }
        return route
    }
}
