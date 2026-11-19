import XCTest
@testable import VeloCore

private struct Fixture: Decodable {
    struct SnapInfo: Decodable {
        let geometry: Int
        let offset: Double
        let distance: Double
    }
    struct Case: Decodable {
        let from: [Double]
        let to: [Double]
        let priority: String
        let avoidMainRoads: Bool
        let snapFrom: SnapInfo
        let snapTo: SnapInfo
        let noRoute: Bool?
        let cost: Double?
        let distance: Double?
    }
    let cases: [Case]
}

final class RouterTests: XCTestCase {
    static var graph: RoadGraph!

    override class func setUp() {
        super.setUp()
        let url = Bundle.module.url(forResource: "hradec", withExtension: "vpg", subdirectory: "Fixtures")!
        graph = try! RoadGraph(contentsOf: url)
    }

    private func loadFixture() throws -> Fixture {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "expected_routes", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    func testGraphLoads() {
        let g = Self.graph!
        XCTAssertGreaterThan(g.nodeCount, 1000)
        XCTAssertGreaterThan(g.geometryCount, 1000)
        XCTAssertEqual(g.metadata.format, "VPGRAPH1")
        XCTAssertFalse(g.metadata.sources.isEmpty)
        XCTAssertTrue(g.bounds.contains(GeoCoordinate(latitude: 50.21, longitude: 15.83)))
    }

    func testLoadingFromDataMatchesMappedFile() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "hradec", withExtension: "vpg", subdirectory: "Fixtures"))
        let g = try RoadGraph(data: Data(contentsOf: url))
        XCTAssertEqual(g.nodeCount, Self.graph.nodeCount)
        XCTAssertEqual(g.coordinateCount, Self.graph.coordinateCount)
    }

    func testRejectsGarbage() {
        XCTAssertThrowsError(try RoadGraph(data: Data(repeating: 7, count: 2048)))
    }

    func testSnapMatchesReference() throws {
        let router = Router(graph: Self.graph)
        for c in try loadFixture().cases {
            for (q, expected) in [(c.from, c.snapFrom), (c.to, c.snapTo)] {
                let p = try XCTUnwrap(router.snap(GeoCoordinate(latitude: q[0], longitude: q[1])))
                XCTAssertEqual(p.geometry, expected.geometry)
                XCTAssertEqual(p.offset, expected.offset, accuracy: 0.01)
                XCTAssertEqual(p.distanceFromQuery, expected.distance, accuracy: 0.01)
            }
        }
    }

    func testRoutesMatchReference() throws {
        let router = Router(graph: Self.graph)
        var checked = 0
        for c in try loadFixture().cases {
            let a = try XCTUnwrap(router.snap(GeoCoordinate(latitude: c.from[0], longitude: c.from[1])))
            let b = try XCTUnwrap(router.snap(GeoCoordinate(latitude: c.to[0], longitude: c.to[1])))
            let options = RoutingOptions(surfacePriority: SurfacePriority(rawValue: c.priority)!,
                                         avoidMainRoads: c.avoidMainRoads)
            if c.noRoute == true {
                XCTAssertThrowsError(try router.leg(from: a, to: b, cost: CostModel(options: options)))
                continue
            }
            let leg = try router.leg(from: a, to: b, cost: CostModel(options: options))
            let expectedCost = try XCTUnwrap(c.cost)
            XCTAssertEqual(leg.cost, expectedCost, accuracy: max(0.01, expectedCost * 1e-6))
            XCTAssertEqual(leg.distance, try XCTUnwrap(c.distance), accuracy: 0.5)
            // geometry sanity
            XCTAssertEqual(leg.points.count, leg.elevations.count)
            XCTAssertEqual(leg.points.count, leg.distances.count)
            XCTAssertEqual(leg.distances.last ?? 0, leg.distance, accuracy: 0.5)
            XCTAssertEqual(leg.pieces.reduce(0) { $0 + $1.length }, leg.distance, accuracy: 0.5)
            XCTAssertEqual(Geo.distance(leg.points.first!, a.coordinate), 0, accuracy: 0.5)
            XCTAssertEqual(Geo.distance(leg.points.last!, b.coordinate), 0, accuracy: 0.5)
            checked += 1
        }
        XCTAssertGreaterThan(checked, 15)
    }

    func testRouterIsReusable() throws {
        let router = Router(graph: Self.graph)
        let a = try XCTUnwrap(router.snap(GeoCoordinate(latitude: 50.2092, longitude: 15.8327)))
        let b = try XCTUnwrap(router.snap(GeoCoordinate(latitude: 50.2365, longitude: 15.8900)))
        let model = CostModel(options: RoutingOptions())
        let first = try router.leg(from: a, to: b, cost: model)
        for _ in 0..<5 {
            let again = try router.leg(from: a, to: b, cost: model)
            XCTAssertEqual(first.cost, again.cost, accuracy: 1e-9)
        }
        let back = try router.leg(from: b, to: a, cost: model)
        XCTAssertGreaterThan(back.distance, 0)
    }

    func testCancellation() throws {
        let router = Router(graph: Self.graph)
        let a = try XCTUnwrap(router.snap(GeoCoordinate(latitude: 50.17, longitude: 15.80)))
        let b = try XCTUnwrap(router.snap(GeoCoordinate(latitude: 50.29, longitude: 15.96)))
        XCTAssertThrowsError(try router.leg(from: a, to: b, cost: CostModel(options: RoutingOptions()), isCancelled: { true })) { error in
            XCTAssertEqual(error as? RoutingError, .cancelled)
        }
    }

    func testSnapFarAwayFails() {
        let router = Router(graph: Self.graph)
        XCTAssertNil(router.snap(GeoCoordinate(latitude: 48.0, longitude: 12.0)))
    }

    func testMultiLegRoute() throws {
        let router = Router(graph: Self.graph)
        let pts = [
            GeoCoordinate(latitude: 50.2092, longitude: 15.8327),
            GeoCoordinate(latitude: 50.2365, longitude: 15.8900),
            GeoCoordinate(latitude: 50.1700, longitude: 15.8000),
        ].compactMap { router.snap($0) }
        XCTAssertEqual(pts.count, 3)
        guard pts.count == 3 else { return }
        let route = try router.route(through: pts, options: RoutingOptions(surfacePriority: .best))
        XCTAssertEqual(route.legs.count, 2)
        XCTAssertEqual(route.distance, route.legs[0].distance + route.legs[1].distance, accuracy: 1e-6)
        XCTAssertEqual(route.points.count, route.legs[0].points.count + route.legs[1].points.count - 1)
        XCTAssertEqual(route.distances.last ?? 0, route.distance, accuracy: 1)
        XCTAssertEqual(route.legStartIndices.count, 2)
        let breakdown = route.conditionBreakdown.values.reduce(0, +)
        XCTAssertEqual(breakdown, route.distance, accuracy: 1)
        let profile = route.elevationProfile(maxSamples: 100)
        XCTAssertGreaterThan(profile.count, 50)
        XCTAssertTrue(profile.allSatisfy { $0.elevation > 150 && $0.elevation < 500 })
        XCTAssertGreaterThanOrEqual(route.ascent, 0)
        let nearest = try XCTUnwrap(route.nearestLeg(to: route.points[route.points.count - 3]))
        XCTAssertEqual(nearest.leg, 1)
    }

    func testOneWayStreetsAreRespected() throws {
        // every forward edge of a one-way geometry must have no reverse counterpart
        let g = Self.graph!
        var oneWays = 0
        for geom in 0..<g.geometryCount {
            let d = g.allowedDirections(ofGeometry: geom)
            XCTAssertTrue(d.forward || d.backward, "geometry \(geom) not traversable")
            if d.forward != d.backward { oneWays += 1 }
        }
        XCTAssertGreaterThan(oneWays, 10)
    }

    func testClimbHysteresis() {
        let flatNoise = [200.0, 202, 199, 201, 200, 203, 200]
        XCTAssertEqual(Router.climb(of: flatNoise, threshold: 4).ascent, 0)
        let hill = [200.0, 205, 210, 220, 215, 230, 210, 200]
        let c = Router.climb(of: hill, threshold: 4)
        XCTAssertEqual(c.ascent, 35, accuracy: 1e-9)   // 200→220, 215→230
        XCTAssertEqual(c.descent, 35, accuracy: 1e-9)  // 220→215, 230→210→200
    }

    func testRoutingPerformance() throws {
        let router = Router(graph: Self.graph)
        let a = try XCTUnwrap(router.snap(GeoCoordinate(latitude: 50.17, longitude: 15.80)))
        let b = try XCTUnwrap(router.snap(GeoCoordinate(latitude: 50.29, longitude: 15.96)))
        let model = CostModel(options: RoutingOptions(surfacePriority: .best))
        measure {
            _ = try? router.leg(from: a, to: b, cost: model)
        }
    }
}
