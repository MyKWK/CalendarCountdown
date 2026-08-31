import CalendarCountdownCore
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
                    title: "张三",
                    eventDate: Calendar.current.date(byAdding: .day, value: 5, to: Date()) ?? Date(),
                    colorHex: "#EC4899",
                    calendarTitle: "生日"
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
        let refreshDate = snapshot.items.isEmpty
            ? now.addingTimeInterval(60)
            : DateSupport.nextMidnight(after: now)
        let entry = CountdownWidgetEntry(date: now, snapshot: snapshot)
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }
}

struct CalendarCountdownWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CountdownWidgetEntry

    var body: some View {
        Group {
            if entry.snapshot.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.title)
                    Text("尚未选择倒数事件")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary)
            } else if family == .systemSmall {
                smallView(entry.snapshot.items[0])
            } else {
                listView
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "calendarcountdown://open"))
    }

    private func smallView(_ item: WidgetSnapshotItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Circle()
                .fill(WidgetColor.hex(item.colorHex))
                .frame(width: 9, height: 9)
            Text(item.title)
                .font(.headline)
                .lineLimit(2)
            Spacer()
            Text(CountdownCalculator.label(until: item.eventDate, from: entry.date))
                .font(.title2.bold().monospacedDigit())
                .minimumScaleFactor(0.7)
            Text(item.eventDate, format: .dateTime.month().day())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var listView: some View {
        let limit = family == .systemLarge ? 8 : 3
        return VStack(alignment: .leading, spacing: family == .systemLarge ? 10 : 7) {
            HStack {
                Label("最近倒数", systemImage: "calendar.badge.clock")
                    .font(.headline)
                Spacer()
                Text(entry.snapshot.generatedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ForEach(entry.snapshot.items.prefix(limit)) { item in
                HStack(spacing: 8) {
                    Circle()
                        .fill(WidgetColor.hex(item.colorHex))
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title).lineLimit(1)
                        Text(item.calendarTitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(CountdownCalculator.label(until: item.eventDate, from: entry.date))
                        .font(.callout.bold().monospacedDigit())
                }
            }
            Spacer(minLength: 0)
        }
    }
}

private enum WidgetColor {
    static func hex(_ value: String) -> Color {
        let cleaned = value.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let number = UInt64(cleaned, radix: 16) ?? 0x8E8E93
        return Color(
            red: Double((number >> 16) & 0xFF) / 255,
            green: Double((number >> 8) & 0xFF) / 255,
            blue: Double(number & 0xFF) / 255
        )
    }
}

struct CalendarCountdownWidget: Widget {
    let kind = ProductConstants.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CountdownTimelineProvider()) { entry in
            CalendarCountdownWidgetView(entry: entry)
        }
        .configurationDisplayName("日历倒数")
        .description("显示你从 Apple 日历中选中的下一批倒数事件。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct CalendarCountdownWidgetBundle: WidgetBundle {
    var body: some Widget {
        CalendarCountdownWidget()
    }
}
