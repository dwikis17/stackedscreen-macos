//
//  StackedScreenshotUITests.swift
//  StackedScreenshotUITests
//
//  Created by Dwiki on 03/08/26.
//

import XCTest

final class StackedScreenshotUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testMenuBarPopoverShowsCaptureControls() throws {
        let app = XCUIApplication()
        app.launch()

        let menuBarItem = app.menuBarItems["StackedScreenshotMenuBarItem"]
        XCTAssertTrue(menuBarItem.waitForExistence(timeout: 5))
        menuBarItem.click()

        XCTAssertTrue(app.buttons["Capture Now"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Clear Stack"].exists)

        let shortcuts = app.staticTexts["FixedShortcuts"]
        XCTAssertTrue(shortcuts.waitForExistence(timeout: 5))
        XCTAssertTrue(shortcuts.label.contains("⌥⌘4"))
        XCTAssertTrue(shortcuts.label.contains("⌥⌘⌫"))
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
