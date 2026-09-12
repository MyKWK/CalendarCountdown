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

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    ForEach(AppSection.allCases) { section in
                        Label(section.title, systemImage: section.systemImage)
                            .badge(badge(for: section))
                            .tag(section)
                    }
                }
            }
            .navigationTitle("日历倒数")
            .navigationSplitViewColumnWidth(min: 220, ideal: 270)
            .appGlassScrollBackground()
        } detail: {
            detail
                .appGlassScrollBackground()
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
                    switch selection {
                    case .missions:
                        showingAddMission = true
                    case .habits:
                        showingAddHabit = true
                    case .countdown:
                        showingAddEvent = true
                    case .tasks, .none:
                        showingAddTask = true
                    }
                } label: {
                    Label("新建", systemImage: "plus")
                }
                .appActionFocusEffectDisabled()

                Button {
                    Task { await model.refresh() }
                    workspace.reload()
                    Task { await workspace.reconcileProjections() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .appActionFocusEffectDisabled()

                Menu("系统投影") {
                    Toggle(isOn: Binding(
                        get: { (try? workspace.workspace?.projectionSettings().projectTasks) ?? false },
                        set: { workspace.setProjectTasks($0) }
                    )) {
                        Text("任务")
                    }
                    Toggle(isOn: Binding(
                        get: { (try? workspace.workspace?.projectionSettings().projectHabits) ?? false },
                        set: { workspace.setProjectHabits($0) }
                    )) {
                        Text("习惯")
                    }
                    Toggle(isOn: Binding(
                        get: { (try? workspace.workspace?.projectionSettings().projectMissions) ?? false },
                        set: { workspace.setProjectMissions($0) }
                    )) {
                        Text("使命")
                    }
                }

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
                Text(message)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding()
                    .task {
                        try? await Task.sleep(for: .seconds(3))
                        if workspace.statusMessage == message { workspace.statusMessage = nil }
                        if model.statusMessage == message { model.statusMessage = nil }
                    }
            }
        }
        .onAppear { workspace.reload() }
        .onReceive(shortcuts.$request.compactMap { $0 }) { request in
            performShortcut(request.action)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .countdown {
        case .countdown:
            CountdownModuleView(model: model, searchText: searchText, selectedCalendarID: nil)
        case .tasks:
            TaskListView(title: AppSection.tasks.title, views: filtered(workspace.taskViews), workspace: workspace)
        case .missions:
            MissionListView(workspace: workspace, searchText: searchText)
        case .habits:
            HabitListView(workspace: workspace, searchText: searchText)
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

    private var isEnabled: Bool {
        workspace.cloudMode == .iCloud
    }

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) {
                workspace.setCloudMode(!isEnabled)
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: isEnabled ? "icloud.fill" : "icloud")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 15, weight: .semibold))

                VStack(alignment: .leading, spacing: 0) {
                    Text("iCloud 同步")
                        .font(.callout.weight(.medium))
                    Text(isEnabled ? "已开启" : "仅本机")
                        .font(.caption2)
                        .foregroundStyle(isEnabled ? Color.accentColor : .secondary)
                }

                Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isEnabled ? Color.accentColor : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(backgroundColor, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(borderColor, lineWidth: 1)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .appActionFocusEffectDisabled()
        .accessibilityIdentifier("mac-icloud-sync-control")
        .accessibilityLabel("iCloud 同步")
        .accessibilityValue(isEnabled ? "已开启" : "仅本机")
        .help(isEnabled ? "iCloud 同步已开启；点按切换为仅本机" : "当前仅保存在本机；点按开启 iCloud 同步")
    }

    private var backgroundColor: Color {
        isEnabled ? Color.accentColor.opacity(0.13) : Color.secondary.opacity(0.08)
    }

    private var borderColor: Color {
        isEnabled ? Color.accentColor.opacity(0.48) : Color.secondary.opacity(0.2)
    }
}
