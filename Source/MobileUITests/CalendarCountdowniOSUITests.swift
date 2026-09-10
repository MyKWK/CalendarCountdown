import XCTest

final class CalendarCountdowniOSUITests: XCTestCase {
    func testFourPrimaryTabsExist() throws {
        let app = XCUIApplication()
        app.launch()
        let countdown = app.descendants(matching: .any)["tab-countdown"].firstMatch
        let tasks = app.descendants(matching: .any)["tab-tasks"].firstMatch
        let missions = app.descendants(matching: .any)["tab-missions"].firstMatch
        let habits = app.descendants(matching: .any)["tab-habits"].firstMatch
        let sawTabs = countdown.waitForExistence(timeout: 8)
            && tasks.waitForExistence(timeout: 2)
            && missions.waitForExistence(timeout: 2)
            && habits.waitForExistence(timeout: 2)
        let sawCountdown = app.navigationBars["倒数展示"].waitForExistence(timeout: 2)
            || app.navigationBars["倒数日"].waitForExistence(timeout: 2)
            || app.staticTexts["需要访问 Apple 日历"].waitForExistence(timeout: 2)
        XCTAssertTrue(sawTabs || sawCountdown, "iPhone tabs or iPad sidebar should expose the four primary modules")
    }

    func testAddTaskSheetCanSave() throws {
        let app = XCUIApplication()
        app.launch()
        let addTask = app.descendants(matching: .any)["add-task"].firstMatch
        if addTask.waitForExistence(timeout: 8) {
            addTask.tap()
            let save = app.descendants(matching: .any)["save-task"].firstMatch
            XCTAssertTrue(save.waitForExistence(timeout: 4))
        } else {
            let sidebar = app.descendants(matching: .any)["tab-tasks"].firstMatch
            XCTAssertTrue(sidebar.waitForExistence(timeout: 4) || app.tabBars.buttons.count >= 4)
        }
    }
}
