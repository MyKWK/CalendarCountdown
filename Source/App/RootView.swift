import CalendarCountdownCore
import CalendarCountdownPersistence
import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var workspace: WorkspaceModel
    let openSettings: (AppSettingsSection) -> Void
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
            VStack(spacing: 0) {
                detailHeader
                Rectangle()
                    .fill(ZhixingColor.hairline)
                    .frame(height: 1)
                detail
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(ZhixingColor.contentBackground)
        }
        .toolbar(.hidden, for: .windowToolbar)
        .background {
            AppGlassBackdrop()
                .ignoresSafeArea()
        }
        .zhixingForeground(.body)
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
        VStack(spacing: 0) {
            sidebarHeader

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(AppSection.allCases) { section in
                        Button {
                            withAnimation(ZhixingMotion.fast(reduceMotion: reduceMotion)) {
                                selection = section
                            }
                        } label: {
                            SidebarItemRow(
                                section: section,
                                count: badge(for: section),
                                isSelected: currentSection == section
                            )
                            .padding(.horizontal, ZhixingMetrics.space8)
                            .background(
                                SidebarSelectionBackground(isSelected: currentSection == section)
                            )
                        }
                        .buttonStyle(.plain)
                        .appActionFocusEffectDisabled()
                    }
                }
                .padding(.horizontal, ZhixingMetrics.space8)
                .padding(.top, ZhixingMetrics.space4)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            sidebarFooter
        }
        .background(ZhixingColor.sidebarBackground)
        .frame(minWidth: ZhixingMetrics.sidebarMinWidth)
    }

    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: ZhixingMetrics.space12) {
            HStack(spacing: ZhixingMetrics.space8) {
                Image(systemName: "scope")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .zhixingForeground(.heading)
                Text(AppLocalization.text("app.name", defaultValue: "知行"))
                    .font(ZhixingTypography.sidebarBrandTitle)
                    .zhixingForeground(.heading)
            }

            HStack(spacing: ZhixingMetrics.space8) {
                Image(systemName: "magnifyingglass")
                    .zhixingForeground(.supporting)
                TextField("搜索", text: $searchText)
                    .textFieldStyle(.plain)
                    .accessibilityIdentifier("sidebar-search-field")
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .zhixingForeground(.faint)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清除搜索")
                    .appActionFocusEffectDisabled()
                }
            }
            .padding(.horizontal, ZhixingMetrics.space12)
            .frame(height: 32)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: ZhixingMetrics.glassStrokeWidth)
            }
        }
        .padding(.horizontal, ZhixingMetrics.space16)
        .padding(.top, ZhixingMetrics.space12)
        .padding(.bottom, ZhixingMetrics.space8)
    }

    private var sidebarFooter: some View {
        HStack(spacing: ZhixingMetrics.space8) {
            CloudSyncToolbarButton(workspace: workspace)
            Spacer(minLength: 0)
            Button {
                refreshAllContent()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(CodexIconButtonStyle())
            .help("刷新全部内容")
            .accessibilityLabel("刷新全部内容")
            .accessibilityIdentifier("sidebar-refresh")
            .appActionFocusEffectDisabled()

            Menu {
                ForEach(AppSettingsSection.allCases) { section in
                    Button {
                        openSettings(section)
                    } label: {
                        Label(section.title, systemImage: section.systemImage)
                    }
                    .accessibilityIdentifier("settings-\(section.rawValue)")
                }
            } label: {
                Image(systemName: "gearshape")
                    .zhixingForeground(.supporting)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .tint(.secondary)
            .buttonStyle(CodexIconButtonStyle())
            .help("设置")
            .accessibilityLabel("设置")
            .accessibilityIdentifier("mac-settings-button")
            .appActionFocusEffectDisabled()
        }
        .padding(.horizontal, ZhixingMetrics.space12)
        .padding(.vertical, ZhixingMetrics.space8)
        .background(ZhixingColor.sidebarBackground)
        .overlay(alignment: .top) {
            Rectangle().fill(ZhixingColor.hairline).frame(height: 1)
        }
    }

    private var detailHeader: some View {
        HStack(spacing: ZhixingMetrics.space12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(currentSection.title)
                    .font(.headline.weight(.medium))
                    .zhixingForeground(.heading)
                Text(detailSummary)
                    .font(.caption.monospacedDigit())
                    .zhixingForeground(.faint)
            }

            Spacer(minLength: ZhixingMetrics.space16)

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

                Divider()
                Toggle("投影任务", isOn: projectTasksBinding)
                Toggle("投影习惯", isOn: projectHabitsBinding)
                Toggle("投影使命", isOn: projectMissionsBinding)
            } label: {
                Image(systemName: "ellipsis")
                    .zhixingForeground(.supporting)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .tint(.secondary)
            .buttonStyle(CodexIconButtonStyle())
            .help("导入、导出与系统投影")
            .accessibilityLabel("导入、导出与投影")
            .accessibilityIdentifier("sidebar-data-and-projection")
            .appActionFocusEffectDisabled()

            PrimaryToolbarAction(
                title: currentSection.createActionTitle,
                systemImage: "plus",
                help: currentSection.createHelp,
                identifier: currentSection == .missions ? "mission-create-toolbar" : "mac-create-button"
            ) {
                presentCreate(for: currentSection)
            }
        }
        .padding(.horizontal, ZhixingMetrics.space20)
        .frame(height: 54)
        .background(ZhixingColor.contentBackground)
    }

    private var detailSummary: String {
        switch currentSection {
        case .countdown:
            return "\(model.selectedEvents.count) 个倒数"
        case .tasks:
            let completed = workspace.taskViews.filter { $0.occurrence.status == .completed }.count
            return "\(workspace.openTasks.count) 个待办 · \(completed) 个已完成"
        case .missions:
            return "\(workspace.missions.count) 项使命"
        case .habits:
            let completed = workspace.habits.filter {
                $0.period?.disposition == .completed || $0.checkIn != nil
            }.count
            return "今日 \(completed) / \(workspace.habits.count) 已打卡"
        }
    }

    private var projectTasksBinding: Binding<Bool> {
        Binding(
            get: { (try? workspace.workspace?.projectionSettings().projectTasks) ?? false },
            set: { workspace.setProjectTasks($0) }
        )
    }

    private var projectHabitsBinding: Binding<Bool> {
        Binding(
            get: { (try? workspace.workspace?.projectionSettings().projectHabits) ?? false },
            set: { workspace.setProjectHabits($0) }
        )
    }

    private var projectMissionsBinding: Binding<Bool> {
        Binding(
            get: { (try? workspace.workspace?.projectionSettings().projectMissions) ?? false },
            set: { workspace.setProjectMissions($0) }
        )
    }

    private func refreshAllContent() {
        Task { await model.refresh() }
        workspace.reload()
        Task { await workspace.reconcileProjections() }
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
