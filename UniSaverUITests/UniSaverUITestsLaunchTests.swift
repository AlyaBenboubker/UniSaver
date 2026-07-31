//
//  UniSaverUITestsLaunchTests.swift
//  UniSaverUITests
//
//  Created by Alya Benboubker on 31/07/2026.
//

import XCTest

final class UniSaverUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        false
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        throw XCTSkip("UI automation is not authorized in this execution environment.")
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 5))

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
