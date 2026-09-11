import XCTest

final class PadNavigationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSidebarHasFourPrimaryModulesAndSettingsIsSecondary() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad, "iPad split navigation is verified on regular-width pad destinations.")
        let app = XCUIApplication()
        app.launch()
        let sidebar = app.descendants(matching: .any)["mobile-sidebar"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 10) || app.buttons["倒数日"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["倒数日"].exists || app.staticTexts["倒数日"].exists)
        XCTAssertTrue(app.buttons["任务清单"].exists || app.staticTexts["任务清单"].exists)
        XCTAssertTrue(app.buttons["使命清单"].exists || app.staticTexts["使命清单"].exists)
        XCTAssertTrue(app.buttons["打卡"].exists || app.staticTexts["打卡"].exists)
        XCTAssertFalse(app.tabBars.buttons["更多"].exists)
        XCTAssertFalse(app.tabBars.buttons["今天"].exists)

        let tasks = app.buttons["任务清单"].exists ? app.buttons["任务清单"] : app.staticTexts["任务清单"]
        tasks.tap()
        let missions = app.buttons["使命清单"].exists ? app.buttons["使命清单"] : app.staticTexts["使命清单"]
        missions.tap()
        let habits = app.buttons["打卡"].exists ? app.buttons["打卡"] : app.staticTexts["打卡"]
        habits.tap()
    }
}
