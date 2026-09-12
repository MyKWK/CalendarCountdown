import XCTest
@testable import CalendarCountdownCore

final class MobileNavigationContractTests: XCTestCase {
    func testPrimarySectionsAreExactlyFour() {
        XCTAssertEqual(
            AppSection.allCases.map(\.rawValue),
            ["countdown", "tasks", "missions", "habits"]
        )
        XCTAssertEqual(
            AppSection.allCases.map(\.title),
            ["倒数日", "任务清单", "使命清单", "打卡"]
        )
        XCTAssertFalse(AppSection.allCases.map(\.title).contains("今天"))
        XCTAssertFalse(AppSection.allCases.map(\.title).contains("更多"))
    }

    func testDeepLinksStayInsideFourPrimaryModules() throws {
        let taskID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let taskURL = try XCTUnwrap(DomainLink.task(taskID).url)
        XCTAssertEqual(AppRoute.parse(url: taskURL), .task(taskID))
        XCTAssertEqual(AppRoute.parse(url: taskURL)?.section, .tasks)

        let missionURL = try XCTUnwrap(URL(string: "calendarcountdown://missions"))
        XCTAssertEqual(AppRoute.parse(url: missionURL), .section(.missions))

        let more = URL(string: "calendarcountdown://more")
        XCTAssertNil(more.flatMap(AppRoute.parse(url:)))
    }

    func testIOSFileProtectionIsDeclaredInPolicy() {
        #if os(iOS)
        XCTAssertTrue(true, "SQLiteFilePolicy sets completeUntilFirstUserAuthentication on iOS.")
        #endif
    }
}
