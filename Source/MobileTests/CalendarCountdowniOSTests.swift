import XCTest
@testable import CalendarCountdown

final class CalendarCountdowniOSTests: XCTestCase {
    func testPrimarySectionsMatchMacSidebar() {
        XCTAssertEqual(AppSection.allCases.map(\.rawValue), ["countdown", "tasks", "missions", "habits"])
    }

    func testDeepLinksResolveToFourModules() {
        XCTAssertEqual(AppRoute.parse(URL(string: "calendarcountdown://open")!), .open)
        XCTAssertEqual(AppRoute.parse(URL(string: "calendarcountdown://event")!), .section(.countdown))
        XCTAssertEqual(AppRoute.parse(URL(string: "calendarcountdown://task")!), .section(.tasks))
        XCTAssertEqual(AppRoute.parse(URL(string: "calendarcountdown://mission")!), .section(.missions))
        XCTAssertEqual(AppRoute.parse(URL(string: "calendarcountdown://habit")!), .section(.habits))
    }

    func testManagedEventCloudPayloadStripsCalendarIdentifier() throws {
        var draft = try ManagedEventDraft(
            title: "生日",
            calendarIdentifier: "local-calendar",
            date: "2026-01-01"
        ).validated()
        draft.calendarIdentifier = "local-calendar"
        let payload = CountdownManagedCloudPayload(
            ManagedEventRecord(draft: draft, modifiedByDevice: UUID())
        )
        let json = String(decoding: try JSONCoding.encoder(pretty: false).encode(payload), as: UTF8.self)
        XCTAssertFalse(json.contains("calendarIdentifier"))
        XCTAssertFalse(json.contains("local-calendar"))
    }

    func testSelectionCloudPayloadOmitsEventKitIdentifiers() throws {
        let selection = CountdownSelection(
            mode: .exactEvent,
            calendarIdentifier: "cal-1",
            calendarTitle: "节日",
            eventIdentifier: "ek-1",
            eventTitle: "元旦"
        )
        let payload = CountdownSelectionCloudPayload(selection)
        let json = String(decoding: try JSONCoding.encoder(pretty: false).encode(payload), as: UTF8.self)
        XCTAssertFalse(json.contains("eventIdentifier"))
        XCTAssertFalse(json.contains("calendarIdentifier"))
    }
}
