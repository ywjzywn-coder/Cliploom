import XCTest

final class PasteBoxUITests: XCTestCase {
    func testApplicationLaunches() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(en)",
            "-onboarding.completed", "YES"
        ]
        app.launch()

        XCTAssertNotEqual(app.state, .notRunning)
    }
}
