import CalendarCountdownCalendar
import CalendarCountdownCore
import Darwin
import Foundation

private struct SuccessEnvelope<T: Encodable>: Encodable {
    let ok = true
    let data: T
}

private struct FailureEnvelope: Encodable {
    let ok = false
    let error: CLIErrorPayload
}

private struct CLIErrorPayload: Encodable {
    let code: String
    let message: String
}

private struct AuthReport: Codable {
    let state: CalendarAccessState
}

private struct TrackingExportReport: Codable {
    let exportedPath: String
    let eventCount: Int
}

private struct DoctorReport: Codable {
    let version: String
    let calendarAccess: CalendarAccessState
    let sharedContainer: String?
    let calendarCount: Int?
    let managedRecordCount: Int
    let selectionCount: Int
    let trackedEventCount: Int
    let trackedEventsDocument: String?
}

private enum CLIUsageError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case let .message(value): value
        }
    }
}

private struct Arguments {
    let values: [String]

    func has(_ flag: String) -> Bool { values.contains(flag) }

    func value(_ option: String) -> String? {
        guard let index = values.firstIndex(of: option), values.indices.contains(index + 1) else { return nil }
        let candidate = values[index + 1]
        return candidate.hasPrefix("--") ? nil : candidate
    }

    func required(_ option: String) throws -> String {
        guard let result = value(option), !result.isEmpty else {
            throw CLIUsageError.message("缺少必填参数 \(option)。")
        }
        return result
    }
}

@main
struct CalCountCLI {
    static func main() async {
        let raw = Array(CommandLine.arguments.dropFirst())
        guard let command = raw.first else {
            printHelp()
            return
        }

        let arguments = Arguments(values: raw)
        let repository = EventKitRepository()
        do {
            switch command {
            case "help", "--help", "-h":
                printHelp()
            case "version", "--version":
                try emit(["version": ProductConstants.version])
            case "auth":
                var state = await repository.authorizationState()
                if state == .notDetermined {
                    _ = try await repository.requestFullAccess()
                    state = await repository.authorizationState()
                }
                try emit(AuthReport(state: state))
            case "calendars":
                try requireSubcommand(raw, "list")
                try emit(await repository.calendars())
            case "events":
                try await handleEvents(raw, arguments: arguments, repository: repository)
            case "birthdays":
                try await handleBirthdays(raw, arguments: arguments, repository: repository)
            case "records":
                try requireSubcommand(raw, "list")
                try emit(await repository.managedRecords())
            case "selections":
                try await handleSelections(raw, arguments: arguments, repository: repository)
            case "tracking":
                try await handleTracking(raw, arguments: arguments, repository: repository)
            case "next":
                let limit = Int(arguments.value("--limit") ?? "10") ?? 10
                let days = Int(arguments.value("--days") ?? String(ProductConstants.defaultFetchDays))
                    ?? ProductConstants.defaultFetchDays
                let events = try await repository.selectedUpcomingEvents(days: days)
                try emit(Array(events.prefix(max(1, limit))))
            case "import":
                try await handleImport(raw, arguments: arguments, repository: repository)
            case "sync":
                let count = try await repository.syncManagedRecords()
                try emit(["projectedEventCount": count])
            case "doctor":
                try await handleDoctor(repository: repository)
            default:
                throw CLIUsageError.message("未知命令：\(command)。运行 calcount help 查看用法。")
            }
        } catch {
            let code: String
            let exitCode: Int32
            if error is CLIUsageError {
                code = "usage_error"
                exitCode = 64
            } else if let eventKitError = error as? EventKitRepositoryError,
                      case .calendarAccessRequired = eventKitError {
                code = "calendar_access_required"
                exitCode = 77
            } else {
                code = "operation_failed"
                exitCode = 1
            }
            try? emitFailure(code: code, message: error.localizedDescription)
            Darwin.exit(exitCode)
        }
    }

    private static func handleEvents(
        _ raw: [String],
        arguments: Arguments,
        repository: EventKitRepository
    ) async throws {
        guard raw.count >= 2 else { throw CLIUsageError.message("events 需要子命令。") }
        switch raw[1] {
        case "list":
            let days = Int(arguments.value("--days") ?? String(ProductConstants.defaultFetchDays))
                ?? ProductConstants.defaultFetchDays
            let calendarIDs = arguments.value("--calendar-id").map { [$0] } ?? []
            try emit(await repository.events(days: days, calendarIdentifiers: calendarIDs))
        case "add":
            let draft = try eventDraft(arguments: arguments, birthdayMode: false)
            try emit(await repository.write(draft))
        case "update":
            guard raw.count >= 3, let id = UUID(uuidString: raw[2]) else {
                throw CLIUsageError.message("用法：calcount events update <record-uuid> [参数]。")
            }
            guard let record = try await repository.managedRecords().first(where: { $0.id == id }) else {
                throw CLIUsageError.message("找不到记录 \(id.uuidString)。")
            }
            let merged = try mergedDraft(record.draft, arguments: arguments)
            try emit(await repository.updateManagedRecord(id: id, draft: merged))
        case "delete":
            guard raw.count >= 3, let id = UUID(uuidString: raw[2]) else {
                throw CLIUsageError.message("用法：calcount events delete <record-uuid>。")
            }
            try await repository.deleteManagedRecord(id: id)
            try emit(["deletedRecordId": id.uuidString])
        case "select":
            let eventID = try arguments.required("--event-id")
            let days = Int(arguments.value("--days") ?? String(ProductConstants.defaultFetchDays))
                ?? ProductConstants.defaultFetchDays
            guard let event = try await repository.events(days: days).first(where: { $0.id == eventID }) else {
                throw CLIUsageError.message("在查询范围内找不到 event-id 对应事件。")
            }
            let mode: SelectionMode = arguments.has("--annual-title") ? .annualTitle : .exactEvent
            try emit(await repository.select(event: event, mode: mode))
        default:
            throw CLIUsageError.message("未知 events 子命令：\(raw[1])。")
        }
    }

    private static func handleBirthdays(
        _ raw: [String],
        arguments: Arguments,
        repository: EventKitRepository
    ) async throws {
        try requireSubcommand(raw, "add")
        let draft = try eventDraft(arguments: arguments, birthdayMode: true)
        try emit(await repository.write(draft))
    }

    private static func handleSelections(
        _ raw: [String],
        arguments: Arguments,
        repository: EventKitRepository
    ) async throws {
        guard raw.count >= 2 else { throw CLIUsageError.message("selections 需要子命令。") }
        switch raw[1] {
        case "list":
            try emit(await repository.selections())
        case "add":
            let calendar = try arguments.required("--calendar")
            let title = try arguments.required("--title")
            let mode = SelectionMode(rawValue: arguments.value("--mode") ?? "annualTitle") ?? .annualTitle
            try emit(await repository.select(draft: SelectionDraft(calendarTitle: calendar, eventTitle: title, mode: mode)))
        case "remove":
            guard raw.count >= 3, let id = UUID(uuidString: raw[2]) else {
                throw CLIUsageError.message("用法：calcount selections remove <selection-uuid>。")
            }
            try await repository.removeSelection(id: id)
            try emit(["removedSelectionId": id.uuidString])
        default:
            throw CLIUsageError.message("未知 selections 子命令：\(raw[1])。")
        }
    }

    private static func handleImport(
        _ raw: [String],
        arguments: Arguments,
        repository: EventKitRepository
    ) async throws {
        guard raw.count >= 2, !raw[1].hasPrefix("--") else {
            throw CLIUsageError.message("用法：calcount import <json-path> [--dry-run]。")
        }
        let url = URL(fileURLWithPath: raw[1])
        let document = try JSONCoding.decoder().decode(ImportDocument.self, from: Data(contentsOf: url))
        try emit(await repository.importDocument(document, dryRun: arguments.has("--dry-run")))
    }

    private static func handleTracking(
        _ raw: [String],
        arguments: Arguments,
        repository: EventKitRepository
    ) async throws {
        guard raw.count >= 2 else { throw CLIUsageError.message("tracking 需要子命令。") }
        switch raw[1] {
        case "list":
            try emit(try TrackedEventsFileStore.load())
        case "refresh":
            try emit(await repository.synchronizeTrackedEventsDocument())
        case "export":
            let output = try arguments.required("--output")
            let document = try TrackedEventsFileStore.load()
            let url = URL(fileURLWithPath: output)
            try TrackedEventsFileStore.export(document, to: url)
            try emit(TrackingExportReport(exportedPath: url.path, eventCount: document.events.count))
        default:
            throw CLIUsageError.message("未知 tracking 子命令：\(raw[1])。")
        }
    }

    private static func handleDoctor(repository: EventKitRepository) async throws {
        let state = await repository.authorizationState()
        let calendarCount = state == .fullAccess ? try await repository.calendars().count : nil
        let trackedDocument = try? TrackedEventsFileStore.load()
        let report = DoctorReport(
            version: ProductConstants.version,
            calendarAccess: state,
            sharedContainer: (try? SharedContainer.rootURL())?.path,
            calendarCount: calendarCount,
            managedRecordCount: (try? ManagedEventFileStore.load().count) ?? 0,
            selectionCount: (try? CountdownSelectionStore.load().count) ?? 0,
            trackedEventCount: trackedDocument?.events.count ?? 0,
            trackedEventsDocument: (try? SharedContainer.trackedEventsURL())?.path
        )
        try emit(report)
    }

    private static func eventDraft(arguments: Arguments, birthdayMode: Bool) throws -> ManagedEventDraft {
        let title = try arguments.required(birthdayMode ? "--name" : "--title")
        let calendarTitle = arguments.value("--calendar") ?? (birthdayMode ? ProductConstants.suggestedBirthdayCalendarTitle : nil)
        guard let calendarTitle else { throw CLIUsageError.message("缺少 --calendar。") }
        let lunarValue = arguments.value("--lunar")
        let lunarParts = lunarValue?.split(separator: "-").compactMap { Int($0) }
        if lunarValue != nil, lunarParts?.count != 2 {
            throw CLIUsageError.message("--lunar 应为 月-日，例如 8-15。")
        }
        let recurrence = birthdayMode
            ? RecurrenceKind.yearly
            : RecurrenceKind(rawValue: arguments.value("--recurrence") ?? "none") ?? .none
        let alerts = parseAlertDays(arguments.value("--alert-days") ?? (birthdayMode ? "7,1,0" : ""))
        let startYearValue = arguments.value("--start-year")
        let startYear = startYearValue.flatMap(Int.init)
        if startYearValue != nil, startYear == nil {
            throw CLIUsageError.message("--start-year 应为年份整数。")
        }
        return ManagedEventDraft(
            externalId: arguments.value("--external-id"),
            title: title,
            calendarTitle: calendarTitle,
            calendarIdentifier: arguments.value("--calendar-id"),
            calendarSystem: lunarValue == nil ? .gregorian : .lunar,
            recurrence: lunarValue == nil ? recurrence : .yearly,
            date: lunarValue == nil ? try arguments.required("--date") : nil,
            time: arguments.value("--time"),
            startYear: startYear,
            lunarMonth: lunarParts?[0],
            lunarDay: lunarParts?[1],
            lunarLeapMonthPolicy: arguments.has("--leap-month") ? .leapOnly : .regularOnly,
            invalidLunarDayPolicy: arguments.has("--strict-lunar-day") ? .strict : .clampToMonthEnd,
            isAllDay: arguments.value("--time") == nil,
            alertDaysBefore: alerts,
            notes: arguments.value("--notes"),
            selectForCountdown: !arguments.has("--no-select")
        )
    }

    private static func mergedDraft(_ original: ManagedEventDraft, arguments: Arguments) throws -> ManagedEventDraft {
        var result = original
        if let value = arguments.value("--title") { result.title = value }
        if let value = arguments.value("--calendar") { result.calendarTitle = value; result.calendarIdentifier = nil }
        if let value = arguments.value("--calendar-id") { result.calendarIdentifier = value }
        if let value = arguments.value("--date") { result.date = value; result.calendarSystem = .gregorian }
        if let value = arguments.value("--time") { result.time = value; result.isAllDay = false }
        if let value = arguments.value("--start-year"), let parsed = Int(value) { result.startYear = parsed }
        if let value = arguments.value("--recurrence"), let parsed = RecurrenceKind(rawValue: value) { result.recurrence = parsed }
        if let value = arguments.value("--alert-days") { result.alertDaysBefore = parseAlertDays(value) }
        if let value = arguments.value("--notes") { result.notes = value }
        if let value = arguments.value("--lunar") {
            let parts = value.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 2 else { throw CLIUsageError.message("--lunar 应为 月-日。") }
            result.calendarSystem = .lunar
            result.recurrence = .yearly
            result.date = nil
            result.lunarMonth = parts[0]
            result.lunarDay = parts[1]
        }
        if arguments.has("--no-select") { result.selectForCountdown = false }
        if arguments.has("--select") { result.selectForCountdown = true }
        return try result.validated()
    }

    private static func parseAlertDays(_ value: String) -> [Int] {
        value.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }

    private static func requireSubcommand(_ raw: [String], _ expected: String) throws {
        guard raw.count >= 2, raw[1] == expected else {
            throw CLIUsageError.message("需要子命令 \(expected)。")
        }
    }

    private static func emit<T: Encodable>(_ value: T) throws {
        let data = try JSONCoding.encoder().encode(SuccessEnvelope(data: value))
        print(String(decoding: data, as: UTF8.self))
    }

    private static func emitFailure(code: String, message: String) throws {
        let data = try JSONCoding.encoder().encode(
            FailureEnvelope(error: CLIErrorPayload(code: code, message: message))
        )
        print(String(decoding: data, as: UTF8.self))
    }

    private static func printHelp() {
        print("""
        calcount \(ProductConstants.version) — Apple 日历倒数 CLI

        calcount auth
        calcount calendars list
        calcount events list [--days N] [--calendar-id ID]
        calcount events add --calendar NAME --title TITLE --date YYYY-MM-DD [--recurrence yearly]
        calcount events update <record-uuid> [参数]
        calcount events delete <record-uuid>
        calcount events select --event-id ID [--annual-title]
        calcount birthdays add [--calendar 生日] --name NAME (--date YYYY-MM-DD | --lunar M-D [--start-year YYYY])
        calcount records list
        calcount selections list
        calcount selections add --calendar NAME --title TITLE [--mode annualTitle]
        calcount selections remove <selection-uuid>
        calcount tracking list
        calcount tracking refresh
        calcount tracking export --output FILE.json
        calcount next [--limit 10] [--days N]
        calcount import FILE.json [--dry-run]
        calcount sync
        calcount doctor

        所有结构化命令均输出 JSON。写操作只作用于明确指定的 Apple 日历。
        """)
    }
}
