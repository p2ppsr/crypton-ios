import XCTest
final class CryptonLaunchTests: XCTestCase {
    func testLaunchScreenshot() {
        let app = XCUIApplication(); app.launchArguments = ["--uitesting"]; app.launch()
        XCTAssertTrue(app.buttons["New message"].exists)
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = "Crypton iOS home"; shot.lifetime = .keepAlways; add(shot)
    }
}
