import XCTest

// Walks the app on a simulator and saves a screenshot of each screen, so the UI can be seen without a Mac.
final class ScreenshotTests: XCTestCase {
	private var app: XCUIApplication!
	private var output: URL?

	override func setUpWithError() throws {
		continueAfterFailure = false
		if let directory = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !directory.isEmpty {
			output = URL(fileURLWithPath: directory, isDirectory: true)
			try FileManager.default.createDirectory(at: output!, withIntermediateDirectories: true)
		}
		app = XCUIApplication()
		app.launchArguments = ["--reset-library", "--ui-testing"]
		app.launch()
	}

	func test_walkthrough_screens() throws {
		XCTAssertTrue(app.navigationBars["My routines"].waitForExistence(timeout: 10))
		try snap("01-home-empty")
		XCTAssertFalse(app.buttons["Use this routine"].exists)
		app.buttons["New routine"].tap()
		XCTAssertTrue(app.navigationBars["New routine"].waitForExistence(timeout: 10))
		XCTAssertTrue(app.textFields["editor.name"].exists || app.textViews["editor.name"].exists)
		try snap("02-new-page")
		app.buttons["Cancel"].tap()
		XCTAssertFalse(app.buttons["Open My new routine"].exists)
		app.buttons["New routine"].tap()
		element("editor.add-block").tap()
		XCTAssertTrue(app.navigationBars["Add block"].waitForExistence(timeout: 10))
		try snap("03-block-picker")
		element("add.checklist").tap()
		XCTAssertTrue(app.buttons["block.checklist"].waitForExistence(timeout: 10))
		try snap("04-page-editor")
		app.buttons["Save"].tap()
		XCTAssertTrue(app.buttons["Open My new routine"].waitForExistence(timeout: 10))
		try snap("05-home-with-routine")
		app.buttons["Edit My new routine"].tap()
		XCTAssertTrue(app.navigationBars["My new routine"].waitForExistence(timeout: 10))
		XCTAssertTrue(app.textFields["page.name"].waitForExistence(timeout: 10))
		XCTAssertFalse(app.navigationBars["Edit routine"].exists)
		try snap("09-routine-inline-edit")
		// The fixed footer is visible; bypass XCTest trying to scroll its accessibility node.
		app.buttons["page.add-block"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
		app.buttons["Note"].tap()
		app.buttons["Cancel"].tap()
		XCTAssertFalse(app.staticTexts["A note to myself"].exists)
		app.buttons["tool.edit"].tap()
		app.buttons["page.add-block"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
		app.buttons["Note"].tap()
		app.buttons["Save"].tap()
		XCTAssertTrue(app.staticTexts["A note to myself"].waitForExistence(timeout: 10))
		try snap("10-routine-after-save")
		app.navigationBars["My new routine"].buttons["My routines"].tap()
		app.swipeUp()
		element("home.groups").tap()
		XCTAssertTrue(app.navigationBars["App groups"].waitForExistence(timeout: 10))
		try snap("06-app-groups")
		let name = app.textFields["groups.new"]
		name.tap(); name.typeText("Distractions")
		app.buttons["Add"].tap()
		app.swipeDown()
		let group = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "group.")).firstMatch
		XCTAssertTrue(group.waitForExistence(timeout: 10)); group.tap()
		XCTAssertTrue(app.navigationBars["Distractions"].waitForExistence(timeout: 10))
		try snap("07-choose-apps")
	}

	func test_home_allowance_can_be_edited() throws {
		app.terminate()
		app.launchEnvironment["POCKETWORK_UI_LIBRARY"] = """
		{"schema_version":1,"tools":[{"updated_at":"2026-09-13T00:00:00.000Z","document":{"schema_version":2,"id":"home-distraction-allowance","name":"Home distraction allowance","description":"Only distraction time at home counts.","enabled":false,"rules":{"block_during_focus":true,"notify_on_complete":false},"blocks":[{"id":"heading","type":"heading","title":"Home allowance","subtitle":""},{"id":"schedule","type":"schedule","title":"Weekly windows","days":[1,2,3,4,5,6,7],"start":"00:00","end":"23:59"},{"id":"shield","type":"screen_time","title":"Distractions","mode":"block","groups":["Distractions"]}],"home_allowance":{"timezone":"America/Los_Angeles","away_usage_counts":false,"outside_windows":"block_at_home","rules":[{"days":[2,3,4,5],"allowance_minutes":30,"windows":[{"start":"18:00","end":"18:30"},{"start":"19:00","end":"20:50"}]},{"days":[6],"allowance_minutes":120,"windows":[{"start":"14:30","end":"20:20"}]},{"days":[1,7],"allowance_minutes":180,"windows":[{"start":"06:30","end":"20:30"}]}]}}}],"groups":[{"id":"distractions","name":"Distractions"}]}
		"""
		app.launch()
		element("home.edit.home-distraction-allowance").tap()
		XCTAssertTrue(app.navigationBars["Home allowance"].waitForExistence(timeout: 10))
		try snap("08-home-allowance-editor")
		let allowance = app.buttons["home.allowance.2-Increment"]
		allowance.tap()
		XCTAssertEqual(allowance.value as? String, "35 minutes")
		app.buttons["Save"].tap()
		XCTAssertTrue(app.buttons["tool.edit"].waitForExistence(timeout: 10))
		app.buttons["tool.edit"].tap()
		XCTAssertTrue(allowance.waitForExistence(timeout: 10))
		XCTAssertEqual(allowance.value as? String, "35 minutes")
		allowance.tap()
		app.buttons["Cancel"].tap()
		app.buttons["tool.edit"].tap()
		XCTAssertEqual(allowance.value as? String, "35 minutes")
		app.buttons["Cancel"].tap()
		app.navigationBars["Home allowance"].buttons["My routines"].tap()
		app.swipeUp()
		element("home.group.distractions").tap()
		XCTAssertTrue(app.navigationBars["Distractions"].waitForExistence(timeout: 10))
	}

	// SwiftUI exposes list rows and toolbar items as different element types; a typed query per kind stays fast.
	private func element(_ identifier: String) -> XCUIElement {
		let candidates = [app.buttons[identifier], app.cells[identifier], app.otherElements[identifier], app.staticTexts[identifier]]
		for candidate in candidates where candidate.waitForExistence(timeout: 5) { return candidate }
		XCTFail("Missing \(identifier)")
		return candidates[0]
	}

	private func snap(_ name: String) throws {
		let screenshot = app.screenshot()
		let attachment = XCTAttachment(screenshot: screenshot)
		attachment.name = name
		attachment.lifetime = .keepAlways
		add(attachment)
		if let output { try screenshot.pngRepresentation.write(to: output.appendingPathComponent("\(name).png")) }
	}

	func test_connected_behaviors() throws {
		app.terminate()
		let fixture = #"""
{"schema_version": 1, "tools": [{"document": {"schema_version": 3, "id": "behavior-test-id", "name": "Gym check-ins", "description": "", "blocks": [{"id": "heading", "type": "heading", "title": "Gym check-ins", "subtitle": ""}], "rules": {"block_during_focus": false, "notify_on_complete": false}, "behaviors": {"nodes": [{"id": "tap", "kind": "check_in", "x": 0, "y": 0, "config": {"label": "Check in", "value": 1, "minutes": 5, "time": "18:00", "days": [1, 2, 3, 4, 5, 6, 7], "message": "Goal reached", "operator": "gte"}}, {"id": "count", "kind": "count", "x": 0, "y": 0, "config": {"label": "Visits", "value": 1, "minutes": 5, "time": "18:00", "days": [1, 2, 3, 4, 5, 6, 7], "message": "Goal reached", "operator": "gte"}}, {"id": "goal", "kind": "goal", "x": 0, "y": 0, "config": {"label": "Visit goal", "value": 2, "minutes": 5, "time": "18:00", "days": [1, 2, 3, 4, 5, 6, 7], "message": "Goal reached", "operator": "gte"}}, {"id": "message", "kind": "reminder", "x": 0, "y": 0, "config": {"label": "Reminder", "value": 1, "minutes": 5, "time": "18:00", "days": [1, 2, 3, 4, 5, 6, 7], "message": "Goal reached", "operator": "gte"}}], "connections": [{"from": "tap", "output": "done", "to": "count", "input": "increment"}, {"from": "count", "output": "value", "to": "goal", "input": "value"}, {"from": "goal", "output": "reached", "to": "message", "input": "send"}]}}, "updated_at": "2026-09-13T12:00:00.000Z"}]}
"""#.replacingOccurrences(of: "behavior-test-id", with: UUID().uuidString)
		app.launchEnvironment["POCKETWORK_UI_LIBRARY"] = fixture
		app.launch()
		XCTAssertTrue(app.buttons["Open Gym check-ins"].waitForExistence(timeout: 10))
		app.buttons["Open Gym check-ins"].tap()
		XCTAssertTrue(app.buttons["behavior.tap"].waitForExistence(timeout: 10))
		app.buttons["behavior.tap"].tap()
		app.buttons["behavior.tap"].tap()
		XCTAssertTrue(app.staticTexts["Goal reached"].waitForExistence(timeout: 10))
		try snap("11-connected-behaviors")
	}
	func test_build_logic_on_phone() throws {
		app.buttons["New routine"].tap()
		element("editor.logic").tap()
		XCTAssertTrue(app.navigationBars["Logic"].waitForExistence(timeout: 10))
		for (kind, title) in [("button", "Button"), ("reminder", "Reminder")] {
			element("logic.add").tap()
			let search = app.searchFields.firstMatch
			XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText(title)
			element("logic.add.\(kind)").tap()
			XCTAssertTrue(app.navigationBars["Logic"].waitForExistence(timeout: 10))
		}
		try snap("12-native-logic-before-connect")
		app.buttons["Find a block"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap(); app.buttons["Button"].tap()
		let source = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@", "logic.port.", ".pressed")).firstMatch
		XCTAssertTrue(source.waitForExistence(timeout: 10)); XCTAssertTrue(source.isHittable); source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
		XCTAssertTrue(app.navigationBars["Connect blocks"].waitForExistence(timeout: 10))
		let connection = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@", "logic.connect.", ".send")).firstMatch
		XCTAssertTrue(connection.waitForExistence(timeout: 10)); connection.tap()
		try snap("12-native-logic-canvas")
		app.buttons["logic.apply"].tap()
		app.buttons["Save"].tap()
		XCTAssertTrue(app.buttons["Open My new routine"].waitForExistence(timeout: 10))
		app.buttons["Open My new routine"].tap()
		let tap = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "behavior.")).firstMatch
		XCTAssertTrue(tap.waitForExistence(timeout: 10)); tap.tap()
		XCTAssertTrue(app.staticTexts["Time for your routine."].waitForExistence(timeout: 10))
		app.buttons["tool.edit"].tap(); element("editor.logic").tap()
		XCTAssertTrue(app.staticTexts["2 blocks · 1 connections"].waitForExistence(timeout: 10))
		app.buttons["Find a block"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap(); app.buttons["Reminder"].tap()
		try snap("13-native-logic-find-block")
		// Find a block scrolls the canvas to the node with animation; wait until the node's button has settled on screen before tapping.
		let edit_reminder = app.buttons["Edit Reminder"]
		XCTAssertTrue(edit_reminder.waitForExistence(timeout: 10))
		let settled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: edit_reminder)
		XCTAssertEqual(XCTWaiter().wait(for: [settled], timeout: 10), .completed, "Edit Reminder never became hittable after Find a block")
		edit_reminder.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
		let name = app.textFields["logic.label"]
		XCTAssertTrue(name.waitForExistence(timeout: 10)); name.tap(); name.typeText(" edited")
		app.buttons["Done"].tap()
		app.buttons["Back"].tap()
		app.buttons["Discard changes"].tap()
		app.buttons["Cancel"].tap()
		XCTAssertFalse(app.staticTexts["Reminder edited"].exists)
	}

}
