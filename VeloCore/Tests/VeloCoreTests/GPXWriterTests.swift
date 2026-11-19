import XCTest
@testable import VeloCore

final class GPXWriterTests: XCTestCase {
    func testDocumentStructure() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "hradec", withExtension: "vpg", subdirectory: "Fixtures"))
        let router = Router(graph: try RoadGraph(contentsOf: url))
        let a = try XCTUnwrap(router.snap(GeoCoordinate(latitude: 50.2092, longitude: 15.8327)))
        let b = try XCTUnwrap(router.snap(GeoCoordinate(latitude: 50.2365, longitude: 15.8900)))
        let route = try router.route(through: [a, b], options: RoutingOptions())
        let xml = GPXWriter().document(
            name: "Hradec <test> & \"okruh\"",
            route: route,
            waypoints: [.init(coordinate: a.coordinate, name: "Start"), .init(coordinate: b.coordinate, name: "Cíl")],
            date: Date(timeIntervalSince1970: 1_800_000_000))

        XCTAssertTrue(xml.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"))
        XCTAssertTrue(xml.contains("<name>Hradec &lt;test&gt; &amp; &quot;okruh&quot;</name>"))
        XCTAssertTrue(xml.contains("<time>2027-01-15T08:00:00Z</time>"))
        XCTAssertTrue(xml.contains("<name>Cíl</name>"))
        XCTAssertTrue(xml.contains("<ele>"))
        let trkpts = xml.components(separatedBy: "<trkpt ").count - 1
        XCTAssertGreaterThan(trkpts, 10)
        XCTAssertLessThanOrEqual(trkpts, route.points.count)
        // decimal separator must be a dot regardless of locale
        XCTAssertFalse(xml.contains("lat=\"50,"))

        // the document must be well-formed XML
        let parser = XMLParser(data: Data(xml.utf8))
        XCTAssertTrue(parser.parse(), parser.parserError?.localizedDescription ?? "")
    }
}
