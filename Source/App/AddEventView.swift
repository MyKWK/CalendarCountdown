import CalendarCountdownCore
import SwiftUI

struct AddEventView: View {
    let calendars: [CalendarSummary]
    let onSave: (ManagedEventDraft) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var entryKind: EntryKind = .oneTime
    @State private var title = ""
    @State private var calendarIdentifier: String?
    @State private var calendarSystem: CalendarSystemKind = .gregorian
    @State private var date = Date()
    @State private var isAllDay = true
    @State private var lunarStartYear = Calendar.current.component(.year, from: Date())
    @State private var lunarMonth = 1
    @State private var lunarDay = 1
    @State private var lunarLeapMonthPolicy: LunarLeapMonthPolicy = .regularOnly
    @State private var invalidLunarDayPolicy: InvalidLunarDayPolicy = .clampToMonthEnd
    @State private var alertDays = "7,1,0"
    @State private var notes = ""
    @State private var selectForCountdown = true
    @State private var isSaving = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("录入类型") {
                    Picker("类型", selection: $entryKind) {
                        ForEach(EntryKind.allCases) { kind in
                            Label(kind.title, systemImage: kind.systemImage).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: entryKind) { _, kind in
                        configure(for: kind)
                    }
                }

                Section("重要日") {
                    TextField("名称", text: $title, prompt: Text(entryKind.titlePlaceholder))
                    Picker("写入日历", selection: $calendarIdentifier) {
                        ForEach(calendars) { calendar in
                            Text("\(calendar.sourceTitle) / \(calendar.title)")
                                .tag(Optional(calendar.id))
                        }
                    }
                }

                if entryKind == .oneTime {
                    Section("日期") {
                        DatePicker(
                            "发生时间",
                            selection: $date,
                            displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute]
                        )
                        Toggle("全天事件", isOn: $isAllDay)
                    }
                } else {
                    recurringSection
                }

                Section("提醒与倒数") {
                    TextField("提前提醒天数", text: $alertDays, prompt: Text("例如 30,7,1,0"))
                    Text("用逗号分隔；0 表示当天提醒，留空表示不提醒。")
                        .font(.caption)
                        .foregroundStyle(alertDaysAreValid ? Color.secondary : Color.red)
                    if !alertDaysAreValid {
                        Text("提醒天数只能填写 0 到 3650 的整数。")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    TextField("备注（可选）", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                    Toggle("同步后加入倒数展示", isOn: $selectForCountdown)
                }

                Section("同步预览") {
                    Label(syncPreview, systemImage: "calendar.badge.plus")
                    Text("保存成功以 Apple 日历实际写入结果为准；事件内容不会只保存在本 App 中。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Button("取消", role: .cancel) { dismiss() }
                Spacer()
                if isSaving {
                    ProgressView().controlSize(.small)
                }
                Button("同步到 Apple 日历") { Task { await save() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
            .padding()
        }
        .frame(width: 560, height: 680)
        .onAppear { selectSuggestedCalendar(for: entryKind, force: false) }
    }

    @ViewBuilder
    private var recurringSection: some View {
        Section("每年循环") {
            Picker("历法", selection: $calendarSystem) {
                ForEach(CalendarSystemKind.allCases, id: \.self) {
                    Text($0.displayName).tag($0)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: calendarSystem) { _, value in
                if value == .lunar { isAllDay = true }
            }

            if calendarSystem == .gregorian {
                DatePicker(
                    "首次日期",
                    selection: $date,
                    displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute]
                )
                Toggle("全天事件", isOn: $isAllDay)
                Text("Apple 日历会保存为每年重复的日历事件。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Stepper("开始年份：\(lunarStartYear)", value: $lunarStartYear, in: 1...9999)
                Text("例如生日填写出生年份；该年份会进入可导出的追踪清单。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Picker("农历月份", selection: $lunarMonth) {
                        ForEach(1...12, id: \.self) { month in
                            Text(Self.lunarMonthNames[month - 1]).tag(month)
                        }
                    }
                    Picker("农历日期", selection: $lunarDay) {
                        ForEach(1...30, id: \.self) { day in
                            Text(Self.lunarDayNames[day - 1]).tag(day)
                        }
                    }
                }
                Picker("闰月规则", selection: $lunarLeapMonthPolicy) {
                    Text("只按正常月份").tag(LunarLeapMonthPolicy.regularOnly)
                    Text("只按闰月").tag(LunarLeapMonthPolicy.leapOnly)
                    Text("正常月和闰月都提醒").tag(LunarLeapMonthPolicy.both)
                }
                Picker("小月没有三十时", selection: $invalidLunarDayPolicy) {
                    Text("改为当月廿九").tag(InvalidLunarDayPolicy.clampToMonthEnd)
                    Text("该年不创建").tag(InvalidLunarDayPolicy.strict)
                }
                if let nextLunarDate {
                    LabeledContent("下一次") {
                        Text(nextLunarDate, format: .dateTime.year().month().day())
                    }
                }
                Text("EventKit 不支持农历重复规则，因此会把未来 \(ProductConstants.defaultProjectionYears) 年的实际日期直接写入 Apple 日历。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && calendarIdentifier != nil
            && alertDaysAreValid
            && !isSaving
    }

    private var parsedAlertDays: [Int] {
        alertDays.split(separator: ",", omittingEmptySubsequences: true)
            .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private var alertDaysAreValid: Bool {
        let parts = alertDays.split(separator: ",", omittingEmptySubsequences: true)
        return parts.allSatisfy { part in
            guard let value = Int(part.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                return false
            }
            return (0...3650).contains(value)
        }
    }

    private var projectedLunarDates: [Date] {
        let currentYear = Calendar.current.component(.year, from: Date())
        let today = Calendar.current.startOfDay(for: Date())
        return (currentYear...(currentYear + ProductConstants.defaultProjectionYears))
            .flatMap { year in
                LunarDateResolver.dates(
                    month: lunarMonth,
                    day: lunarDay,
                    leapMonthPolicy: lunarLeapMonthPolicy,
                    invalidDayPolicy: invalidLunarDayPolicy,
                    inGregorianYear: year
                )
            }
            .filter { $0 >= today }
            .sorted()
    }

    private var nextLunarDate: Date? { projectedLunarDates.first }

    private var syncPreview: String {
        let calendarName = calendars.first(where: { $0.id == calendarIdentifier })?.title ?? "所选日历"
        switch (entryKind, calendarSystem) {
        case (.oneTime, _):
            return "向“\(calendarName)”写入 1 个单次事件。"
        case (.yearly, .gregorian):
            return "向“\(calendarName)”写入 1 个每年重复事件。"
        case (.yearly, .lunar):
            return "向“\(calendarName)”写入 \(projectedLunarDates.count) 个农历循环日期。"
        }
    }

    private func configure(for kind: EntryKind) {
        switch kind {
        case .oneTime:
            calendarSystem = .gregorian
        case .yearly:
            isAllDay = true
        }
        selectSuggestedCalendar(for: kind, force: true)
    }

    private func selectSuggestedCalendar(for kind: EntryKind, force: Bool) {
        guard force || calendarIdentifier == nil else { return }
        let preferredTitle = kind == .yearly ? ProductConstants.suggestedBirthdayCalendarTitle : "个人"
        calendarIdentifier = calendars.first(where: { $0.title == preferredTitle })?.id
            ?? calendars.first?.id
    }

    private func save() async {
        guard let selected = calendars.first(where: { $0.id == calendarIdentifier }) else { return }
        isSaving = true
        defer { isSaving = false }
        let usesGregorianDate = entryKind == .oneTime || calendarSystem == .gregorian
        let time: String? = usesGregorianDate && !isAllDay ? String(
            format: "%02d:%02d",
            Calendar.current.component(.hour, from: date),
            Calendar.current.component(.minute, from: date)
        ) : nil
        let draft = ManagedEventDraft(
            title: title,
            calendarTitle: selected.title,
            calendarIdentifier: selected.id,
            calendarSystem: entryKind == .oneTime ? .gregorian : calendarSystem,
            recurrence: entryKind == .oneTime ? .none : .yearly,
            date: usesGregorianDate ? DateSupport.dateOnlyString(date) : nil,
            time: time,
            startYear: entryKind == .yearly && calendarSystem == .lunar ? lunarStartYear : nil,
            lunarMonth: entryKind == .yearly && calendarSystem == .lunar ? lunarMonth : nil,
            lunarDay: entryKind == .yearly && calendarSystem == .lunar ? lunarDay : nil,
            lunarLeapMonthPolicy: lunarLeapMonthPolicy,
            invalidLunarDayPolicy: invalidLunarDayPolicy,
            isAllDay: entryKind == .yearly && calendarSystem == .lunar ? true : isAllDay,
            alertDaysBefore: parsedAlertDays,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes,
            selectForCountdown: selectForCountdown
        )
        if await onSave(draft) { dismiss() }
    }

    private enum EntryKind: String, CaseIterable, Identifiable {
        case oneTime
        case yearly

        var id: String { rawValue }
        var title: String { self == .oneTime ? "单次重要日" : "每年循环" }
        var systemImage: String { self == .oneTime ? "calendar.badge.plus" : "repeat" }
        var titlePlaceholder: String { self == .oneTime ? "例如：项目纪念日" : "例如：小林生日" }
    }

    private static let lunarMonthNames = [
        "正月", "二月", "三月", "四月", "五月", "六月",
        "七月", "八月", "九月", "十月", "冬月", "腊月"
    ]

    private static let lunarDayNames = [
        "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
        "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
        "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"
    ]
}
