import AppKit
import CalendarCountdownCore
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var workspace: WorkspaceModel
    @ObservedObject var appearanceSettings: AppAppearanceSettings
    let openMainWindow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("今天 · 任务 \(workspace.openTasks.count)")
                    .font(ZhixingTypography.cardTitle)
                    .zhixingForeground(.heading)
                Spacer()
                Button {
                    Task { await model.refresh() }
                    workspace.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .appActionFocusEffectDisabled()
            }

            if !workspace.todayTasks.isEmpty {
                ForEach(workspace.todayTasks.prefix(3)) { view in
                    HStack {
                        Button {
                            workspace.complete(view)
                        } label: {
                            Image(systemName: "circle")
                        }
                        .buttonStyle(.plain)
                        .appActionFocusEffectDisabled()
                        Text(view.title)
                            .zhixingForeground(.body)
                            .lineLimit(1)
                        Spacer()
                    }
                }
                Divider()
            }

            Text("置顶与最近倒数")
                .font(ZhixingTypography.rowTitle)
                .zhixingForeground(.heading)

            if model.accessState != .fullAccess {
                CalendarAccessActions(model: model)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else if model.selectedEvents.isEmpty {
                Text("尚未选择倒数事件")
                    .zhixingForeground(.supporting)
                    .padding(.vertical, 8)
            } else {
                ForEach(menuEvents) { event in
                    HStack(spacing: 8) {
                        Image(systemName: model.isPinned(event) ? "pin.fill" : "circle.fill")
                            .font(.system(size: model.isPinned(event) ? 9 : 7))
                            .foregroundStyle(model.isPinned(event) ? .orange : Color(hex: event.colorHex))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(event.title)
                                .zhixingForeground(.body)
                                .lineLimit(1)
                            Text(event.eventDate, format: .dateTime.year().month().day())
                                .font(.caption2)
                                .zhixingForeground(.supporting)
                        }
                        Spacer()
                        Text(CountdownCalculator.label(until: event.eventDate))
                            .font(.callout.monospacedDigit())
                            .zhixingForeground(.body)
                    }
                }
            }

            if !workspace.missions.isEmpty {
                Divider()
                Text(AppLocalization.text("menubar.missions", defaultValue: "使命"))
                    .font(ZhixingTypography.rowTitle)
                    .zhixingForeground(.heading)
                ForEach(workspace.missions.prefix(3), id: \.mission.id) { item in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.missionIdentity(item.mission.color))
                            .frame(width: 10, height: 10)
                            .accessibilityLabel(MissionColor.resolve(item.mission.color).title)
                        Image(systemName: MissionSymbolCatalog.resolved(item.mission.icon))
                            .foregroundStyle(Color.missionIdentity(item.mission.color))
                            .accessibilityHidden(true)
                        Text(item.mission.title)
                            .zhixingForeground(.body)
                            .lineLimit(1)
                        Spacer()
                        if let percent = item.progress.displayPercent {
                            Text(String(format: "%.0f%%", percent))
                                .font(.caption.monospacedDigit())
                                .zhixingForeground(.supporting)
                        }
                    }
                    .accessibilityIdentifier("menubar-mission-\(item.mission.id.uuidString)")
                }
            }

            Divider()
            HStack {
                Button("打开日历倒数", action: openMainWindow)
                    .appActionFocusEffectDisabled()
                Spacer()
                Button("退出") { NSApplication.shared.terminate(nil) }
                    .appActionFocusEffectDisabled()
            }
        }
        .padding(14)
        .frame(width: 340)
        .tint(appearanceSettings.accentColor)
        .preferredColorScheme(appearanceSettings.appearanceMode.colorScheme)
        .appSurfaceTransparency(appearanceSettings.windowGlassTransparency)
        .onAppear { workspace.reload() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.recoverAuthorization() }
        }
    }

    private var menuEvents: [CountdownEvent] {
        guard let featured = model.featuredEvent else {
            return Array(model.selectedEvents.prefix(10))
        }
        return Array(([featured] + model.selectedEvents.filter { $0.id != featured.id }).prefix(10))
    }
}
