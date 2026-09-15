import CalendarCountdownCore
import SwiftUI
import UniformTypeIdentifiers

struct MainView: View {
    @ObservedObject var model: AppModel
    let openSettings: () -> Void
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
                .appActionFocusEffectDisabled()

                Button {
                    showingExporter = true
                } label: {
                    Label("导出追踪清单", systemImage: "square.and.arrow.up")
                }
                .disabled(model.trackedEventsDocument.events.isEmpty)
                .appActionFocusEffectDisabled()

                Button {
                    showingAddEvent = true
                } label: {
                    Label("录入重要日", systemImage: "calendar.badge.plus")
                }
                .disabled(model.writableCalendars.isEmpty)
                .appActionFocusEffectDisabled()

                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .disabled(model.isLoading)
                .appActionFocusEffectDisabled()

                Button {
                    openSettings()
                } label: {
                    Label("设置", systemImage: "gearshape")
                }
                .appActionFocusEffectDisabled()
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
                model.statusMessage = AppLocalization.text(
                    "status.tracked_events_exported",
                    defaultValue: "当前追踪的重要日已导出"
                )
            case let .failure(error):
                model.errorMessage = error.localizedDescription
            }
        }
        .alert("操作失败", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { model.errorMessage = nil }
                .appActionFocusEffectDisabled()
        } message: {
            Text(model.errorMessage ?? AppLocalization.text(
                "error.unknown",
                defaultValue: "未知错误"
            ))
        }
        .overlay(alignment: .bottom) {
            if let message = model.statusMessage {
                FloatingStatusBanner(message: message)
                    .task {
                        try? await Task.sleep(for: .seconds(3))
                        if model.statusMessage == message { model.statusMessage = nil }
                    }
            }
        }
        .zhixingForeground(.body)
    }

    private var permissionView: some View {
        ContentUnavailableView {
            Label("需要访问 Apple 日历", systemImage: "calendar.badge.exclamationmark")
        } description: {
            Text("日历倒数读取现有日历分类和事件；只有在你明确新建或导入时才会写入选定日历。")
        } actions: {
            CalendarAccessActions(model: model)
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

    private var countdownEmptyTitle: String {
        if selectedCalendarID == "__countdown__", !model.selections.isEmpty {
            return AppLocalization.text(
                "empty.countdown_unresolved",
                defaultValue: "已保存的倒数选择尚未匹配到日历事件"
            )
        }
        if selectedCalendarID == "__countdown__" {
            return AppLocalization.text(
                "empty.no_countdown_events",
                defaultValue: "尚未选择倒数事件"
            )
        }
        return AppLocalization.text("empty.no_future_events", defaultValue: "没有未来事件")
    }

    private var countdownEmptyDescription: String {
        if selectedCalendarID == "__countdown__", !model.selections.isEmpty {
            return AppLocalization.text(
                "empty.countdown_unresolved_description",
                defaultValue: "选择仍保留在本机，不会被清空。授权恢复或刷新后会按稳定标识重新匹配年度和重复事件。"
            )
        }
        if selectedCalendarID == "__countdown__" {
            return AppLocalization.text(
                "empty.select_event_description",
                defaultValue: "从任意 Apple 日历中选择具体事件加入倒数。"
            )
        }
        return AppLocalization.text(
            "empty.future_events_description",
            defaultValue: "尝试扩大时间范围或检查该日历是否包含未来事件。"
        )
    }

    private var eventList: some View {
        Group {
            if displayedEvents.isEmpty {
                ContentUnavailableView(
                    countdownEmptyTitle,
                    systemImage: "calendar",
                    description: Text(countdownEmptyDescription)
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
                .appGlassScrollBackground()
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
        if selectedCalendarID == "__countdown__" {
            return AppLocalization.text("navigation.countdown", defaultValue: "倒数展示")
        }
        return model.calendars.first(where: { $0.id == selectedCalendarID })?.title
            ?? AppLocalization.text("navigation.future_events", defaultValue: "未来事件")
    }

    private var groupedCalendars: [(key: String, value: [CalendarSummary])] {
        Dictionary(grouping: model.calendars, by: \.sourceTitle)
            .map { ($0.key, $0.value) }
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
    }
}

struct TrackedEventsFileDocument: FileDocument {
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
            Label(
                isTracked
                    ? AppLocalization.text("action.untrack", defaultValue: "不追踪")
                    : AppLocalization.text("action.track", defaultValue: "追踪"),
                systemImage: isTracked ? "eye.slash" : "eye"
            )
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
        }
        .buttonStyle(.borderless)
        .appActionFocusEffectDisabled()
        .fixedSize()
        .help(
            isTracked
                ? AppLocalization.text(
                    "help.untrack_calendar",
                    defaultValue: "不再在倒数展示、顶部菜单栏和小组件中显示这个类别"
                )
                : AppLocalization.text(
                    "help.track_calendar",
                    defaultValue: "在倒数展示、顶部菜单栏和小组件中追踪这个类别"
                )
        )
    }
}

struct EventRow: View {
    let event: CountdownEvent
    let isSelected: Bool
    let isPinned: Bool
    var featured: Bool = false
    let onSelectExact: () -> Void
    let onSelectAnnual: () -> Void
    let onTogglePin: () -> Void
    let onUnselect: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var remaining: Int {
        CountdownCalculator.daysRemaining(until: event.eventDate)
    }

    var body: some View {
        HStack(alignment: featured ? .center : .top, spacing: ZhixingMetrics.space12) {
            IdentityMark(color: Color(hex: event.colorHex), height: featured ? 56 : 36)
            VStack(alignment: .leading, spacing: featured ? 6 : 4) {
                Text(event.title)
                    .font(featured ? ZhixingTypography.cardTitle : ZhixingTypography.rowTitle)
                    .zhixingForeground(.heading)
                HStack(spacing: 6) {
                    Text(event.eventDate, format: .dateTime.year().month().day())
                    Text("·")
                    Text(event.calendarTitle)
                }
                .font(.caption)
                .zhixingForeground(.supporting)
            }
            Spacer(minLength: ZhixingMetrics.space8)
            Text(numericLabel)
                .font(featured ? ZhixingTypography.featuredCountdownValue : ZhixingTypography.countdownValue)
                .foregroundStyle(
                    remaining < 0
                        ? Color.orange
                        : ZhixingColor.text(.heading, colorScheme: colorScheme, contrast: contrast)
                )
                .accessibilityLabel(CountdownCalculator.label(until: event.eventDate))
            Button(action: onTogglePin) {
                Image(systemName: isPinned ? "star.fill" : "star")
                    .font(.body)
                    .foregroundStyle(isPinned ? Color.yellow : Color.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!isSelected)
            .appActionFocusEffectDisabled()
            .zhixingHoverOpacity(isPersistent: isPinned)
            .help(
                isSelected
                    ? (isPinned
                        ? AppLocalization.text("action.unpin", defaultValue: "取消置顶")
                        : AppLocalization.text("action.pin", defaultValue: "置顶到顶部菜单栏"))
                    : AppLocalization.text(
                        "help.pin_requires_tracking",
                        defaultValue: "请先追踪这个事件，再进行置顶"
                    )
            )
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
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .appActionFocusEffectDisabled()
            .zhixingHoverOpacity(isPersistent: false)
            .fixedSize()
            .accessibilityLabel("更多")
        }
        .padding(.vertical, featured ? ZhixingMetrics.space8 : ZhixingMetrics.space4)
    }

    private var numericLabel: String {
        switch remaining {
        case ..<0:
            "\(-remaining)"
        case 0:
            "今"
        default:
            "\(remaining)"
        }
    }
}

struct CountdownModuleView: View {
    @ObservedObject var model: AppModel
    var searchText: String
    var selectedCalendarID: String?
    var onCreate: (() -> Void)? = nil

    var body: some View {
        Group {
            if model.accessState != .fullAccess {
                VStack(spacing: ZhixingMetrics.space12) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.system(size: 28, weight: .regular))
                        .symbolRenderingMode(.hierarchical)
                        .zhixingForeground(.faint)
                    Text("需要访问 Apple 日历")
                        .font(.headline.weight(.medium))
                        .zhixingForeground(.heading)
                    Text("日历倒数读取现有日历分类和事件；只有在你明确新建或导入时才会写入选定日历。")
                        .font(.callout)
                        .zhixingForeground(.supporting)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                    CalendarAccessActions(model: model)
                }
                .padding(ZhixingMetrics.space32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if displayedEvents.isEmpty {
                ZhixingEmptyState(
                    systemImage: AppSection.countdown.emptySymbol,
                    title: countdownEmptyTitle,
                    description: countdownEmptyDescription,
                    actionTitle: onCreate == nil ? nil : AppSection.countdown.createActionTitle,
                    actionIdentifier: "countdown-create",
                    action: onCreate
                )
            } else {
                List {
                    if let featured = displayedEvents.first {
                        Section {
                            eventRow(featured, featured: true)
                                .zhixingListRow(featured: true)
                                .listRowBackground(
                                    GlassSurface(cornerRadius: ZhixingMetrics.cornerContainer) {
                                        Color.clear
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                )
                        }
                    }
                    if displayedEvents.count > 1 {
                        Section {
                            ForEach(Array(displayedEvents.dropFirst())) { event in
                                TaskBarCard {
                                    eventRow(event, featured: false)
                                }
                                .listRowSeparator(.hidden)
                                .listRowInsets(
                                    EdgeInsets(
                                        top: ZhixingMetrics.space4,
                                        leading: ZhixingMetrics.pageInset,
                                        bottom: ZhixingMetrics.space4,
                                        trailing: ZhixingMetrics.pageInset
                                    )
                                )
                                .listRowBackground(Color.clear)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .appGlassScrollBackground()
                .contentMargins(.top, ZhixingMetrics.space8, for: .scrollContent)
            }
        }
        .background(Color.clear)
        .navigationTitle(selectedTitle)
    }

    private func eventRow(_ event: CountdownEvent, featured: Bool) -> some View {
        EventRow(
            event: event,
            isSelected: model.isSelected(event),
            isPinned: model.isPinned(event),
            featured: featured,
            onSelectExact: { Task { await model.select(event, mode: .exactEvent) } },
            onSelectAnnual: { Task { await model.select(event, mode: .annualTitle) } },
            onTogglePin: { Task { await model.togglePin(event) } },
            onUnselect: { Task { await model.unselect(event) } }
        )
    }

    private var countdownEmptyTitle: String {
        if selectedCalendarID == nil, !model.selections.isEmpty {
            return AppLocalization.text(
                "empty.countdown_unresolved",
                defaultValue: "已保存的倒数选择尚未匹配到日历事件"
            )
        }
        if selectedCalendarID == nil {
            return AppLocalization.text(
                "empty.no_countdown_events",
                defaultValue: "尚未选择倒数事件"
            )
        }
        return AppLocalization.text("empty.no_future_events", defaultValue: "没有未来事件")
    }

    private var countdownEmptyDescription: String {
        if selectedCalendarID == nil, !model.selections.isEmpty {
            return AppLocalization.text(
                "empty.countdown_unresolved_description",
                defaultValue: "选择仍保留在本机，不会被清空。授权恢复或刷新后会按稳定标识重新匹配年度和重复事件。"
            )
        }
        if selectedCalendarID == nil {
            return AppLocalization.text(
                "empty.select_event_description",
                defaultValue: "从任意 Apple 日历中选择具体事件加入倒数。"
            )
        }
        return AppLocalization.text(
            "empty.future_events_description",
            defaultValue: "尝试扩大时间范围或检查该日历是否包含未来事件。"
        )
    }

    private var displayedEvents: [CountdownEvent] {
        let base: [CountdownEvent]
        if let selectedCalendarID {
            base = CountdownSelectionStore.nextOccurrences(
                from: model.events.filter { $0.calendarIdentifier == selectedCalendarID }
            )
        } else {
            base = model.selectedEvents
        }
        guard !searchText.isEmpty else { return base }
        return base.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.calendarTitle.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var selectedTitle: String {
        if let selectedCalendarID {
            return model.calendars.first(where: { $0.id == selectedCalendarID })?.title
                ?? AppLocalization.text("navigation.future_events", defaultValue: "未来事件")
        }
        return AppLocalization.text("navigation.countdown", defaultValue: "倒数展示")
    }
}
