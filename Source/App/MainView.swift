import CalendarCountdownCore
import SwiftUI
import UniformTypeIdentifiers

struct MainView: View {
    @ObservedObject var model: AppModel
    let openAppearanceSettings: () -> Void
    @State private var selectedCalendarID: String? = "__countdown__"
    @State private var searchText = ""
    @State private var showingAddEvent = false
    @State private var showingImporter = false
    @State private var showingExporter = false

    var body: some View {
        Group {
            if model.accessState != .fullAccess {
                permissionView
            } else {
                content
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    showingImporter = true
                } label: {
                    Label("导入", systemImage: "square.and.arrow.down")
                }
                .disabled(model.accessState != .fullAccess)

                Button {
                    showingExporter = true
                } label: {
                    Label("导出追踪清单", systemImage: "square.and.arrow.up")
                }
                .disabled(model.trackedEventsDocument.events.isEmpty)

                Button {
                    showingAddEvent = true
                } label: {
                    Label("录入重要日", systemImage: "calendar.badge.plus")
                }
                .disabled(model.writableCalendars.isEmpty)

                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .disabled(model.isLoading)

                Button {
                    openAppearanceSettings()
                } label: {
                    Label("外观设置", systemImage: "paintpalette")
                }
            }
        }
        .searchable(text: $searchText, prompt: "搜索日历事件")
        .sheet(isPresented: $showingAddEvent) {
            AddEventView(calendars: model.writableCalendars) { draft in
                await model.add(draft)
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                if let url = urls.first { Task { await model.importDocument(at: url) } }
            case let .failure(error):
                model.errorMessage = error.localizedDescription
            }
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: TrackedEventsFileDocument(document: model.trackedEventsDocument),
            contentType: .json,
            defaultFilename: "CalendarCountdown-tracked-events-\(DateSupport.dateOnlyString(Date()))"
        ) { result in
            switch result {
            case .success:
                model.statusMessage = "当前追踪的重要日已导出"
            case let .failure(error):
                model.errorMessage = error.localizedDescription
            }
        }
        .alert("操作失败", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "未知错误")
        }
        .overlay(alignment: .bottom) {
            if let message = model.statusMessage {
                Text(message)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding()
                    .task {
                        try? await Task.sleep(for: .seconds(3))
                        if model.statusMessage == message { model.statusMessage = nil }
                    }
            }
        }
    }

    private var permissionView: some View {
        ContentUnavailableView {
            Label("需要访问 Apple 日历", systemImage: "calendar.badge.exclamationmark")
        } description: {
            Text("日历倒数读取现有日历分类和事件；只有在你明确新建或导入时才会写入选定日历。")
        } actions: {
            Button("授权日历访问") {
                Task { await model.requestAccess() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isLoading)
        }
    }

    private var content: some View {
        NavigationSplitView {
            List(selection: $selectedCalendarID) {
                Label("倒数展示", systemImage: "star.fill")
                    .badge(model.selectedEvents.count)
                    .tag(Optional("__countdown__"))

                ForEach(groupedCalendars, id: \.key) { source, calendars in
                    Section(source) {
                        ForEach(calendars) { calendar in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color(hex: calendar.colorHex))
                                    .frame(width: 9, height: 9)
                                Text(calendar.title)
                                    .lineLimit(1)
                                Spacer()
                                if !calendar.allowsContentModifications {
                                    Image(systemName: "lock.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                CalendarTrackingButton(
                                    isTracked: model.isCalendarTracked(calendar.id)
                                ) {
                                    Task {
                                        await model.setCalendarTracked(
                                            calendar.id,
                                            tracked: !model.isCalendarTracked(calendar.id)
                                        )
                                    }
                                }
                            }
                            .opacity(model.isCalendarTracked(calendar.id) ? 1 : 0.58)
                            .tag(Optional(calendar.id))
                        }
                    }
                }
            }
            .navigationTitle("Apple 日历")
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            eventList
        }
    }

    private var eventList: some View {
        Group {
            if displayedEvents.isEmpty {
                ContentUnavailableView(
                    selectedCalendarID == "__countdown__" ? "尚未选择倒数事件" : "没有未来事件",
                    systemImage: "calendar",
                    description: Text(selectedCalendarID == "__countdown__"
                        ? "从任意 Apple 日历中选择具体事件加入倒数。"
                        : "尝试扩大时间范围或检查该日历是否包含未来事件。")
                )
            } else {
                List(displayedEvents) { event in
                    EventRow(
                        event: event,
                        isSelected: model.isSelected(event),
                        isPinned: model.isPinned(event),
                        onSelectExact: { Task { await model.select(event, mode: .exactEvent) } },
                        onSelectAnnual: { Task { await model.select(event, mode: .annualTitle) } },
                        onTogglePin: { Task { await model.togglePin(event) } },
                        onUnselect: { Task { await model.unselect(event) } }
                    )
                }
            }
        }
        .navigationTitle(selectedTitle)
    }

    private var displayedEvents: [CountdownEvent] {
        let base: [CountdownEvent]
        if selectedCalendarID == "__countdown__" {
            base = model.selectedEvents
        } else if let selectedCalendarID {
            base = CountdownSelectionStore.nextOccurrences(
                from: model.events.filter { $0.calendarIdentifier == selectedCalendarID }
            )
        } else {
            base = CountdownSelectionStore.nextOccurrences(from: model.events)
        }
        guard !searchText.isEmpty else { return base }
        return base.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.calendarTitle.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var selectedTitle: String {
        if selectedCalendarID == "__countdown__" { return "倒数展示" }
        return model.calendars.first(where: { $0.id == selectedCalendarID })?.title ?? "未来事件"
    }

    private var groupedCalendars: [(key: String, value: [CalendarSummary])] {
        Dictionary(grouping: model.calendars, by: \.sourceTitle)
            .map { ($0.key, $0.value) }
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
    }
}

private struct TrackedEventsFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let document: TrackedEventsDocument

    init(document: TrackedEventsDocument) {
        self.document = document
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        document = try JSONCoding.decoder().decode(TrackedEventsDocument.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try JSONCoding.encoder().encode(document))
    }
}

private struct CalendarTrackingButton: View {
    let isTracked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(isTracked ? "不追踪" : "追踪", systemImage: isTracked ? "eye.slash" : "eye")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
        }
        .buttonStyle(.borderless)
        .fixedSize()
        .help(isTracked
            ? "不再在倒数展示、顶部菜单栏和小组件中显示这个类别"
            : "在倒数展示、顶部菜单栏和小组件中追踪这个类别")
    }
}

private struct EventRow: View {
    let event: CountdownEvent
    let isSelected: Bool
    let isPinned: Bool
    let onSelectExact: () -> Void
    let onSelectAnnual: () -> Void
    let onTogglePin: () -> Void
    let onUnselect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: event.colorHex))
                .frame(width: 5, height: 42)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title).font(.headline)
                HStack(spacing: 6) {
                    Text(event.eventDate, format: .dateTime.year().month().day())
                    Text("·")
                    Text(event.calendarTitle)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(CountdownCalculator.label(until: event.eventDate))
                .font(.headline.monospacedDigit())
            Button(action: onTogglePin) {
                Image(systemName: isPinned ? "star.fill" : "star")
                    .font(.title3)
                    .foregroundStyle(isPinned ? .yellow : .secondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!isSelected)
            .help(isSelected
                ? (isPinned ? "取消置顶" : "置顶到顶部菜单栏")
                : "请先追踪这个事件，再进行置顶")
            Menu {
                if isSelected {
                    Button("不追踪这个倒数", role: .destructive, action: onUnselect)
                } else {
                    Button("只追踪这一次", action: onSelectExact)
                    Button("每年追踪该日历中的同名事件", action: onSelectAnnual)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.vertical, 5)
    }
}
