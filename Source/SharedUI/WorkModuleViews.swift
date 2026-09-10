#if canImport(CalendarCountdownCore)
import CalendarCountdownCore
#endif
import SwiftUI

struct TaskListView: View {
    @ObservedObject var workspace: WorkspaceModel
    @Binding var selectedID: UUID?
    @State private var title = ""
    @State private var missionID: UUID?
    @State private var showingAdd = false

    init(workspace: WorkspaceModel, selectedID: Binding<UUID?> = .constant(nil)) {
        self._workspace = ObservedObject(wrappedValue: workspace)
        self._selectedID = selectedID
    }

    var body: some View {
        List(selection: $selectedID) {
            ForEach(workspace.tasks) { task in
                Button {
                    selectedID = task.id
                    try? workspace.toggleTask(task)
                } label: {
                    HStack {
                        Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(task.isCompleted ? .green : .secondary)
                        VStack(alignment: .leading) {
                            Text(task.title)
                                .strikethrough(task.isCompleted)
                            if let dueDate = task.dueDate {
                                Text(dueDate, format: .dateTime.month().day())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                }
                .tag(task.id)
                .accessibilityIdentifier("task-row-\(task.id.uuidString)")
            }
            .onDelete { indexSet in
                for index in indexSet {
                    try? workspace.deleteTask(workspace.tasks[index])
                }
            }
        }
        .navigationTitle("任务清单")
        .toolbar {
            Button {
                showingAdd = true
            } label: {
                Label("新建任务", systemImage: "plus")
            }
            .accessibilityIdentifier("add-task")
        }
        .sheet(isPresented: $showingAdd) {
            NavigationStack {
                Form {
                    TextField("标题", text: $title)
                    Picker("所属使命", selection: $missionID) {
                        Text("无").tag(Optional<UUID>.none)
                        ForEach(workspace.missions) { mission in
                            Text(mission.title).tag(Optional(mission.id))
                        }
                    }
                }
                .navigationTitle("新建任务")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showingAdd = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            try? workspace.addTask(title: trimmed, dueDate: nil, missionID: missionID)
                            title = ""
                            missionID = nil
                            showingAdd = false
                        }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("save-task")
                    }
                }
            }
        }
        .onAppear { try? workspace.reload() }
    }
}

struct TaskDetailView: View {
    @ObservedObject var workspace: WorkspaceModel
    let taskID: UUID

    var body: some View {
        if let task = workspace.tasks.first(where: { $0.id == taskID }) {
            Form {
                LabeledContent("标题", value: task.title)
                LabeledContent("状态", value: task.isCompleted ? "已完成" : "未完成")
                if let dueDate = task.dueDate {
                    LabeledContent("截止日期", value: dueDate.formatted(date: .abbreviated, time: .omitted))
                }
                if let mission = workspace.missions.first(where: { $0.id == task.missionID }) {
                    LabeledContent("所属使命", value: mission.title)
                }
                Button(task.isCompleted ? "标为未完成" : "标为完成") {
                    try? workspace.toggleTask(task)
                }
                .accessibilityIdentifier("toggle-task-detail")
            }
            .navigationTitle("任务")
        } else {
            ContentUnavailableView("选择一个任务", systemImage: "checklist")
        }
    }
}

struct MissionListView: View {
    @ObservedObject var workspace: WorkspaceModel
    @Binding var selectedID: UUID?
    @State private var title = ""
    @State private var showingAdd = false

    init(workspace: WorkspaceModel, selectedID: Binding<UUID?> = .constant(nil)) {
        self._workspace = ObservedObject(wrappedValue: workspace)
        self._selectedID = selectedID
    }

    var body: some View {
        List(workspace.missions, selection: $selectedID) { mission in
            let progress = workspace.progress(for: mission)
            VStack(alignment: .leading, spacing: 6) {
                Text(mission.title).font(.headline)
                ProgressView(value: progress.ratio)
                Text("\(progress.completedWorkload)/\(progress.plannedWorkload)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .tag(mission.id)
            .accessibilityIdentifier("mission-row-\(mission.id.uuidString)")
        }
        .navigationTitle("使命清单")
        .toolbar {
            Button {
                showingAdd = true
            } label: {
                Label("新建使命", systemImage: "plus")
            }
            .accessibilityIdentifier("add-mission")
        }
        .sheet(isPresented: $showingAdd) {
            NavigationStack {
                Form {
                    TextField("标题", text: $title)
                }
                .navigationTitle("新建使命")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showingAdd = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            try? workspace.addMission(title: trimmed)
                            title = ""
                            showingAdd = false
                        }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("save-mission")
                    }
                }
            }
        }
        .onAppear { try? workspace.reload() }
    }
}

struct MissionDetailView: View {
    @ObservedObject var workspace: WorkspaceModel
    let missionID: UUID

    var body: some View {
        if let mission = workspace.missions.first(where: { $0.id == missionID }) {
            let progress = workspace.progress(for: mission)
            Form {
                LabeledContent("标题", value: mission.title)
                LabeledContent("进度", value: "\(progress.completedWorkload)/\(progress.plannedWorkload)")
                ProgressView(value: progress.ratio)
                Section("任务") {
                    ForEach(workspace.tasks.filter { $0.missionID == mission.id }) { task in
                        Text(task.title)
                    }
                }
            }
            .navigationTitle("使命")
        } else {
            ContentUnavailableView("选择一个使命", systemImage: "flag")
        }
    }
}

struct HabitListView: View {
    @ObservedObject var workspace: WorkspaceModel
    @Binding var selectedID: UUID?
    @State private var title = ""
    @State private var showingAdd = false

    init(workspace: WorkspaceModel, selectedID: Binding<UUID?> = .constant(nil)) {
        self._workspace = ObservedObject(wrappedValue: workspace)
        self._selectedID = selectedID
    }

    var body: some View {
        List(workspace.habits, selection: $selectedID) { habit in
            HStack {
                VStack(alignment: .leading) {
                    Text(habit.title).font(.headline)
                    Text("打卡记录保存在本机 SQLite，并进入 CloudKit outbox。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("打卡") {
                    selectedID = habit.id
                    try? workspace.checkIn(habit: habit)
                }
                .accessibilityIdentifier("checkin-\(habit.id.uuidString)")
            }
            .tag(habit.id)
        }
        .navigationTitle("打卡")
        .toolbar {
            Button {
                showingAdd = true
            } label: {
                Label("新建习惯", systemImage: "plus")
            }
            .accessibilityIdentifier("add-habit")
        }
        .sheet(isPresented: $showingAdd) {
            NavigationStack {
                Form {
                    TextField("标题", text: $title)
                }
                .navigationTitle("新建习惯")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showingAdd = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            try? workspace.addHabit(title: trimmed)
                            title = ""
                            showingAdd = false
                        }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("save-habit")
                    }
                }
            }
        }
        .onAppear { try? workspace.reload() }
    }
}

struct HabitDetailView: View {
    @ObservedObject var workspace: WorkspaceModel
    let habitID: UUID

    var body: some View {
        if let habit = workspace.habits.first(where: { $0.id == habitID }) {
            let checkIns = (try? workspace.checkIns(for: habit)) ?? []
            List {
                Section(habit.title) {
                    Button("今日打卡") {
                        try? workspace.checkIn(habit: habit)
                    }
                    .accessibilityIdentifier("checkin-detail")
                }
                Section("记录") {
                    if checkIns.isEmpty {
                        Text("还没有打卡")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(checkIns) { item in
                            Text(item.occurredOn, format: .dateTime.year().month().day())
                        }
                    }
                }
            }
            .navigationTitle("打卡")
        } else {
            ContentUnavailableView("选择一个习惯", systemImage: "flame")
        }
    }
}
