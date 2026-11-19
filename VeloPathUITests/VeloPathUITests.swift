import XCTest

/// End-to-end checks of the planner on the simulator (run by CI).
final class VeloPathUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        // Hradec Králové city centre, ~2 km across
        app.launchArguments = ["-uiTestReset", "-uiCamera", "50.2105,15.8320,0.02"] + extra
        app.launch()
        return app
    }

    func testPlanRouteByTappingAndExport() throws {
        let app = launch()
        let map = app.maps.firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 30))
        sleep(3)

        map.coordinate(withNormalizedOffset: CGVector(dx: 0.30, dy: 0.22)).tap()
        sleep(2)
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.70, dy: 0.40)).tap()

        let export = app.buttons["Exportovat trasu jako GPX"]
        XCTAssertTrue(export.waitForExistence(timeout: 30), "route was not computed")
        attachScreenshot(app, name: "route-by-tapping")

        // a third tap extends the route; the export button must stay available
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.10)).tap()
        sleep(3)
        XCTAssertTrue(export.exists)

        export.tap()
        sleep(3)
        attachScreenshot(app, name: "share-sheet")
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testSearchAddsWaypoint() throws {
        let app = launch()
        let search = app.buttons["Hledat místo"]
        XCTAssertTrue(search.waitForExistence(timeout: 30))
        search.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("Jaroměř")
        let result = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] %@", "Jaroměř")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 20), "no search results")
        result.tap()
        // the sheet now shows the first waypoint
        XCTAssertTrue(app.staticTexts["Start je nastaven"].waitForExistence(timeout: 20))
        attachScreenshot(app, name: "after-search")
    }

    func testSettingsShowAttribution() throws {
        let app = launch()
        let settings = app.buttons["Nastavení"]
        XCTAssertTrue(settings.waitForExistence(timeout: 30))
        settings.tap()
        XCTAssertTrue(app.navigationBars["Nastavení"].waitForExistence(timeout: 10))
        let osm = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "OpenStreetMap")).firstMatch
        for _ in 0..<6 where !osm.exists { app.swipeUp() }
        XCTAssertTrue(osm.exists, "OpenStreetMap attribution missing")
    }

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
}
