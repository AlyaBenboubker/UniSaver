//
//  UniSaverUITests.swift
//  UniSaverUITests
//
//  Created by Alya Benboubker on 31/07/2026.
//

import XCTest

final class UniSaverUITests: XCTestCase {

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
    func testLaunchesOnTodayAndCanOpenClasses() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITestMode"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 5))
        app.staticTexts["Classes"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Classes"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
