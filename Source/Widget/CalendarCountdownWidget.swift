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
                    title: AppLocalization.text(
                        "widget.preview_title",
                        defaultValue: "示例生日"
                    ),
                    eventDate: Calendar.current.date(byAdding: .day, value: 5, to: Date()) ?? Date(),
                    colorHex: "#EC4899",
                    calendarTitle: AppLocalization.text(
                        "widget.preview_calendar",
                        defaultValue: "生日"
                    )
                )
            ])
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (CountdownWidgetEntry) -> Void) {
        let snapshot = WidgetSnapshotStore.load()
        DiagnosticLogger.shared.log(
            .debug,
            category: .widget,
            event: "widget.countdown_snapshot.loaded",
            metadata: ["item_count": String(snapshot.items.count)]
        )
        completion(CountdownWidgetEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CountdownWidgetEntry>) -> Void) {
        let snapshot = WidgetSnapshotStore.load()
        let now = Date()
        let refreshDate = snapshot.items.isEmpty
            ? now.addingTimeInterval(60)
            : DateSupport.nextMidnight(after: now)
        let entry = CountdownWidgetEntry(date: now, snapshot: snapshot)
        DiagnosticLogger.shared.log(
            .info,
            category: .widget,
            event: "widget.countdown_timeline.created",
            metadata: [
                "item_count": String(snapshot.items.count),
                "refresh_reason": snapshot.items.isEmpty ? "empty_retry" : "next_midnight"
            ]
        )
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
        .supportedFamilies(Self.supportedFamilies)
    }

    private static var supportedFamilies: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge]
        #else
        [.systemSmall, .systemMedium, .systemLarge]
        #endif
    }
}

@main
struct CalendarCountdownWidgetBundle: WidgetBundle {
    init() {
        DiagnosticLogger.shared.configure(component: "widget")
        DiagnosticLogger.shared.log(.info, category: .lifecycle, event: "widget.process.started")
    }

    var body: some Widget {
        CalendarCountdownWidget()
        TasksWidget()
        MissionsWidget()
        HabitsWidget()
    }
}

enum WidgetFamilySupport {
    static var countdown: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge]
        #else
        [.systemSmall, .systemMedium, .systemLarge]
        #endif
    }

    static var domain: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge]
        #else
        [.systemSmall, .systemMedium]
        #endif
    }
}

struct DomainWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshotV2
}

struct DomainTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> DomainWidgetEntry {
        DomainWidgetEntry(date: Date(), snapshot: WidgetSnapshotV2())
    }

    func getSnapshot(in context: Context, completion: @escaping (DomainWidgetEntry) -> Void) {
        let snapshot = WidgetSnapshotV2.load()
        DiagnosticLogger.shared.log(
            .debug,
            category: .widget,
            event: "widget.domain_snapshot.loaded",
            metadata: [
                "tasks": String(snapshot.tasks.count),
                "missions": String(snapshot.missions.count),
                "habits": String(snapshot.habits.count)
            ]
        )
        completion(DomainWidgetEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DomainWidgetEntry>) -> Void) {
        let snapshot = WidgetSnapshotV2.load()
        DiagnosticLogger.shared.log(
            .info,
            category: .widget,
            event: "widget.domain_timeline.created",
            metadata: [
                "tasks": String(snapshot.tasks.count),
                "missions": String(snapshot.missions.count),
                "habits": String(snapshot.habits.count)
            ]
        )
        completion(Timeline(entries: [DomainWidgetEntry(date: Date(), snapshot: snapshot)], policy: .after(Date().addingTimeInterval(300))))
    }
}

struct TasksWidget: Widget {
    let kind = ProductConstants.taskWidgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DomainTimelineProvider()) { entry in
            VStack(alignment: .leading, spacing: 6) {
                Label("今日任务", systemImage: "checkmark.circle")
                    .font(.headline)
                if entry.snapshot.tasks.isEmpty {
                    Text("没有待办").foregroundStyle(.secondary)
                } else {
                    ForEach(entry.snapshot.tasks.prefix(5)) { task in
                        HStack {
                            Text(task.title).lineLimit(1)
                            Spacer()
                            if task.isOverdue {
                                Text("逾期").foregroundStyle(.red)
                            }
                        }
                        .font(.caption)
                    }
                }
                Spacer(minLength: 0)
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("今日任务")
        .description("显示尚未完成的任务。")
        .supportedFamilies(WidgetFamilySupport.domain)
    }
}

struct MissionsWidget: Widget {
    let kind = ProductConstants.missionWidgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DomainTimelineProvider()) { entry in
            VStack(alignment: .leading, spacing: 8) {
                Label("使命进度", systemImage: "flag.fill")
                    .font(.headline)
                if entry.snapshot.missions.isEmpty {
                    Text("尚未规划").foregroundStyle(.secondary)
                } else {
                    ForEach(entry.snapshot.missions.prefix(3)) { mission in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mission.title).lineLimit(1)
                            ProgressView(value: mission.progress ?? 0)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("使命进度")
        .description("显示使命完成百分比。")
        .supportedFamilies(WidgetFamilySupport.domain)
    }
}

struct HabitsWidget: Widget {
    let kind = ProductConstants.habitWidgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DomainTimelineProvider()) { entry in
            VStack(alignment: .leading, spacing: 6) {
                Label("今日习惯", systemImage: "flame.fill")
                    .font(.headline)
                if entry.snapshot.habits.isEmpty {
                    Text("还没有习惯").foregroundStyle(.secondary)
                } else {
                    ForEach(entry.snapshot.habits.prefix(5)) { habit in
                        HStack {
                            Text(habit.title).lineLimit(1)
                            Spacer()
                            Text("连续 \(habit.currentStreak)")
                                .monospacedDigit()
                        }
                        .font(.caption)
                    }
                }
                Spacer(minLength: 0)
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("今日习惯")
        .description("显示习惯连续达标。")
        .supportedFamilies(WidgetFamilySupport.domain)
    }
}
