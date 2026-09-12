import CalendarCountdownCore
import CalendarCountdownPersistence
import SwiftUI

struct TodayView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var workspace: WorkspaceModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let error = workspace.databaseError {
                    ContentUnavailableView(
                        "数据库不可用",
                        systemImage: "externaldrive.badge.xmark",
                        description: Text(error)
                    )
                }

                section(title: "逾期与今日任务", isEmpty: workspace.todayTasks.isEmpty, empty: "今天没有待办任务") {
                    ForEach(workspace.todayTasks) { view in
                        TaskRowView(view: view, workspace: workspace)
                    }
                }

                section(title: "今日打卡", isEmpty: workspace.habits.isEmpty, empty: "还没有习惯") {
                    ForEach(workspace.habits, id: \.habit.id) { item in
                        HabitRowView(item: item, workspace: workspace)
                    }
                }

                section(title: "使命进度", isEmpty: workspace.missions.isEmpty, empty: "还没有使命") {
                    ForEach(workspace.missions, id: \.mission.id) { item in
                        MissionCardView(item: item, compact: true, workspace: workspace)
                    }
                }

                if model.accessState == .fullAccess {
                    section(title: "最近倒数", isEmpty: model.selectedEvents.isEmpty, empty: "尚未选择倒数事件") {
                        ForEach(model.selectedEvents.prefix(5)) { event in
                            HStack {
                                Circle().fill(Color(hex: event.colorHex)).frame(width: 8, height: 8)
                                Text(event.title)
                                Spacer()
                                Text(CountdownCalculator.label(until: event.eventDate))
                                    .monospacedDigit()
                            }
                        }
                    }
                } else {
                    ContentUnavailableView {
                        Label("倒数需要 Apple 日历权限", systemImage: "calendar.badge.exclamationmark")
                    } description: {
                        Text("任务、使命和打卡可以离线使用。授权后才会读取 Apple 日历中的倒数事件。")
                    } actions: {
                        CalendarAccessActions(model: model)
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("今天")
    }

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        isEmpty: Bool,
        empty: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title2.weight(.semibold))
            if isEmpty {
                Text(empty).foregroundStyle(.secondary)
            } else {
                content()
            }
        }
    }
}

struct TaskListView: View {
    let title: String
    let views: [TaskOccurrenceView]
    @ObservedObject var workspace: WorkspaceModel
    var onCreate: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewport = TaskListViewportSnapshot()

    private var partitioned: (open: [TaskOccurrenceView], completed: [TaskOccurrenceView]) {
        CompletedTrailPresentation.partition(views) { $0.occurrence.status == .completed }
    }

    var body: some View {
        Group {
            if views.isEmpty {
                ZhixingEmptyState(
                    systemImage: AppSection.tasks.emptySymbol,
                    title: title,
                    description: AppSection.tasks.emptyDescription,
                    actionTitle: onCreate == nil ? nil : AppSection.tasks.createActionTitle,
                    actionIdentifier: "task-create",
                    action: onCreate
                )
            } else {
                List {
                    Section {
                        ModuleHeader(
                            title: title,
                            subtitle: AppSection.tasks.subtitle,
                            summary: taskSummary
                        )
                        .zhixingListRow()
                    }
                    Section {
                        ForEach(partitioned.open) { view in
                            TaskRowView(view: view, workspace: workspace)
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
                    if !partitioned.completed.isEmpty {
                        Section {
                            ForEach(Array(partitioned.completed.enumerated()), id: \.element.id) { index, view in
                                TaskRowView(
                                    view: view,
                                    workspace: workspace,
                                    trailIndex: index
                                )
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
                .coordinateSpace(name: "zhixing.tasks")
                .environment(\.taskListViewport, viewport)
                .onScrollGeometryChange(for: CGRect.self) { geometry in
                    geometry.visibleRect
                } action: { _, rect in
                    viewport.visibleRect = rect
                }
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { viewport.globalFrame = proxy.frame(in: .global) }
                            .onChange(of: proxy.frame(in: .global)) { _, frame in
                                viewport.globalFrame = frame
                            }
                    }
                }
                .animation(
                    reduceMotion ? nil : .snappy(duration: ZhixingMetrics.motionStandard),
                    value: partitioned.open.map(\.id)
                )
            }
        }
        .background(ZhixingColor.contentBackground)
        .navigationTitle(title)
    }

    private var taskSummary: String {
        let open = partitioned.open.count
        let overdue = partitioned.open.filter(\.isOverdue).count
        let done = partitioned.completed.count
        if overdue > 0 {
            return "\(open) 个待办 · \(overdue) 个逾期 · \(done) 个已完成"
        }
        return "\(open) 个待办 · \(done) 个已完成"
    }
}

struct TaskRowView: View {
    let view: TaskOccurrenceView
    @ObservedObject var workspace: WorkspaceModel
    var trailIndex: Int? = nil
    @State private var showingEditor = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isCompleted: Bool {
        view.occurrence.status == .completed
    }

    var body: some View {
        TaskBarCard {
            HStack(alignment: .center, spacing: ZhixingMetrics.space12) {
                CompletionRingButton(
                    isCompleted: isCompleted,
                    tint: .accentColor,
                    accessibilityLabel: isCompleted ? "标记为未完成" : "完成任务"
                ) {
                    let animation = ZhixingMotion.standard(reduceMotion: reduceMotion)
                    withAnimation(animation) {
                        if isCompleted {
                            workspace.reopen(view)
                        } else {
                            workspace.complete(view)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(view.title)
                        .font(.headline)
                        .strikethrough(isCompleted)
                        .foregroundStyle(.primary)
                    if let markdown = view.markdownDescription, !markdown.isEmpty {
                        MarkdownBodyView(text: markdown)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    HStack(spacing: 6) {
                        if let mission = workspace.mission(for: view.series.missionID) {
                            MetaTag(
                                title: mission.title,
                                systemImage: MissionSymbolCatalog.resolved(mission.icon),
                                tint: Color.missionIdentity(mission.color),
                                emphasized: true,
                                identifier: "task-mission-tag"
                            )
                        }
                        if let due = view.occurrence.plannedDue {
                            Text(due, format: .dateTime.month().day().hour().minute())
                                .foregroundStyle(view.isOverdue && !isCompleted ? Color.orange : Color.secondary)
                        } else {
                            Text("收集箱")
                                .foregroundStyle(.secondary)
                        }
                        MetaTag(title: "\(view.workload.rawValue) 点")
                        if view.series.isInfinite {
                            Image(systemName: "repeat")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if view.isOverdue, !isCompleted {
                            MetaTag(title: "逾期", tint: .orange, emphasized: true)
                        }
                    }
                    .font(.caption)
                }
                Spacer(minLength: 0)
                if view.series.recurrence != nil, view.occurrence.status == .open {
                    Button("跳过") { workspace.skip(view) }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .buttonStyle(.plain)
                        .appActionFocusEffectDisabled()
                        .zhixingHoverOpacity(isPersistent: false, idleOpacity: 0.4)
                }
            }
        }
        .modifier(OptionalCompletedTrailModifier(index: trailIndex))
        .accessibilityHint(isCompleted ? "已完成。滚动到阅读区域、悬停或聚焦后可清晰查看。" : "")
        .contextMenu {
            Button("编辑") { showingEditor = true }
            if isCompleted {
                Button("重新打开") {
                    withAnimation(ZhixingMotion.standard(reduceMotion: reduceMotion)) {
                        workspace.reopen(view)
                    }
                }
            }
            if view.series.recurrence != nil, view.occurrence.status == .open {
                Button("跳过") { workspace.skip(view) }
            }
            Button("归档") { workspace.archiveTask(view) }
            Button("删除", role: .destructive) { workspace.deleteTask(view, permanent: true) }
        }
        .sheet(isPresented: $showingEditor) {
            EditTaskSheet(
                view: view,
                missions: workspace.missions.map(\.mission)
            ) { command in
                workspace.updateTask(occurrenceID: view.occurrence.id, command: command)
            }
        }
    }
}

private struct OptionalCompletedTrailModifier: ViewModifier {
    var index: Int?

    func body(content: Content) -> some View {
        if let index {
            content.modifier(TaskCompletedTrailChrome(index: index))
        } else {
            content
        }
    }
}

private struct MissionComposerTarget: Identifiable, Hashable {
    let id: UUID
}

private struct MissionCreateToolbarModifier: ViewModifier {
    @Binding var showingAddMission: Bool

    func body(content: Content) -> some View {
        #if os(iOS)
        content.toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddMission = true
                } label: {
                    Label("新建使命", systemImage: "plus")
                }
                .accessibilityIdentifier("mission-create-toolbar")
                .appActionFocusEffectDisabled()
            }
        }
        #else
        content
        #endif
    }
}

struct MissionListView: View {
    @ObservedObject var workspace: WorkspaceModel
    var searchText: String
    @State private var showingAddMission = false
    @State private var editingMission: MissionDefinition?
    @State private var addingTaskToMission: MissionComposerTarget?
    @State private var attachingToMission: MissionComposerTarget?
    @State private var completedMissionForNewTask: MissionDefinition?

    var body: some View {
        let items = workspace.missions.filter {
            searchText.isEmpty || $0.mission.title.localizedCaseInsensitiveContains(searchText)
        }
        Group {
            if items.isEmpty {
                ZhixingEmptyState(
                    systemImage: AppSection.missions.emptySymbol,
                    title: AppSection.missions.title,
                    description: AppSection.missions.emptyDescription,
                    actionTitle: AppSection.missions.createActionTitle,
                    actionIdentifier: "mission-create",
                    action: { showingAddMission = true }
                )
            } else {
                List {
                    Section {
                        ModuleHeader(
                            title: AppSection.missions.title,
                            subtitle: AppSection.missions.subtitle,
                            summary: "\(items.count) 项使命"
                        )
                        .zhixingListRow()
                    }
                    ForEach(items, id: \.mission.id) { item in
                        MissionCardView(
                            item: item,
                            compact: false,
                            workspace: workspace,
                            onAddTask: { requestAddTask(item.mission) },
                            onAttachExisting: { attachingToMission = MissionComposerTarget(id: item.mission.id) }
                        )
                        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                editingMission = item.mission
                            } label: {
                                Label("编辑", systemImage: "pencil")
                            }
                            .tint(.blue)
                            if item.mission.status != .archived {
                                Button {
                                    requestAddTask(item.mission)
                                } label: {
                                    Label("添加任务", systemImage: "plus")
                                }
                                .tint(.accentColor)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button("删除", role: .destructive) {
                                if editingMission?.id == item.mission.id {
                                    editingMission = nil
                                }
                                workspace.deleteMission(item.mission)
                            }
                            Button("归档") {
                                workspace.archiveMission(item.mission)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .appGlassScrollBackground()
            }
        }
        .background(ZhixingColor.contentBackground)
        .navigationTitle("使命")
        .modifier(MissionCreateToolbarModifier(showingAddMission: $showingAddMission))
        .sheet(isPresented: $showingAddMission) {
            AddMissionSheet(initialColor: workspace.suggestedMissionColor.rawValue) { command in
                workspace.createMission(command)
            }
        }
        .sheet(item: $editingMission) { mission in
            MissionEditorSheet(mission: mission) { command in
                workspace.patchMission(id: mission.id, command: command)
            }
        }
        .sheet(item: $addingTaskToMission) { target in
            AddTaskSheet(
                missions: workspace.missions.map(\.mission),
                preselectedMissionID: target.id
            ) { command in
                var command = command
                command.missionID = target.id
                workspace.createTask(command)
            }
        }
        .sheet(item: $attachingToMission) { target in
            AttachExistingTaskSheet(
                missionTitle: mission(for: target.id)?.title ?? "使命",
                series: workspace.unassignedTaskSeries
            ) { series in
                if let mission = mission(for: target.id) {
                    workspace.attachTask(series, to: mission)
                }
            }
        }
        .confirmationDialog(
            "这个使命已完成",
            isPresented: Binding(
                get: { completedMissionForNewTask != nil },
                set: { if !$0 { completedMissionForNewTask = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("重新开启并添加任务") {
                guard let mission = completedMissionForNewTask else { return }
                workspace.reopenMission(mission)
                presentAddTask(missionID: mission.id)
            }
            Button("仅作为后续维护") {
                guard let mission = completedMissionForNewTask else { return }
                presentAddTask(missionID: mission.id)
            }
            Button("取消", role: .cancel) {
                completedMissionForNewTask = nil
            }
        } message: {
            Text("新增任务会扩大计划。要重新开启使命，还是只作为后续维护？")
        }
    }

    private func mission(for id: UUID) -> MissionDefinition? {
        workspace.missions.first(where: { $0.mission.id == id })?.mission
    }

    private func requestAddTask(_ mission: MissionDefinition) {
        guard mission.status != .archived else { return }
        if mission.status == .completed {
            completedMissionForNewTask = mission
        } else {
            addingTaskToMission = MissionComposerTarget(id: mission.id)
        }
    }

    private func presentAddTask(missionID: UUID) {
        completedMissionForNewTask = nil
        Task { @MainActor in
            addingTaskToMission = MissionComposerTarget(id: missionID)
        }
    }
}

struct MissionCardView: View {
    let item: MissionWriteResult
    var compact: Bool
    @ObservedObject var workspace: WorkspaceModel
    var onAddTask: (() -> Void)?
    var onAttachExisting: (() -> Void)?
    @State private var showingEditor = false
    @State private var showingAddTask = false
    @State private var showingAttach = false
    @State private var editingTask: TaskOccurrenceView?
    @State private var confirmCompletedAdd = false
    @State private var showingActivity = false
    @State private var isCollapsed = true

    private var linkedTasks: [TaskOccurrenceView] {
        workspace.taskViews(forMissionID: item.mission.id)
    }

    private var visibleLinkedTasks: [TaskOccurrenceView] {
        Array(linkedTasks.prefix(compact ? 3 : 20))
    }

    private var missionTint: Color {
        Color.missionIdentity(item.mission.color)
    }

    private var collapseStorageKey: String {
        "mission.card.collapsed.\(item.mission.id.uuidString.lowercased())"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ZhixingMetrics.space12) {
            HStack(alignment: .center, spacing: ZhixingMetrics.space8) {
                Image(systemName: MissionSymbolCatalog.resolved(item.mission.icon))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(missionTint)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(missionTint.opacity(0.14)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.mission.title).font(.title3.weight(.semibold))
                    HStack(spacing: 6) {
                        if item.mission.status != .active {
                            MetaTag(
                                title: missionStatusLabel,
                                systemImage: missionStatusSymbol,
                                tint: .secondary,
                                emphasized: true
                            )
                        }
                        if let date = item.mission.targetDate {
                            Text("截止 \(date.isoString)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer(minLength: 0)
                Menu {
                    missionManagementButtons
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .accessibilityIdentifier("mission-overflow")
                .appActionFocusEffectDisabled()
            }
            if let markdown = item.mission.markdownDescription, !markdown.isEmpty {
                MarkdownBodyView(text: markdown)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(compact || isCollapsed ? 2 : 6)
            }
            if item.progress.isUnplanned {
                Text("尚未规划").font(.callout).foregroundStyle(.secondary)
            } else {
                ProgressView(value: item.progress.progress ?? 0)
                    .tint(missionTint)
                    .scaleEffect(x: 1, y: 0.72, anchor: .center)
                HStack {
                    Text("成果进度 \(item.progress.displayPercent.map { String(format: "%.1f%%", $0) } ?? "—")")
                        .font(.callout.monospacedDigit().weight(.medium))
                    Spacer()
                    Text("\(item.progress.donePoints) / \(item.progress.totalPoints) 点")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if !isCollapsed, let continuity = item.progress.continuity, let rate = continuity.rate {
                Text("持续性 \(Int((rate * 100).rounded()))% · 最近 \(continuity.windowDays) 天 \(continuity.completedCount) / \(continuity.expectedCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if compact, !isCollapsed, !visibleLinkedTasks.isEmpty {
                VStack(alignment: .leading, spacing: ZhixingMetrics.space8) {
                    ForEach(visibleLinkedTasks) { view in
                        MissionLinkedTaskRow(
                            view: view,
                            mission: item.mission,
                            workspace: workspace,
                            onEdit: { editingTask = view }
                        )
                    }
                }
            }
            if !compact, !isCollapsed {
                if !visibleLinkedTasks.isEmpty {
                    VStack(alignment: .leading, spacing: ZhixingMetrics.space8) {
                        ForEach(visibleLinkedTasks) { view in
                            MissionLinkedTaskRow(
                                view: view,
                                mission: item.mission,
                                workspace: workspace,
                                onEdit: { editingTask = view }
                            )
                        }
                        if linkedTasks.count > visibleLinkedTasks.count {
                            Text("还有 \(linkedTasks.count - visibleLinkedTasks.count) 个任务")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.leading, ZhixingMetrics.space8)
                }
                if item.mission.status != .archived {
                    addTaskControls
                }
                if item.progress.progress == 1, item.mission.status != .completed {
                    Button("完成使命") {
                        workspace.completeMission(item.mission)
                    }
                    .buttonStyle(.borderedProminent)
                    .appActionFocusEffectDisabled()
                }
            }
        }
        .padding(compact ? 0 : ZhixingMetrics.space16)
        .padding(.leading, compact ? 0 : ZhixingMetrics.space8)
        .background {
            if !compact {
                RoundedRectangle(cornerRadius: ZhixingMetrics.cornerContainer, style: .continuous)
                    .fill(ZhixingColor.groupedBackground.opacity(0.94))
                    .overlay {
                        RoundedRectangle(cornerRadius: ZhixingMetrics.cornerContainer, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: ZhixingMetrics.glassStrokeWidth)
                    }
            }
        }
        .overlay(alignment: .leading) {
            if !compact {
                IdentityMark(color: missionTint)
                    .padding(.vertical, ZhixingMetrics.space12)
            }
        }
        .contextMenu {
            missionManagementButtons
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            isCollapsed.toggle()
            UserDefaults.standard.set(isCollapsed, forKey: collapseStorageKey)
        }
        .onAppear {
            if UserDefaults.standard.object(forKey: collapseStorageKey) != nil {
                isCollapsed = UserDefaults.standard.bool(forKey: collapseStorageKey)
            }
        }
        .sheet(isPresented: $showingEditor) {
            MissionEditorSheet(mission: item.mission) { command in
                workspace.patchMission(id: item.mission.id, command: command)
            }
        }
        .sheet(isPresented: $showingActivity) {
            MissionActivitySheet(
                mission: item.mission,
                entries: workspace.missionActivity(for: item.mission)
            )
        }
        .sheet(isPresented: $showingAddTask) {
            AddTaskSheet(
                missions: workspace.missions.map(\.mission),
                preselectedMissionID: item.mission.id
            ) { command in
                var command = command
                command.missionID = item.mission.id
                workspace.createTask(command)
            }
        }
        .sheet(isPresented: $showingAttach) {
            AttachExistingTaskSheet(
                missionTitle: item.mission.title,
                series: workspace.unassignedTaskSeries
            ) { series in
                workspace.attachTask(series, to: item.mission)
            }
        }
        .sheet(item: $editingTask) { view in
            EditTaskSheet(
                view: view,
                missions: workspace.missions.map(\.mission),
                lockedMissionID: item.mission.id
            ) { command in
                workspace.updateTask(occurrenceID: view.occurrence.id, command: command)
            }
        }
        .confirmationDialog(
            "这个使命已完成",
            isPresented: $confirmCompletedAdd,
            titleVisibility: .visible
        ) {
            Button("重新开启并添加任务") {
                workspace.reopenMission(item.mission)
                showingAddTask = true
            }
            Button("仅作为后续维护") {
                showingAddTask = true
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("新增任务会扩大计划。要重新开启使命，还是只作为后续维护？")
        }
    }

    @ViewBuilder
    private var missionManagementButtons: some View {
        Button("编辑使命") { showingEditor = true }
            .accessibilityIdentifier("mission-edit")
        Button("使命历程") { showingActivity = true }
        if item.mission.status != .archived {
            Button("添加任务") { requestAddTask() }
            if !workspace.unassignedTaskSeries.isEmpty {
                Button("关联已有任务") { requestAttach() }
            }
        }
        if item.mission.status == .active {
            Button("暂停") { workspace.pauseMission(item.mission) }
        }
        Button("归档") { workspace.archiveMission(item.mission) }
        Button("删除", role: .destructive) { workspace.deleteMission(item.mission) }
            .accessibilityIdentifier("mission-delete")
    }

    @ViewBuilder
    private var addTaskControls: some View {
        HStack(spacing: ZhixingMetrics.space8) {
            Button {
                requestAddTask()
            } label: {
                Label(
                    item.progress.isUnplanned ? "添加第一个任务" : "添加任务",
                    systemImage: "plus"
                )
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("mission-add-task")
            .appActionFocusEffectDisabled()

            Button("关联已有任务") {
                requestAttach()
            }
            .accessibilityIdentifier("mission-attach-task")
            .disabled(workspace.unassignedTaskSeries.isEmpty)
            .appActionFocusEffectDisabled()
        }
    }

    private func requestAddTask() {
        guard item.mission.status != .archived else { return }
        if let onAddTask {
            onAddTask()
            return
        }
        if item.mission.status == .completed {
            confirmCompletedAdd = true
        } else {
            showingAddTask = true
        }
    }

    private func requestAttach() {
        guard item.mission.status != .archived else { return }
        if let onAttachExisting {
            onAttachExisting()
        } else {
            showingAttach = true
        }
    }

    private var missionStatusLabel: String {
        switch item.mission.status {
        case .draft: "草稿"
        case .active: "进行中"
        case .paused: "已暂停"
        case .completed: "已完成"
        case .archived: "已归档"
        }
    }

    private var missionStatusSymbol: String {
        switch item.mission.status {
        case .draft: "doc.badge.ellipsis"
        case .active: "circle.fill"
        case .paused: "pause.circle.fill"
        case .completed: "checkmark.circle.fill"
        case .archived: "archivebox.fill"
        }
    }
}

private struct MissionActivitySheet: View {
    let mission: MissionDefinition
    let entries: [MissionActivityEntry]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "还没有历程记录",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("此后对使命和其任务的创建、编辑、完成与删除都会按时间记录在这里。")
                    )
                } else {
                    List(entries) { entry in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: symbol(for: entry))
                                .foregroundStyle(tint(for: entry))
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.summary?.isEmpty == false ? entry.summary! : title(for: entry))
                                    .font(.body.weight(.medium))
                                Text(entry.occurredAt, format: .dateTime.year().month().day().hour().minute().second())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listStyle(.inset)
                }
            }
            .navigationTitle("\(mission.title) · 历程")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .frame(minWidth: 440, minHeight: 420)
    }

    private func title(for entry: MissionActivityEntry) -> String {
        switch entry.command {
        case "missions.create": "新建使命"
        case "missions.update": "编辑使命"
        case "missions.complete": "完成使命"
        case "missions.delete": "删除使命"
        case "missions.add-task": "加入任务"
        case "missions.remove-task": "移出任务"
        case "tasks.create": "新建任务"
        case "tasks.update": "编辑任务"
        case "tasks.complete": "完成任务"
        case "tasks.reopen": "重新打开任务"
        case "tasks.skip": "跳过任务"
        case "tasks.archive": "归档任务"
        case "tasks.delete": "删除任务"
        default: "更新使命内容"
        }
    }

    private func symbol(for entry: MissionActivityEntry) -> String {
        switch entry.command {
        case "missions.complete", "tasks.complete": "checkmark.circle.fill"
        case "missions.delete", "tasks.delete": "trash.circle.fill"
        case "tasks.create", "missions.add-task": "plus.circle.fill"
        case "missions.archive", "tasks.archive": "archivebox.fill"
        case "tasks.reopen": "arrow.counterclockwise.circle.fill"
        default: "pencil.circle.fill"
        }
    }

    private func tint(for entry: MissionActivityEntry) -> Color {
        switch entry.command {
        case "missions.complete", "tasks.complete": .green
        case "missions.delete", "tasks.delete": .red
        case "tasks.create", "missions.add-task": .accentColor
        default: .secondary
        }
    }
}

private struct MissionLinkedTaskRow: View {
    let view: TaskOccurrenceView
    let mission: MissionDefinition
    @ObservedObject var workspace: WorkspaceModel
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: ZhixingMetrics.space8) {
            CompletionRingButton(
                isCompleted: view.occurrence.status == .completed,
                tint: Color.missionIdentity(mission.color),
                accessibilityLabel: view.occurrence.status == .completed ? "标记为未完成" : "完成任务"
            ) {
                if view.occurrence.status == .completed {
                    workspace.reopen(view)
                } else {
                    workspace.complete(view)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(view.title)
                    .font(.subheadline)
                    .strikethrough(view.occurrence.status == .completed)
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    if let due = view.occurrence.plannedDue {
                        Text(due, format: .dateTime.month().day().hour().minute())
                            .foregroundStyle(view.isOverdue && view.occurrence.status == .open ? Color.orange : Color.secondary)
                    } else {
                        Text("收集箱")
                            .foregroundStyle(.secondary)
                    }
                    Text("\(view.workload.rawValue) 点")
                        .foregroundStyle(.secondary)
                    if view.series.isInfinite {
                        Text("∞")
                            .foregroundStyle(.secondary)
                    }
                    if view.isOverdue, view.occurrence.status == .open {
                        MetaTag(title: "逾期", tint: .orange, emphasized: true)
                    }
                }
                .font(.caption)
            }
            Spacer()
            Button("编辑") { onEdit() }
                .font(.caption)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
                .accessibilityIdentifier("mission-edit-task")
                .appActionFocusEffectDisabled()
                .zhixingHoverOpacity(isPersistent: false, idleOpacity: 0.45)
        }
        .contextMenu {
            Button("编辑") { onEdit() }
            Button("从使命移出") {
                workspace.detachTask(seriesID: view.series.id, from: mission)
            }
            Button("删除", role: .destructive) {
                workspace.deleteTask(view, permanent: true)
            }
        }
    }
}

struct HabitListView: View {
    @ObservedObject var workspace: WorkspaceModel
    var searchText: String
    var onCreate: (() -> Void)? = nil

    var body: some View {
        let items = workspace.habits.filter {
            searchText.isEmpty || $0.habit.title.localizedCaseInsensitiveContains(searchText)
        }
        Group {
            if items.isEmpty {
                ZhixingEmptyState(
                    systemImage: AppSection.habits.emptySymbol,
                    title: AppSection.habits.title,
                    description: AppSection.habits.emptyDescription,
                    actionTitle: onCreate == nil ? nil : AppSection.habits.createActionTitle,
                    actionIdentifier: "habit-create",
                    action: onCreate
                )
            } else {
                List {
                    Section {
                        ModuleHeader(
                            title: AppSection.habits.title,
                            subtitle: AppSection.habits.subtitle,
                            summary: habitSummary(items)
                        )
                        .zhixingListRow()
                    }
                    Section {
                        ForEach(items, id: \.habit.id) { item in
                            HabitRowView(item: item, workspace: workspace)
                                .zhixingListRow()
                                .overlay(alignment: .bottom) {
                                    Divider().padding(.leading, 48)
                                }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .appGlassScrollBackground()
            }
        }
        .background(ZhixingColor.contentBackground)
        .navigationTitle("打卡")
    }

    private func habitSummary(_ items: [HabitWriteResult]) -> String {
        let done = items.filter { isCompletedToday($0) }.count
        return "今日 \(done) / \(items.count) 已打卡"
    }

    private func isCompletedToday(_ item: HabitWriteResult) -> Bool {
        item.period?.disposition == .completed || item.checkIn != nil
    }
}

struct HabitRowView: View {
    let item: HabitWriteResult
    @ObservedObject var workspace: WorkspaceModel
    @State private var showingBackfill = false
    @State private var backfillDate = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var identity: Color {
        ZhixingIdentity.color(for: item.habit.id).swiftUIColor
    }

    private var isCompletedToday: Bool {
        item.period?.disposition == .completed || item.checkIn != nil
    }

    private var isSkipped: Bool {
        item.period?.disposition == .skipped
    }

    var body: some View {
        HStack(alignment: .center, spacing: ZhixingMetrics.space12) {
            IdentityMark(color: identity, height: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.habit.title).font(.headline)
                HStack(spacing: 6) {
                    MetaTag(
                        title: isSkipped ? "今日已跳过" : (isCompletedToday ? "今日已打卡" : "今日未打卡"),
                        tint: isCompletedToday ? identity : .secondary,
                        emphasized: isCompletedToday
                    )
                    if let stats = item.stats {
                        Text("连续 \(stats.currentStreak)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text("本周 \(weekLabel(stats))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
            Button {
                workspace.checkIn(item.habit)
            } label: {
                Image(systemName: isCompletedToday ? "checkmark" : "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isCompletedToday ? identity : Color.primary)
                    .frame(width: 36, height: 36)
                    .background {
                        Circle()
                            .fill(isCompletedToday ? identity.opacity(0.14) : Color.primary.opacity(0.05))
                        Circle()
                            .strokeBorder(isCompletedToday ? identity.opacity(0.4) : Color.secondary.opacity(0.35), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .appActionFocusEffectDisabled()
            .accessibilityLabel("打卡")
            .animation(ZhixingMotion.fast(reduceMotion: reduceMotion), value: isCompletedToday)

            Menu {
                if item.habit.metric != .binary {
                    Button("达标") {
                        workspace.checkIn(item.habit, fillToTarget: true)
                    }
                }
                Button("补打") { showingBackfill = true }
                Button("撤销") { workspace.undoCheckIn(item) }
                    .disabled(item.checkIn == nil)
                Button("跳过") { workspace.skipHabit(item.habit) }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .appActionFocusEffectDisabled()
            .accessibilityLabel("更多打卡操作")
        }
        .padding(.vertical, ZhixingMetrics.space4)
        .popover(isPresented: $showingBackfill) {
            VStack(alignment: .leading, spacing: ZhixingMetrics.space12) {
                Text("补打日期").font(.headline)
                DatePicker("日期", selection: $backfillDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                Button("确认补打") {
                    workspace.checkIn(item.habit, at: backfillDate)
                    showingBackfill = false
                }
                .buttonStyle(.borderedProminent)
                .appActionFocusEffectDisabled()
            }
            .padding()
            .frame(width: 280)
        }
        .contextMenu {
            Button("打卡") { workspace.checkIn(item.habit) }
            if item.habit.metric != .binary {
                Button("达标") { workspace.checkIn(item.habit, fillToTarget: true) }
            }
            Button("补打") { showingBackfill = true }
            Button("撤销") { workspace.undoCheckIn(item) }
                .disabled(item.checkIn == nil)
            Button("跳过") { workspace.skipHabit(item.habit) }
        }
    }

    private func weekLabel(_ stats: HabitStats) -> String {
        guard let rate = stats.weekCompletionRate else { return "—" }
        return "\(Int((rate * 100).rounded()))%"
    }
}

struct AddTaskSheet: View {
    let missions: [MissionDefinition]
    var preselectedMissionID: UUID? = nil
    let onSave: (CreateTaskCommand) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var kind: TaskKind = .deadline
    @State private var due = Date()
    @State private var start = Date()
    @State private var hasDue = false
    @State private var workload: WorkloadPoints = .one
    @State private var missionID: UUID?
    @State private var description = ""
    @State private var recurrencePreset = "none"
    @State private var monday = true
    @State private var tuesday = false
    @State private var wednesday = true
    @State private var thursday = false
    @State private var friday = true
    @State private var saturday = false
    @State private var sunday = false
    @State private var endPreset = "never"
    @State private var endCount = 6
    @State private var endDate = Date()
    @State private var priority: TaskPriority = .none
    @State private var projectionPolicy: ProjectionPolicy = .none

    init(
        missions: [MissionDefinition],
        preselectedMissionID: UUID? = nil,
        onSave: @escaping (CreateTaskCommand) -> Void
    ) {
        self.missions = missions
        self.preselectedMissionID = preselectedMissionID
        self.onSave = onSave
        _missionID = State(
            initialValue: MissionSelection.resolvedID(preselectedMissionID, among: missions)
        )
    }

    var body: some View {
        ComposerSheetScaffold(
            title: "新建任务",
            canSubmit: canSubmit,
            width: 520,
            height: 640,
            onCancel: { dismiss() },
            onSubmit: submit
        ) {
            Form {
                TextField("标题", text: $title)
                Picker("类型", selection: $kind) {
                    Text("截止").tag(TaskKind.deadline)
                    Text("时间段").tag(TaskKind.timeWindow)
                }
                if kind != .timeWindow {
                    Toggle("有到期时间", isOn: $hasDue)
                }
                if kind == .timeWindow {
                    DatePicker("开始", selection: $start)
                    DatePicker("结束", selection: $due)
                } else if hasDue {
                    DatePicker("到期", selection: $due)
                }
                Picker("循环", selection: $recurrencePreset) {
                    Text("不循环").tag("none")
                    Text("每天").tag("daily")
                    Text("每周").tag("weekly")
                    Text("每月").tag("monthly")
                    Text("完成后循环").tag("after")
                }
                if recurrencePreset == "weekly" {
                    Toggle("周日", isOn: $sunday)
                    Toggle("周一", isOn: $monday)
                    Toggle("周二", isOn: $tuesday)
                    Toggle("周三", isOn: $wednesday)
                    Toggle("周四", isOn: $thursday)
                    Toggle("周五", isOn: $friday)
                    Toggle("周六", isOn: $saturday)
                }
                Picker("结束", selection: $endPreset) {
                    Text("永不").tag("never")
                    Text("次数").tag("count")
                    Text("日期").tag("date")
                }
                if endPreset == "count" {
                    Stepper("重复 \(endCount) 次", value: $endCount, in: 1...99)
                }
                if endPreset == "date" {
                    DatePicker("结束日期", selection: $endDate, displayedComponents: .date)
                }
                Picker("优先级", selection: $priority) {
                    Text("无").tag(TaskPriority.none)
                    Text("低").tag(TaskPriority.low)
                    Text("中").tag(TaskPriority.medium)
                    Text("高").tag(TaskPriority.high)
                }
                Picker("系统投影", selection: $projectionPolicy) {
                    Text("不投影").tag(ProjectionPolicy.none)
                    Text("提醒事项").tag(ProjectionPolicy.reminder)
                    Text("日历").tag(ProjectionPolicy.calendar)
                    Text("提醒+日历").tag(ProjectionPolicy.both)
                }
                Picker("工作量", selection: $workload) {
                    ForEach(WorkloadPoints.allCases, id: \.rawValue) { value in
                        Text("\(value.rawValue) 点").tag(value)
                    }
                }
                if let lockedID = MissionSelection.resolvedID(preselectedMissionID, among: missions),
                   let lockedTitle = missions.first(where: { $0.id == lockedID })?.title {
                    LabeledContent("使命", value: lockedTitle)
                } else {
                    Picker("使命", selection: $missionID) {
                        Text("无").tag(Optional<UUID>.none)
                        ForEach(missions) { mission in
                            Text(mission.title).tag(Optional(mission.id))
                        }
                    }
                }
                ComposerMultilineField(
                    title: "说明（支持 Markdown）",
                    text: $description,
                    lineLimit: 8...16,
                    onSubmit: submit
                )
                Text("回车换行；⌘↩ 保存。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .onSubmit(submit)
        }
    }

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        guard canSubmit else { return }
        let timeZone = TimeZone.current.identifier
        let schedule: TaskSchedule
        if kind == .timeWindow {
            schedule = TaskSchedule(
                timeZoneIdentifier: timeZone,
                plannedStart: start,
                plannedDue: due
            )
        } else if hasDue {
            schedule = TaskSchedule(timeZoneIdentifier: timeZone, plannedDue: due)
        } else {
            schedule = TaskSchedule(timeZoneIdentifier: timeZone)
        }
        let recurrence: RecurrenceSpec?
        let end: RecurrenceEnd = {
            switch endPreset {
            case "count": return .afterOccurrences(endCount)
            case "date": return .onDate(LocalDate.from(endDate, timeZone: .current))
            default: return .never
            }
        }()
        var weekdays: [Weekday] = []
        if sunday { weekdays.append(.sunday) }
        if monday { weekdays.append(.monday) }
        if tuesday { weekdays.append(.tuesday) }
        if wednesday { weekdays.append(.wednesday) }
        if thursday { weekdays.append(.thursday) }
        if friday { weekdays.append(.friday) }
        if saturday { weekdays.append(.saturday) }
        switch recurrencePreset {
        case "daily":
            recurrence = RecurrenceSpec(
                mode: .fixedSchedule,
                frequency: .daily,
                end: end,
                timeZoneIdentifier: timeZone
            )
        case "weekly":
            recurrence = RecurrenceSpec(
                mode: .fixedSchedule,
                frequency: .weekly,
                weekdays: weekdays.isEmpty ? [.monday] : weekdays,
                end: end,
                timeZoneIdentifier: timeZone
            )
        case "monthly":
            recurrence = RecurrenceSpec(
                mode: .fixedSchedule,
                frequency: .monthly,
                end: end,
                timeZoneIdentifier: timeZone
            )
        case "after":
            recurrence = RecurrenceSpec(
                mode: .afterCompletion,
                frequency: .daily,
                end: end,
                timeZoneIdentifier: timeZone
            )
        default:
            recurrence = nil
        }
        onSave(
            CreateTaskCommand(
                title: title,
                markdownDescription: description.isEmpty ? nil : description,
                kind: kind,
                missionID: MissionSelection.resolvedID(preselectedMissionID ?? missionID, among: missions),
                priority: priority,
                workload: workload,
                schedule: schedule,
                recurrence: recurrence,
                projectionPolicy: projectionPolicy
            )
        )
        dismiss()
    }
}

struct EditTaskSheet: View {
    let view: TaskOccurrenceView
    let missions: [MissionDefinition]
    var lockedMissionID: UUID? = nil
    let onSave: (PatchTaskCommand) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var description: String
    @State private var kind: TaskKind
    @State private var due: Date
    @State private var start: Date
    @State private var hasDue: Bool
    @State private var workload: WorkloadPoints
    @State private var missionID: UUID?
    @State private var priority: TaskPriority
    @State private var editWholeSeries: Bool

    init(
        view: TaskOccurrenceView,
        missions: [MissionDefinition],
        lockedMissionID: UUID? = nil,
        onSave: @escaping (PatchTaskCommand) -> Void
    ) {
        self.view = view
        self.missions = missions
        self.lockedMissionID = lockedMissionID
        self.onSave = onSave
        _title = State(initialValue: view.title)
        _description = State(initialValue: view.markdownDescription ?? "")
        _kind = State(initialValue: view.series.kind)
        _due = State(initialValue: view.occurrence.plannedDue ?? view.series.schedule.plannedDue ?? Date())
        _start = State(initialValue: view.occurrence.plannedStart ?? view.series.schedule.plannedStart ?? Date())
        _hasDue = State(
            initialValue: view.occurrence.plannedDue != nil || view.series.schedule.plannedDue != nil
        )
        _workload = State(initialValue: view.series.workload)
        _missionID = State(
            initialValue: MissionSelection.resolvedID(
                lockedMissionID ?? view.series.missionID,
                among: missions
            )
        )
        _priority = State(initialValue: view.series.priority)
        _editWholeSeries = State(initialValue: true)
    }

    var body: some View {
        ComposerSheetScaffold(
            title: "编辑任务",
            canSubmit: canSubmit,
            width: 520,
            height: 560,
            onCancel: { dismiss() },
            onSubmit: submit
        ) {
            Form {
                TextField("标题", text: $title)
                Picker("类型", selection: $kind) {
                    Text("截止").tag(TaskKind.deadline)
                    Text("时间段").tag(TaskKind.timeWindow)
                }
                .disabled(!editWholeSeries)
                if kind != .timeWindow {
                    Toggle("有到期时间", isOn: $hasDue)
                }
                if kind == .timeWindow {
                    DatePicker("开始", selection: $start)
                    DatePicker("结束", selection: $due)
                } else if hasDue {
                    DatePicker("到期", selection: $due)
                }
                Picker("优先级", selection: $priority) {
                    Text("无").tag(TaskPriority.none)
                    Text("低").tag(TaskPriority.low)
                    Text("中").tag(TaskPriority.medium)
                    Text("高").tag(TaskPriority.high)
                }
                .disabled(!editWholeSeries)
                Picker("工作量", selection: $workload) {
                    ForEach(WorkloadPoints.allCases, id: \.rawValue) { value in
                        Text("\(value.rawValue) 点").tag(value)
                    }
                }
                .disabled(!editWholeSeries)
                if let lockedID = MissionSelection.resolvedID(lockedMissionID, among: missions),
                   let lockedTitle = missions.first(where: { $0.id == lockedID })?.title {
                    LabeledContent("使命", value: lockedTitle)
                } else {
                    Picker("使命", selection: $missionID) {
                        Text("无").tag(Optional<UUID>.none)
                        ForEach(missions) { mission in
                            Text(mission.title).tag(Optional(mission.id))
                        }
                    }
                    .disabled(!editWholeSeries)
                }
                if view.series.recurrence != nil {
                    Toggle("应用到整个任务", isOn: $editWholeSeries)
                }
                ComposerMultilineField(
                    title: "说明（支持 Markdown）",
                    text: $description,
                    lineLimit: 8...16,
                    onSubmit: submit
                )
                Text("回车换行；⌘↩ 保存。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .onSubmit(submit)
        }
    }

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        guard canSubmit else { return }
        onSave(makeCommand())
        dismiss()
    }

    private func makeCommand() -> PatchTaskCommand {
        let timeZone = view.series.schedule.timeZoneIdentifier
        let schedule: TaskSchedule
        if kind == .timeWindow {
            schedule = TaskSchedule(
                timeZoneIdentifier: timeZone,
                plannedStart: start,
                plannedDue: due
            )
        } else if hasDue {
            schedule = TaskSchedule(timeZoneIdentifier: timeZone, plannedDue: due)
        } else {
            schedule = TaskSchedule(timeZoneIdentifier: timeZone)
        }
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if editWholeSeries {
            return PatchTaskCommand(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                markdownDescription: trimmedDescription,
                kind: kind,
                missionID: MissionSelection.resolvedID(lockedMissionID ?? missionID, among: missions),
                clearMission: MissionSelection.resolvedID(lockedMissionID ?? missionID, among: missions) == nil
                    && view.series.missionID != nil,
                priority: priority,
                workload: workload,
                schedule: schedule,
                scope: .series
            )
        }
        return PatchTaskCommand(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            markdownDescription: trimmedDescription,
            schedule: schedule,
            scope: .thisOccurrence
        )
    }
}

struct AttachExistingTaskSheet: View {
    let missionTitle: String
    let series: [TaskSeries]
    let onAttach: (TaskSeries) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ComposerSheetScaffold(
            title: "关联到「\(missionTitle)」",
            canSubmit: false,
            showsPrimary: false,
            width: 420,
            height: 480,
            onCancel: { dismiss() },
            onSubmit: {}
        ) {
            Group {
                if series.isEmpty {
                    ZhixingEmptyState(
                        systemImage: "checklist",
                        title: "没有可关联的任务",
                        description: "任务清单里暂时没有未归属使命的任务。"
                    )
                } else {
                    List(series) { item in
                        Button {
                            onAttach(item)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                    .foregroundStyle(.primary)
                                if let due = item.schedule.plannedDue {
                                    Text(due, format: .dateTime.month().day().hour().minute())
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("收集箱")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
        }
    }
}

struct AddHabitSheet: View {
    let onSave: (CreateHabitCommand) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var metric: HabitMetric = .binary
    @State private var target: Int = 1
    @State private var unit = ""
    @State private var scheduleKind: HabitScheduleKind = .daily
    @State private var allowBackfill = 1
    @State private var projectReminders = false
    @State private var monday = true
    @State private var tuesday = false
    @State private var wednesday = true
    @State private var thursday = false
    @State private var friday = true
    @State private var saturday = false
    @State private var sunday = false

    var body: some View {
        ComposerSheetScaffold(
            title: "新建习惯",
            canSubmit: canSubmit,
            width: 420,
            height: 420,
            onCancel: { dismiss() },
            onSubmit: submit
        ) {
            Form {
                TextField("标题", text: $title)
                Picker("类型", selection: $metric) {
                    Text("完成/未完成").tag(HabitMetric.binary)
                    Text("次数").tag(HabitMetric.count)
                    Text("数量").tag(HabitMetric.quantity)
                }
                if metric != .binary {
                    Stepper("目标 \(target)", value: $target, in: 1...100)
                    TextField("单位", text: $unit)
                }
                Picker("计划", selection: $scheduleKind) {
                    Text("每天").tag(HabitScheduleKind.daily)
                    Text("选定星期").tag(HabitScheduleKind.selectedWeekdays)
                    Text("每周 N 次").tag(HabitScheduleKind.weeklyN)
                    Text("每月 N 次").tag(HabitScheduleKind.monthlyN)
                }
                if scheduleKind == .selectedWeekdays {
                    Toggle("周日", isOn: $sunday)
                    Toggle("周一", isOn: $monday)
                    Toggle("周二", isOn: $tuesday)
                    Toggle("周三", isOn: $wednesday)
                    Toggle("周四", isOn: $thursday)
                    Toggle("周五", isOn: $friday)
                    Toggle("周六", isOn: $saturday)
                }
                Stepper("允许补打 \(allowBackfill) 天", value: $allowBackfill, in: 0...30)
                Toggle("投影到提醒事项", isOn: $projectReminders)
            }
            .formStyle(.grouped)
            .onSubmit(submit)
        }
    }

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        guard canSubmit else { return }
        onSave(
            CreateHabitCommand(
                title: title,
                metric: metric,
                targetValue: Decimal(target),
                unit: unit.isEmpty ? nil : unit,
                schedule: HabitSchedule(
                    kind: scheduleKind,
                    weekdays: {
                        var days: [Weekday] = []
                        if sunday { days.append(.sunday) }
                        if monday { days.append(.monday) }
                        if tuesday { days.append(.tuesday) }
                        if wednesday { days.append(.wednesday) }
                        if thursday { days.append(.thursday) }
                        if friday { days.append(.friday) }
                        if saturday { days.append(.saturday) }
                        return days.isEmpty ? [.monday] : days
                    }(),
                    timesPerPeriod: scheduleKind == .weeklyN || scheduleKind == .monthlyN ? target : 1
                ),
                activeFrom: LocalDate.from(Date(), timeZone: .current),
                allowBackfillDays: allowBackfill,
                projectionPolicy: projectReminders ? .reminder : .none
            )
        )
        dismiss()
    }
}

struct MarkdownBodyView: View {
    let text: String

    var body: some View {
        if let attributed = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .full,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        ) {
            Text(attributed)
                .textSelection(.enabled)
        } else {
            Text(text)
                .textSelection(.enabled)
        }
    }
}
