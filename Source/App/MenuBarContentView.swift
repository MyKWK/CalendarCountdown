import AppKit
import CalendarCountdownCore
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var appearanceSettings: AppAppearanceSettings
    let openMainWindow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("置顶与最近倒数").font(.headline)
                Spacer()
                Button {
                    Task { await model.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
            }

            if model.selectedEvents.isEmpty {
                Text("尚未选择倒数事件")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 18)
            } else {
                ForEach(menuEvents) { event in
                    HStack(spacing: 8) {
                        Image(systemName: model.isPinned(event) ? "pin.fill" : "circle.fill")
                            .font(.system(size: model.isPinned(event) ? 9 : 7))
                            .foregroundStyle(model.isPinned(event) ? .orange : Color(hex: event.colorHex))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(event.title).lineLimit(1)
                            Text(event.eventDate, format: .dateTime.year().month().day())
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(CountdownCalculator.label(until: event.eventDate))
                            .font(.callout.monospacedDigit())
                    }
                }
            }

            Divider()
            HStack {
                Button("打开日历倒数", action: openMainWindow)
                Spacer()
                Button("退出") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 340)
        .tint(appearanceSettings.accentColor)
        .preferredColorScheme(appearanceSettings.appearanceMode.colorScheme)
    }

    private var menuEvents: [CountdownEvent] {
        guard let featured = model.featuredEvent else {
            return Array(model.selectedEvents.prefix(10))
        }
        return Array(([featured] + model.selectedEvents.filter { $0.id != featured.id }).prefix(10))
    }
}
