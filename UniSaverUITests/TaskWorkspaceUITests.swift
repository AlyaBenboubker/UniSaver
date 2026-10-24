import XCTest

final class TaskWorkspaceUITests: XCTestCase {
    @MainActor func testNotesChecklistReviewAndReopen() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "alyaben.UniSaver")
        app.launchArguments = ["--p0-validation", "--p0-test-store", UUID().uuidString]
        app.launch()
        if app.windows.count == 0 {
            app.menuBars.menuBarItems["File"].click()
            app.menuItems["New Window"].click()
        }
        let open = app.buttons["openValidationTask"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.click()
        let editor = app.textViews["taskWorkingNotes"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        app.checkBoxes["Solve 2x = 8"].click()
        app.activate()
        editor.click()
        app.activate()
        editor.typeText("My attempt x equals 4 and 2 times 4 equals 8")
        XCTAssertEqual(editor.value as? String, "My attempt x equals 4 and 2 times 4 equals 8")
        XCTAssertEqual(app.staticTexts["taskNotesCharacterCount"].value as? String, "44 characters")
        app.buttons["Start timer"].click()
        app.menuItems["Elapsed"].click()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))
        app.buttons["Agent"].firstMatch.click()
        XCTAssertTrue(app.buttons["Working notes"].waitForExistence(timeout: 5))
        app.buttons["Working notes"].click()
        XCTAssertEqual(editor.value as? String, "My attempt x equals 4 and 2 times 4 equals 8")
        app.buttons["Finish session"].click()
        let save = app.buttons["Save progress"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.click()
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        if app.windows.count == 0 {
            app.menuBars.menuBarItems["File"].click()
            app.menuItems["New Window"].click()
        }
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.click()
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertEqual(editor.value as? String, "My attempt x equals 4 and 2 times 4 equals 8")
        XCTAssertEqual((app.checkBoxes["Solve 2x = 8"].value as? NSNumber)?.intValue, 1)
        app.buttons["Continue later"].click()
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.click()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, "My attempt x equals 4 and 2 times 4 equals 8")
        app.buttons["Back"].click()
        app.terminate()
    }
}
