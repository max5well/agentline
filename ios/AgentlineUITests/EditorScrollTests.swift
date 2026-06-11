import XCTest

final class EditorScrollTests: XCTestCase {
    // The redesigned editor (DESIGN-SPEC §3.5): Conversation rows reach
    // their sub-screens, and Memory & Context shows the toggle.
    func testEditorConversationRowsNavigate() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-screen-editor"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Edit Agent"].waitForExistence(timeout: 5), "editor did not open")
        for row in ["Language", "Voice", "Model", "Memory & Context"] {
            XCTAssertTrue(app.staticTexts[row].exists, "missing Conversation row: \(row)")
        }

        app.staticTexts["Memory & Context"].tap()
        let toggle = app.switches.firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 3), "memory toggle not shown")
    }

    func testTabsExist() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch()
        for tab in ["Agents", "Recents", "Settings"] {
            XCTAssertTrue(app.tabBars.buttons[tab].waitForExistence(timeout: 5), "missing tab: \(tab)")
        }
        app.tabBars.buttons["Recents"].tap()
        XCTAssertTrue(app.navigationBars["Recents"].waitForExistence(timeout: 3))
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
    }
}
