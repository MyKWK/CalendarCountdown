import XCTest

final class PhoneNavigationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testFourPrimaryTabsExistAndMoreIsAbsent() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .phone, "iPhone tab navigation is verified on compact phone destinations.")
        let app = XCUIApplication()
        app.launch()
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))
        XCTAssertTrue(tabBar.buttons["倒数日"].exists)
        XCTAssertTrue(tabBar.buttons["任务清单"].exists)
        XCTAssertTrue(tabBar.buttons["使命清单"].exists)
        XCTAssertTrue(tabBar.buttons["打卡"].exists)
        XCTAssertEqual(tabBar.buttons.count, 4)
        XCTAssertFalse(tabBar.buttons["更多"].exists)
        XCTAssertFalse(tabBar.buttons["今天"].exists)

        tabBar.buttons["任务清单"].tap()
        XCTAssertTrue(app.segmentedControls["task-inbox-filter"].waitForExistence(timeout: 5))
        tabBar.buttons["使命清单"].tap()
        tabBar.buttons["打卡"].tap()
        tabBar.buttons["倒数日"].tap()
    }
}
