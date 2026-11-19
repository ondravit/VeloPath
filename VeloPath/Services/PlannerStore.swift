import Foundation
import Observation
import SwiftUI
import VeloCore

/// Single source of truth for the route planner UI.
@MainActor
@Observable
final class PlannerStore {
    enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    // MARK: State

    private(set) var phase: Phase = .loading
    private(set) var waypoints: [Waypoint] = []
    private(set) var route: Route?
    /// Incremented whenever `route` changes – cheap change detection for the map.
    private(set) var routeRevision = 0
    private(set) var isRouting = false
    private(set) var routeError: String?
    private(set) var conditionChunks: [ConditionChunk] = []
    private(set) var metadata: GraphMetadata?
    private(set) var coverage: GeoBounds?
    private(set) var gpxFileURL: URL?
    var toast: Toast?
    /// Whether the condition overlay is actually drawn right now (zoom dependent).
    var conditionLayerOnScreen = false
    /// Height of the bottom sheet, used to keep map content clear of it.
    var sheetHeight: CGFloat = 0
    /// Request for the map to frame something (consumed by the map view).
    private(set) var cameraRequest: CameraRequest?

    var options: RoutingOptions {
        didSet {
            guard options != oldValue else { return }
            persist()
            scheduleRouting()
        }
    }

    var showsConditionLayer: Bool {
        didSet { UserDefaults.standard.set(showsConditionLayer, forKey: Keys.conditionLayer) }
    }

    var mapStyle: MapStyleChoice {
        didSet { UserDefaults.standard.set(mapStyle.rawValue, forKey: Keys.mapStyle) }
    }

    /// Average speed on flat roads in km/h, used for the time estimate.
    var averageSpeed: Double {
        didSet { UserDefaults.standard.set(averageSpeed, forKey: Keys.speed) }
    }

    @ObservationIgnored let location = LocationProvider()
    @ObservationIgnored private var engine: RoutingEngine?
    @ObservationIgnored private var routingTask: Task<Void, Never>?
    @ObservationIgnored private let geocoder = GeocodingService()
    @ObservationIgnored private var demoMode = false

    private enum Keys {
        static let conditionLayer = "map.conditionLayer"
        static let mapStyle = "map.style"
        static let speed = "route.averageSpeed"
    }

    struct CameraRequest: Equatable {
        enum Target: Equatable {
            case coordinates([GeoCoordinate])
            case bounds(GeoBounds)
            case region(center: GeoCoordinate, latitudeDelta: Double)
        }
        let id = UUID()
        let target: Target
        let animated: Bool
    }

    init() {
        let defaults = UserDefaults.standard
        options = PlanStorage.loadPlan()?.options ?? RoutingOptions()
        showsConditionLayer = defaults.object(forKey: Keys.conditionLayer) as? Bool ?? true
        mapStyle = MapStyleChoice(rawValue: defaults.string(forKey: Keys.mapStyle) ?? "") ?? .standard
        let speed = defaults.double(forKey: Keys.speed)
        averageSpeed = speed > 0 ? speed : 25
    }

    // MARK: Lifecycle

    func start() async {
        guard engine == nil else { return }
        do {
            let graph = try await Task.detached(priority: .userInitiated) {
                try RoutingEngine.loadBundledGraph()
            }.value
            let engine = RoutingEngine(graph: graph)
            self.engine = engine
            metadata = graph.metadata
            coverage = graph.bounds
            phase = .ready
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }

        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-uiTestReset") {
            demoMode = true
            UserDefaults.standard.removeObject(forKey: "plan.current.v1")
        }
        if let i = arguments.firstIndex(of: "-uiCamera"), i + 1 < arguments.count {
            let parts = arguments[i + 1].split(separator: ",").compactMap { Double($0) }
            if parts.count == 3 {
                cameraRequest = CameraRequest(target: .region(center: GeoCoordinate(latitude: parts[0], longitude: parts[1]),
                                                              latitudeDelta: parts[2]), animated: false)
            }
        } else if arguments.contains("-uiDemo") {
            demoMode = true
            UserDefaults.standard.removeObject(forKey: "plan.current.v1")
            await loadDemoRoute()
        } else if let plan = PlanStorage.loadPlan(), !plan.waypoints.isEmpty {
            await restore(plan)
        } else {
            showOverview()
        }

        if let engine {
            conditionChunks = await engine.conditionChunks()
        }
    }

    private func restore(_ plan: PlanSnapshot) async {
        guard let engine else { return }
        var restored: [Waypoint] = []
        for var w in plan.waypoints {
            if let p = await engine.snap(w.coordinate, maxDistance: 1000) {
                w.networkPoint = p
                w.coordinate = p.coordinate
                restored.append(w)
            }
        }
        waypoints = restored
        cameraRequest = CameraRequest(target: .coordinates(restored.map(\.coordinate)), animated: false)
        scheduleRouting()
    }

    private func loadDemoRoute() async {
        let long = ProcessInfo.processInfo.arguments.contains("-uiDemoLong")
        let demo = long ? [
            GeoCoordinate(latitude: 50.0875, longitude: 14.4213),   // Praha
            GeoCoordinate(latitude: 49.1951, longitude: 16.6068),   // Brno
        ] : [
            GeoCoordinate(latitude: 50.2093, longitude: 15.8326),   // Hradec Králové
            GeoCoordinate(latitude: 50.3562, longitude: 15.9213),   // Jaroměř
            GeoCoordinate(latitude: 50.4166, longitude: 16.1630),   // Náchod
        ]
        guard let engine else { return }
        var list: [Waypoint] = []
        for c in demo {
            if let p = await engine.snap(c) {
                list.append(Waypoint(coordinate: p.coordinate, networkPoint: p))
            }
        }
        waypoints = list
        options = RoutingOptions(surfacePriority: .best, avoidMainRoads: true)
        cameraRequest = CameraRequest(target: .coordinates(list.map(\.coordinate)), animated: false)
        resolveNames()
        scheduleRouting()
    }

    // MARK: Derived values

    var canRoute: Bool { waypoints.count >= 2 }

    /// Estimated riding time: flat speed plus ~1 minute per 12 m of climbing.
    var estimatedDuration: TimeInterval? {
        guard let route else { return nil }
        let hours = route.distance / 1000 / max(5, averageSpeed)
        return hours * 3600 + route.ascent / 12 * 60
    }

    func role(of waypoint: Waypoint) -> WaypointRole {
        let i = waypoints.firstIndex(of: waypoint) ?? 0
        return WaypointRole.role(at: i, count: waypoints.count)
    }

    /// Distance along the route from the start to each waypoint.
    func distanceFromStart(toWaypointAt index: Int) -> Double? {
        guard let route, index > 0, index <= route.legs.count else { return index == 0 ? 0 : nil }
        return route.legs.prefix(index).reduce(0) { $0 + $1.distance }
    }

    func displayName(for waypoint: Waypoint) -> String {
        waypoint.name ?? String(format: "%.5f, %.5f", waypoint.coordinate.latitude, waypoint.coordinate.longitude)
    }

    // MARK: Editing

    /// Adds a waypoint. Without `index` the point becomes the new destination.
    func addWaypoint(at coordinate: GeoCoordinate, index: Int? = nil, name: String? = nil, frame: Bool = false) {
        Task {
            guard let p = await snapOrWarn(coordinate) else { return }
            let w = Waypoint(coordinate: p.coordinate, name: name, networkPoint: p)
            let insertAt = min(index ?? waypoints.count, waypoints.count)
            waypoints.insert(w, at: insertAt)
            if name == nil { resolveName(of: w.id) }
            if frame { cameraRequest = CameraRequest(target: .coordinates(waypoints.map(\.coordinate)), animated: true) }
            planChanged()
        }
    }

    /// Adds a via point into the leg closest to `coordinate` (used by long press on the route).
    func insertViaPoint(at coordinate: GeoCoordinate) {
        if let route, let nearest = route.nearestLeg(to: coordinate), nearest.distance < 150 {
            addWaypoint(at: coordinate, index: nearest.leg + 1)
        } else {
            addWaypoint(at: coordinate)
        }
    }

    func replaceWaypoint(_ id: UUID, with coordinate: GeoCoordinate, name: String?) {
        Task {
            guard let p = await snapOrWarn(coordinate), let i = waypoints.firstIndex(where: { $0.id == id }) else { return }
            waypoints[i].coordinate = p.coordinate
            waypoints[i].networkPoint = p
            waypoints[i].name = name
            if name == nil { resolveName(of: id) }
            cameraRequest = CameraRequest(target: .coordinates([p.coordinate]), animated: true)
            planChanged()
        }
    }

    func moveWaypoint(_ id: UUID, to coordinate: GeoCoordinate) {
        Task {
            guard let i = waypoints.firstIndex(where: { $0.id == id }) else { return }
            guard let p = await snapOrWarn(coordinate) else {
                // put the dragged marker back where it was
                waypoints[i].coordinate = waypoints[i].coordinate
                return
            }
            guard let j = waypoints.firstIndex(where: { $0.id == id }) else { return }
            waypoints[j].coordinate = p.coordinate
            waypoints[j].networkPoint = p
            waypoints[j].name = nil
            resolveName(of: id)
            planChanged()
        }
    }

    func removeWaypoint(_ id: UUID) {
        waypoints.removeAll { $0.id == id }
        planChanged()
    }

    func removeWaypoints(atOffsets offsets: IndexSet) {
        waypoints.remove(atOffsets: offsets)
        planChanged()
    }

    func moveWaypoints(fromOffsets source: IndexSet, toOffset destination: Int) {
        waypoints.move(fromOffsets: source, toOffset: destination)
        planChanged()
    }

    func reverseRoute() {
        guard waypoints.count >= 2 else { return }
        waypoints.reverse()
        planChanged()
    }

    /// Adds the start as the final destination (ride back home).
    func closeLoop() {
        guard let first = waypoints.first, waypoints.count >= 2, waypoints.last?.coordinate != first.coordinate else { return }
        waypoints.append(Waypoint(coordinate: first.coordinate, name: first.name, networkPoint: first.networkPoint))
        planChanged()
    }

    func clearRoute() {
        waypoints.removeAll()
        planChanged()
    }

    func startFromCurrentLocation() {
        location.requestCurrentLocation { [weak self] coordinate in
            guard let self else { return }
            guard let coordinate else {
                self.showToast("Polohu se nepodařilo zjistit. Povolte přístup k poloze v Nastavení.", "location.slash")
                return
            }
            if let first = self.waypoints.first {
                self.replaceWaypoint(first.id, with: coordinate, name: "Moje poloha")
            } else {
                self.addWaypoint(at: coordinate, index: 0, name: "Moje poloha", frame: true)
            }
        }
    }

    /// Initial view without a plan: around the user if location is allowed, otherwise the covered region.
    private func showOverview() {
        if location.isAuthorized {
            location.requestCurrentLocation { [weak self] c in
                guard let self else { return }
                if let c, self.coverage?.contains(c) ?? false {
                    self.cameraRequest = CameraRequest(target: .region(center: c, latitudeDelta: 0.5), animated: false)
                } else {
                    self.showCoverage()
                }
            }
        } else {
            showCoverage()
        }
    }

    private func showCoverage() {
        guard let coverage else { return }
        let span = coverage.maxLatitude - coverage.minLatitude
        // A portrait phone cannot show a wide country well; favour a readable zoom around its centre.
        cameraRequest = CameraRequest(target: .region(center: coverage.center, latitudeDelta: min(span * 1.6, 4.2)), animated: false)
    }

    func frameRoute() {
        guard !waypoints.isEmpty else {
            showCoverage()
            return
        }
        let coords = route?.points ?? waypoints.map(\.coordinate)
        cameraRequest = CameraRequest(target: .coordinates(coords), animated: true)
    }

    func focus(on waypoint: Waypoint) {
        cameraRequest = CameraRequest(target: .coordinates([waypoint.coordinate]), animated: true)
    }

    func showToast(_ message: String, _ systemImage: String = "info.circle") {
        toast = Toast(message: message, systemImage: systemImage)
    }

    // MARK: Routing

    private func planChanged() {
        persist()
        scheduleRouting()
    }

    private func persist() {
        guard !demoMode else { return }
        PlanStorage.savePlan(PlanSnapshot(waypoints: waypoints, options: options))
    }

    private func scheduleRouting() {
        routingTask?.cancel()
        guard let engine, waypoints.count >= 2 else {
            routingTask = nil
            isRouting = false
            routeError = nil
            if route != nil {
                route = nil
                routeRevision += 1
            }
            gpxFileURL = nil
            return
        }
        let points = waypoints.compactMap(\.networkPoint)
        guard points.count == waypoints.count else { return }
        let options = self.options
        isRouting = true
        routingTask = Task { [weak self] in
            do {
                let result = try await engine.route(through: points, options: options)
                guard !Task.isCancelled, let self else { return }
                self.route = result
                self.routeRevision += 1
                self.routeError = nil
                self.isRouting = false
                self.writeGPX()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.isRouting = false
                self.routeError = error.localizedDescription
                if self.route != nil {
                    self.route = nil
                    self.routeRevision += 1
                }
                self.gpxFileURL = nil
            }
        }
    }

    private func snapOrWarn(_ coordinate: GeoCoordinate) async -> NetworkPoint? {
        guard let engine else { return nil }
        if let coverage, !coverage.contains(coordinate, marginDegrees: 0.01) {
            showToast("Toto místo je mimo oblast s mapovými daty (\(metadata?.region ?? "")).", "map")
            return nil
        }
        if let p = await engine.snap(coordinate) { return p }
        showToast("V okolí není silnice vhodná pro silniční kolo.", "exclamationmark.triangle")
        return nil
    }

    private func resolveNames() {
        for w in waypoints where w.name == nil { resolveName(of: w.id) }
    }

    private func resolveName(of id: UUID) {
        guard let w = waypoints.first(where: { $0.id == id }) else { return }
        let coordinate = w.coordinate
        geocoder.name(for: coordinate) { [weak self] name in
            guard let self, let name, let i = self.waypoints.firstIndex(where: { $0.id == id }),
                  self.waypoints[i].coordinate == coordinate, self.waypoints[i].name == nil else { return }
            self.waypoints[i].name = name
            self.persist()
        }
    }

    // MARK: Export

    var routeTitle: String {
        guard let first = waypoints.first, let last = waypoints.last, waypoints.count >= 2 else { return "Trasa VeloPath" }
        let a = first.name ?? "Start"
        let b = last.name ?? "Cíl"
        if first.coordinate == last.coordinate { return "Okruh – \(a)" }
        return "\(a) → \(b)"
    }

    private func writeGPX() {
        guard let route else { gpxFileURL = nil; return }
        let named = waypoints.enumerated().map { index, w in
            GPXWriter.Waypoint(coordinate: w.coordinate,
                               name: w.name ?? WaypointRole.role(at: index, count: waypoints.count).title)
        }
        let data = GPXWriter().data(name: routeTitle, route: route, waypoints: named)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        let km = Int((route.distance / 1000).rounded())
        let fileName = "VeloPath-\(formatter.string(from: Date()))-\(km)km.gpx"
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gpx", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            // keep only the latest export
            for old in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] {
                try? FileManager.default.removeItem(at: old)
            }
            let url = dir.appendingPathComponent(fileName)
            try data.write(to: url, options: .atomic)
            gpxFileURL = url
        } catch {
            gpxFileURL = nil
        }
    }
}
