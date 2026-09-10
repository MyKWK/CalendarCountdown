#if canImport(CalendarCountdownCore)
import CalendarCountdownCore
#endif
import SwiftUI
import WidgetKit

struct CountdownWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct CountdownTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> CountdownWidgetEntry {
        CountdownWidgetEntry(
            date: Date(),
            snapshot: WidgetSnapshot(items: [
                WidgetSnapshotItem(
                    id: "preview",
                    title: AppLocalization.text("widget.preview_title", defaultValue: "示例生日"),
                    eventDate: Calendar.current.date(byAdding: .day, value: 5, to: Date()) ?? Date(),
                    colorHex: "#EC4899",
                    calendarTitle: AppLocalization.text("widget.preview_calendar", defaultValue: "生日")
                )
            ])
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (CountdownWidgetEntry) -> Void) {
        completion(CountdownWidgetEntry(date: Date(), snapshot: WidgetSnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CountdownWidgetEntry>) -> Void) {
        let snapshot = WidgetSnapshotStore.load()
        let now = Date()
        let refreshDate = snapshot.items.isEmpty ? now.addingTimeInterval(60) : DateSupport.nextMidnight(after: now)
        completion(Timeline(entries: [CountdownWidgetEntry(date: now, snapshot: snapshot)], policy: .after(refreshDate)))
    }
}

struct CalendarCountdowniOSWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CountdownWidgetEntry

    var body: some View {
        Group {
            if entry.snapshot.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "calendar.badge.clock")
                    Text("尚未选择倒数事件")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary)
            } else if family == .systemSmall {
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.snapshot.items[0].title).font(.headline).lineLimit(2)
                    Spacer()
                    Text(CountdownCalculator.label(until: entry.snapshot.items[0].eventDate, from: entry.date))
                        .font(.title2.bold().monospacedDigit())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Label("最近倒数", systemImage: "calendar.badge.clock").font(.headline)
                    ForEach(entry.snapshot.items.prefix(family == .systemExtraLarge ? 8 : 3)) { item in
                        HStack {
                            Text(item.title).lineLimit(1)
                            Spacer()
                            Text(CountdownCalculator.label(until: item.eventDate, from: entry.date))
                                .font(.callout.bold().monospacedDigit())
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "calendarcountdown://open"))
    }
}

struct CalendarCountdowniOSWidget: Widget {
    let kind = ProductConstants.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CountdownTimelineProvider()) { entry in
            CalendarCountdowniOSWidgetView(entry: entry)
        }
        .configurationDisplayName("日历倒数")
        .description("显示你从 Apple 日历中选中的下一批倒数事件。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}

@main
struct CalendarCountdowniOSWidgetBundle: WidgetBundle {
    var body: some Widget {
        CalendarCountdowniOSWidget()
    }
}
