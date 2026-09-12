import CalendarCountdownCore
import CalendarCountdownPersistence
import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var workspace: WorkspaceModel
    let openSettings: () -> Void
    @ObservedObject var shortcuts: AppShortcutCoordinator
    @State private var selection: AppSection? = .countdown
    @State private var searchText = ""
    @State private var showingAddEvent = false
    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var showingAddTask = false
    @State private var showingAddMission = false
    @State private var showingAddHabit = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var currentSection: AppSection { selection ?? .countdown }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(
                    min: ZhixingMetrics.sidebarMinWidth,
                    ideal: ZhixingMetrics.sidebarIdealWidth,
                    max: ZhixingMetrics.sidebarMaxWidth
                )
        } detail: {
            detail
                .background(ZhixingColor.contentBackground)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                PrimaryToolbarAction(
                    title: "新建",
                    systemImage: "plus",
                    help: currentSection.createHelp,
                    identifier: currentSection == .missions ? "mission-create-toolbar" : "mac-create-button"
                ) {
                    presentCreate(for: currentSection)
                }
            }

            ToolbarItem {
                Menu {
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
                        Task { await model.refresh() }
                        workspace.reload()
                        Task { await workspace.reconcileProjections() }
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }

                    Divider()

                    Toggle(isOn: Binding(
                        get: { (try? workspace.workspace?.projectionSettings().projectTasks) ?? false },
                        set: { workspace.setProjectTasks($0) }
                    )) {
                        Text("投影任务")
                    }
                    Toggle(isOn: Binding(
                        get: { (try? workspace.workspace?.projectionSettings().projectHabits) ?? false },
                        set: { workspace.setProjectHabits($0) }
                    )) {
                        Text("投影习惯")
                    }
                    Toggle(isOn: Binding(
                        get: { (try? workspace.workspace?.projectionSettings().projectMissions) ?? false },
                        set: { workspace.setProjectMissions($0) }
                    )) {
                        Text("投影使命")
                    }
                } label: {
                    Label("整理", systemImage: "ellipsis.circle")
                }
                .help("导入、导出、刷新与系统投影")
                .accessibilityLabel("整理")
                .appActionFocusEffectDisabled()
            }

            ToolbarItem {
                CloudSyncToolbarButton(workspace: workspace)
            }

            ToolbarItem {
                Button {
                    openSettings()
                } label: {
                    Label("设置", systemImage: "gearshape")
                }
                .appActionFocusEffectDisabled()
                .accessibilityIdentifier("mac-settings-button")
                .accessibilityLabel("设置")
                .help("打开设置")
            }
        }
        .searchable(text: $searchText, prompt: "搜索")
        .sheet(isPresented: $showingAddEvent) {
            AddEventView(calendars: model.writableCalendars) { draft in
                await model.add(draft)
            }
        }
        .sheet(isPresented: $showingAddTask) {
            AddTaskSheet(missions: workspace.missions.map(\.mission)) { command in
                workspace.createTask(command)
            }
        }
        .sheet(isPresented: $showingAddMission) {
            AddMissionSheet(initialColor: workspace.suggestedMissionColor.rawValue) { command in
                workspace.createMission(command)
            }
        }
        .sheet(isPresented: $showingAddHabit) {
            AddHabitSheet { command in
                workspace.createHabit(command)
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
            get: { model.errorMessage != nil || workspace.errorMessage != nil || workspace.databaseError != nil },
            set: { if !$0 {
                model.errorMessage = nil
                workspace.errorMessage = nil
            } }
        )) {
            Button("好", role: .cancel) {
                model.errorMessage = nil
                workspace.errorMessage = nil
            }
            .appActionFocusEffectDisabled()
        } message: {
            Text(
                workspace.databaseError
                    ?? workspace.errorMessage
                    ?? model.errorMessage
                    ?? AppLocalization.text("error.unknown", defaultValue: "未知错误")
            )
        }
        .overlay(alignment: .bottom) {
            if let message = workspace.statusMessage ?? model.statusMessage {
                FloatingStatusBanner(message: message)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .task {
                        try? await Task.sleep(for: .seconds(3))
                        if workspace.statusMessage == message { workspace.statusMessage = nil }
                        if model.statusMessage == message { model.statusMessage = nil }
                    }
            }
        }
        .animation(ZhixingMotion.standard(reduceMotion: reduceMotion), value: workspace.statusMessage)
        .animation(ZhixingMotion.standard(reduceMotion: reduceMotion), value: model.statusMessage)
        .onAppear { workspace.reload() }
        .onReceive(shortcuts.$request.compactMap { $0 }) { request in
            performShortcut(request.action)
        }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                ForEach(AppSection.allCases) { section in
                    SidebarItemRow(
                        section: section,
                        count: badge(for: section),
                        isSelected: currentSection == section
                    )
                    .tag(section)
                    .listRowInsets(
                        EdgeInsets(
                            top: ZhixingMetrics.space4,
                            leading: ZhixingMetrics.space8,
                            bottom: ZhixingMetrics.space4,
                            trailing: ZhixingMetrics.space8
                        )
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(SidebarSelectionBackground(isSelected: currentSection == section))
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .navigationTitle(AppLocalization.text("app.name", defaultValue: "知行"))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            sidebarSyncSummary
        }
        .background(ZhixingColor.contentBackground)
        .frame(minWidth: ZhixingMetrics.sidebarMinWidth)
    }

    private var sidebarSyncSummary: some View {
        let presentation = workspace.cloudPresentation
        return HStack(spacing: 6) {
            Image(systemName: presentation.systemImage)
                .font(.caption)
            Text(presentation.title)
                .font(.caption)
            Spacer()
        }
        .foregroundStyle(.tertiary)
        .padding(.horizontal, ZhixingMetrics.space16)
        .padding(.vertical, ZhixingMetrics.space12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("同步状态 \(presentation.accessibilityValue)")
        .accessibilityAddTraits(.updatesFrequently)
    }

    @ViewBuilder
    private var detail: some View {
        switch currentSection {
        case .countdown:
            CountdownModuleView(
                model: model,
                searchText: searchText,
                selectedCalendarID: nil,
                onCreate: { showingAddEvent = true }
            )
        case .tasks:
            TaskListView(
                title: AppSection.tasks.title,
                views: filtered(workspace.taskViews),
                workspace: workspace,
                onCreate: { showingAddTask = true }
            )
        case .missions:
            MissionListView(workspace: workspace, searchText: searchText)
        case .habits:
            HabitListView(
                workspace: workspace,
                searchText: searchText,
                onCreate: { showingAddHabit = true }
            )
        }
    }

    private func badge(for section: AppSection) -> Int {
        switch section {
        case .countdown:
            model.selectedEvents.count
        case .tasks:
            workspace.openTasks.count
        case .missions:
            workspace.missions.count
        case .habits:
            workspace.habits.count
        }
    }

    private func filtered(_ views: [TaskOccurrenceView]) -> [TaskOccurrenceView] {
        guard !searchText.isEmpty else { return views }
        return views.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
                || ($0.markdownDescription?.localizedCaseInsensitiveContains(searchText) ?? false)
                || (workspace.missionTitle(for: $0.series.missionID)?
                    .localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    private func presentCreate(for section: AppSection) {
        switch section {
        case .countdown:
            showingAddEvent = true
        case .tasks:
            showingAddTask = true
        case .missions:
            showingAddMission = true
        case .habits:
            showingAddHabit = true
        }
    }

    private func performShortcut(_ action: AppShortcutAction) {
        switch action {
        case .addCountdown:
            selection = .countdown
            showingAddEvent = true
        case .addTask:
            selection = .tasks
            showingAddTask = true
        case .addMission:
            selection = .missions
            showingAddMission = true
        case .addHabit:
            selection = .habits
            showingAddHabit = true
        case let .selectSection(section):
            selection = section
        }
    }
}

private struct CloudSyncToolbarButton: View {
    @ObservedObject var workspace: WorkspaceModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var presentation: CloudSyncPresentation {
        workspace.cloudPresentation
    }

    private var isEnabled: Bool {
        workspace.cloudMode == .iCloud
    }

    var body: some View {
        Button {
            withAnimation(ZhixingMotion.standard(reduceMotion: reduceMotion)) {
                workspace.setCloudMode(!isEnabled)
            }
        } label: {
            StatusCapsule(
                title: presentation.title,
                systemImage: presentation.systemImage,
                tint: capsuleTint,
                emphasized: isEnabled
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .appActionFocusEffectDisabled()
        .accessibilityIdentifier("mac-icloud-sync-control")
        .accessibilityLabel("iCloud 同步")
        .accessibilityValue(presentation.accessibilityValue)
        .help(helpText)
    }

    private var capsuleTint: Color {
        switch presentation {
        case .failed: .orange
        case .synced, .syncing, .enabled: .accentColor
        case .localOnly: .secondary
        }
    }

    private var helpText: String {
        switch presentation {
        case .localOnly:
            "当前仅保存在本机；点按开启 iCloud 同步"
        case .enabled:
            "iCloud 已开启，待首次同步；点按切换为仅本机"
        case .syncing:
            "正在与 iCloud 同步；点按切换为仅本机"
        case .synced:
            "iCloud 已同步；点按切换为仅本机"
        case .failed:
            "iCloud 同步失败，数据已回到仅本机或等待重试；点按切换"
        }
    }
}
