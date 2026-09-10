#if canImport(CalendarCountdownCore)
import CalendarCountdownCore
#endif
import SwiftUI

struct ModuleHost<Content: View>: View {
    let section: AppSection
    @ViewBuilder var content: () -> Content

    var body: some View {
        NavigationStack {
            content()
        }
    }
}

struct AppSectionSidebar: View {
    @Binding var selection: AppSection
    let countdownCount: Int
    let taskCount: Int
    let missionCount: Int
    let habitCount: Int

    var body: some View {
        List(AppSection.allCases, id: \.self, selection: $selection) { section in
            Label(section.title, systemImage: section.systemImage)
                .badge(badge(for: section))
                .tag(section)
                .accessibilityIdentifier("tab-\(section.rawValue)")
        }
        .navigationTitle("日历倒数")
    }

    private func badge(for section: AppSection) -> Int {
        switch section {
        case .countdown: countdownCount
        case .tasks: taskCount
        case .missions: missionCount
        case .habits: habitCount
        }
    }
}
