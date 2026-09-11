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
                        Button("授权日历访问") {
                            Task { await model.requestAccess() }
                        }
                        .buttonStyle(.borderedProminent)
                        .appActionFocusEffectDisabled()
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

    var body: some View {
        Group {
            if views.isEmpty {
                ContentUnavailableView(title, systemImage: "checkmark.circle", description: Text("没有符合条件的任务。"))
            } else {
                List(views) { view in
                    TaskRowView(view: view, workspace: workspace)
                }
            }
        }
        .navigationTitle(title)
    }
}

struct TaskRowView: View {
    let view: TaskOccurrenceView
    @ObservedObject var workspace: WorkspaceModel

    var body: some View {
        HStack(spacing: 10) {
            Button {
                if view.occurrence.status == .completed {
                    workspace.reopen(view)
                } else {
                    workspace.complete(view)
                }
            } label: {
                Image(systemName: view.occurrence.status == .completed ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(view.isOverdue ? .red : .accentColor)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .appActionFocusEffectDisabled()

            VStack(alignment: .leading, spacing: 3) {
                Text(view.title).font(.headline)
                    .strikethrough(view.occurrence.status == .completed)
                if let markdown = view.markdownDescription, !markdown.isEmpty {
                    MarkdownBodyView(text: markdown)
                        .font(.caption)
                        .lineLimit(3)
                }
                HStack(spacing: 6) {
                    if let due = view.occurrence.plannedDue {
                        Text(due, format: .dateTime.month().day().hour().minute())
                    } else {
                        Text("收集箱")
                    }
                    Text("·")
                    Text("\(view.workload.rawValue) 点")
                    if view.series.isInfinite {
                        Image(systemName: "repeat")
                    }
                    if view.isOverdue {
                        Text("逾期").foregroundStyle(.red)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if view.series.recurrence != nil, view.occurrence.status == .open {
                Button("跳过") { workspace.skip(view) }
                    .appActionFocusEffectDisabled()
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("归档") { workspace.archiveTask(view) }
            Button("删除", role: .destructive) { workspace.deleteTask(view, permanent: true) }
        }
    }
}

struct MissionListView: View {
    @ObservedObject var workspace: WorkspaceModel
    var searchText: String

    var body: some View {
        let items = workspace.missions.filter {
            searchText.isEmpty || $0.mission.title.localizedCaseInsensitiveContains(searchText)
        }
        Group {
            if items.isEmpty {
                ContentUnavailableView("使命", systemImage: "flag", description: Text("创建一个有边界、最终可以完成的长期结果。"))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(items, id: \.mission.id) { item in
                            MissionCardView(item: item, compact: false, workspace: workspace)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .navigationTitle("使命")
    }
}

struct MissionCardView: View {
    let item: MissionWriteResult
    var compact: Bool
    @ObservedObject var workspace: WorkspaceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(item.mission.title).font(.title3.weight(.semibold))
                Spacer()
                if let date = item.mission.targetDate {
                    Text("截止 \(date.isoString)").foregroundStyle(.secondary)
                }
            }
            if item.progress.isUnplanned {
                Text("尚未规划").foregroundStyle(.secondary)
            } else {
                ProgressView(value: item.progress.progress ?? 0)
                HStack {
                    Text("成果进度 \(item.progress.displayPercent.map { String(format: "%.1f%%", $0) } ?? "—")")
                    Spacer()
                    Text("\(item.progress.donePoints) / \(item.progress.totalPoints) 点")
                        .monospacedDigit()
                }
                .font(.callout)
            }
            if let continuity = item.progress.continuity, let rate = continuity.rate {
                Text("持续性 \(Int((rate * 100).rounded()))% · 最近 \(continuity.windowDays) 天 \(continuity.completedCount) / \(continuity.expectedCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !compact {
                ForEach(Array(item.progress.contributions.prefix(8).enumerated()), id: \.offset) { _, row in
                    HStack {
                        Text(row.countsTowardProgress ? (row.status == "completed" ? "✓" : "☐") : "∞")
                        Text(row.title)
                        Spacer()
                        Text(row.countsTowardProgress ? "\(row.workload) 点" : "不计成果进度")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
                if item.progress.progress == 1, item.mission.status != .completed {
                    Button("完成使命") {
                        workspace.completeMission(item.mission)
                    }
                    .buttonStyle(.borderedProminent)
                    .appActionFocusEffectDisabled()
                }
                HStack {
                    if item.mission.status == .active {
                        Button("暂停") { workspace.pauseMission(item.mission) }
                            .appActionFocusEffectDisabled()
                    }
                    Button("归档") { workspace.archiveMission(item.mission) }
                        .appActionFocusEffectDisabled()
                }
            }
        }
        .padding(compact ? 0 : 16)
        .background(compact ? .clear : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct HabitListView: View {
    @ObservedObject var workspace: WorkspaceModel
    var searchText: String

    var body: some View {
        let items = workspace.habits.filter {
            searchText.isEmpty || $0.habit.title.localizedCaseInsensitiveContains(searchText)
        }
        Group {
            if items.isEmpty {
                ContentUnavailableView("打卡", systemImage: "flame", description: Text("习惯关注一致性，而不是最终做完。"))
            } else {
                List {
                    ForEach(items, id: \.habit.id) { item in
                        HabitRowView(item: item, workspace: workspace)
                    }
                }
            }
        }
        .navigationTitle("打卡")
    }
}

struct HabitRowView: View {
    let item: HabitWriteResult
    @ObservedObject var workspace: WorkspaceModel
    @State private var showingBackfill = false
    @State private var backfillDate = Date()

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.habit.title).font(.headline)
                if let stats = item.stats {
                    Text("连续 \(stats.currentStreak) · 最长 \(stats.longestStreak) · 累计 \(stats.totalValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("打卡") {
                workspace.checkIn(item.habit)
            }
            .appActionFocusEffectDisabled()
            if item.habit.metric != .binary {
                Button("达标") {
                    workspace.checkIn(item.habit, fillToTarget: true)
                }
                .appActionFocusEffectDisabled()
            }
            Button("补打") {
                showingBackfill = true
            }
            .popover(isPresented: $showingBackfill) {
                VStack(alignment: .leading, spacing: 12) {
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
            .appActionFocusEffectDisabled()
            Button("撤销") {
                workspace.undoCheckIn(item)
            }
            .disabled(item.checkIn == nil)
            .appActionFocusEffectDisabled()
            Button("跳过") {
                workspace.skipHabit(item.habit)
            }
            .appActionFocusEffectDisabled()
        }
        .padding(.vertical, 4)
    }
}

struct AddTaskSheet: View {
    let missions: [MissionDefinition]
    let onSave: (CreateTaskCommand) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var kind: TaskKind = .deadline
    @State private var due = Date()
    @State private var start = Date()
    @State private var hasDue = true
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

    var body: some View {
        NavigationStack {
            Form {
                TextField("标题", text: $title)
                Picker("类型", selection: $kind) {
                    Text("截止").tag(TaskKind.deadline)
                    Text("时间段").tag(TaskKind.timeWindow)
                }
                Toggle("有日期", isOn: $hasDue)
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
                Picker("使命", selection: $missionID) {
                    Text("无").tag(Optional<UUID>.none)
                    ForEach(missions) { mission in
                        Text(mission.title).tag(Optional(mission.id))
                    }
                }
                TextField("Markdown 描述", text: $description, axis: .vertical)
                    .lineLimit(4...12)
                if !description.isEmpty {
                    MarkdownBodyView(text: description)
                }
            }
            .navigationTitle("新建任务")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .appActionFocusEffectDisabled()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
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
                                missionID: missionID,
                                priority: priority,
                                workload: workload,
                                schedule: schedule,
                                recurrence: recurrence,
                                projectionPolicy: projectionPolicy
                            )
                        )
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .appActionFocusEffectDisabled()
                }
            }
        }
        .frame(width: 520, height: 640)
    }
}

struct AddMissionSheet: View {
    let onSave: (CreateMissionCommand) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var description = ""
    @State private var targetDateEnabled = false
    @State private var targetDate = Date()

    var body: some View {
        NavigationStack {
            Form {
                TextField("标题", text: $title)
                TextField("说明", text: $description, axis: .vertical)
                    .lineLimit(3...8)
                Toggle("目标日期", isOn: $targetDateEnabled)
                if targetDateEnabled {
                    DatePicker("截止", selection: $targetDate, displayedComponents: .date)
                }
                if !description.isEmpty {
                    MarkdownBodyView(text: description)
                }
            }
            .navigationTitle("新建使命")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .appActionFocusEffectDisabled()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(
                            CreateMissionCommand(
                                title: title,
                                markdownDescription: description.isEmpty ? nil : description,
                                targetDate: targetDateEnabled ? LocalDate.from(targetDate, timeZone: .current) : nil
                            )
                        )
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .appActionFocusEffectDisabled()
                }
            }
        }
        .frame(width: 420, height: 260)
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
        NavigationStack {
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
            .navigationTitle("新建习惯")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .appActionFocusEffectDisabled()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
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
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .appActionFocusEffectDisabled()
                }
            }
        }
        .frame(width: 420, height: 420)
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
