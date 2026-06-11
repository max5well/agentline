import XCTest

final class EditorScrollTests: XCTestCase {
    // Regression: the agent editor must scroll all the way down to the
    // memory section (reported broken — screen cut off at Voice).
    func testEditorScrollsToMemoryToggle() {
        let app = XCUIApplication()
        app.launchArguments = ["-screen-editor"]
        app.launch()

        let voiceLabel = app.staticTexts["VOICE"]
        XCTAssertTrue(voiceLabel.waitForExistence(timeout: 5), "editor did not open")
        let before = voiceLabel.frame.minY

        app.swipeUp()
        let after = voiceLabel.frame.minY
        XCTAssertLessThan(after, before - 50, "editor content did not move on swipe")

        app.swipeUp()
        let memoryToggle = app.switches.firstMatch
        XCTAssertTrue(memoryToggle.waitForExistence(timeout: 3), "memory toggle never became visible")
    }
}
