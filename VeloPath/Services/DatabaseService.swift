import CoreLocation
import GRDB

/// Read-only actor that manages the GRDB connection to the bundled VeloGraph.sqlite.
/// All public methods are safe to call from any async context.
actor DatabaseService {

    static let shared = DatabaseService()

    private let queue: DatabaseQueue

    private init() {
        guard let url = Bundle.main.url(forResource: "VeloGraph", withExtension: "sqlite") else {
            fatalError("VeloGraph.sqlite not found in app bundle — verify it is added to the target.")
        }
        var config = Configuration()
        config.readonly = true
        // Use the immutable=1 URI flag so SQLite skips .shm/.wal creation,
        // which requires write access that the app bundle does not provide.
        let immutablePath = "file:\(url.path)?immutable=1"
        do {
            queue = try DatabaseQueue(path: immutablePath, configuration: config)
        } catch {
            fatalError("Cannot open VeloGraph.sqlite: \(error)")
        }
    }

    // MARK: - Graph bootstrap

    /// Loads every node from the `nodes` table (~full table scan, done once at startup).
    func loadAllNodes() throws -> [DBNode] {
        try queue.read { db in
            try DBNode.fetchAll(db, sql: "SELECT id, lat, lon FROM nodes")
        }
    }

    /// Loads every edge from the `edges` table (~full table scan, done once at startup).
    func loadAllEdges() throws -> [DBEdge] {
        try queue.read { db in
            try DBEdge.fetchAll(db, sql: """
                SELECT id, from_node, to_node, distance_m, condition FROM edges
                """)
        }
    }

    // MARK: - Segment loading

    /// Loads all segments with their coordinates — used at startup for the map overlay.
    func loadAllSegments() throws -> [DBSegment] {
        try queue.read { db in
            var segments = try Row.fetchAll(db, sql: "SELECT id, condition FROM segments")
                .map { DBSegment(id: $0["id"], condition: $0["condition"]) }

            let coordRows = try Row.fetchAll(db, sql: """
                SELECT segment_id, lat, lon FROM segment_coords
                ORDER BY segment_id, seq
                """)

            var coordMap = [Int64: [CLLocationCoordinate2D]]()
            for row in coordRows {
                let sid: Int64 = row["segment_id"]
                coordMap[sid, default: []].append(
                    .init(latitude: row["lat"], longitude: row["lon"])
                )
            }

            for i in segments.indices {
                segments[i].coords = coordMap[segments[i].id] ?? []
            }
            return segments
        }
    }

    // MARK: - Spatial segment queries (for map rendering)

    /// Returns segments whose bounding boxes intersect the given map viewport.
    /// Uses the `segments_rtree` virtual table for O(log n) spatial filtering.
    func fetchSegments(
        minLat: Double, maxLat: Double,
        minLon: Double, maxLon: Double
    ) throws -> [DBSegment] {
        try queue.read { db in
            // 1. Spatial filter via R-Tree
            let ids: [Int64] = try Row.fetchAll(db, sql: """
                SELECT id FROM segments_rtree
                WHERE min_lat <= :maxLat AND max_lat >= :minLat
                  AND min_lon <= :maxLon AND max_lon >= :minLon
                """, arguments: ["minLat": minLat, "maxLat": maxLat,
                                 "minLon": minLon, "maxLon": maxLon])
                .map { $0["id"] }

            guard !ids.isEmpty else { return [] }

            // 2. Fetch segment metadata
            let placeholders = databaseQuestionMarks(count: ids.count)
            var segments = try Row.fetchAll(db,
                sql: "SELECT id, condition FROM segments WHERE id IN (\(placeholders))",
                arguments: StatementArguments(ids))
                .map { DBSegment(id: $0["id"], condition: $0["condition"]) }

            // 3. Fetch coordinates ordered by seq
            let coordRows = try Row.fetchAll(db, sql: """
                SELECT segment_id, lat, lon FROM segment_coords
                WHERE segment_id IN (\(placeholders))
                ORDER BY segment_id, seq
                """, arguments: StatementArguments(ids))

            // 4. Group coords by segment id
            var coordMap = [Int64: [CLLocationCoordinate2D]]()
            for row in coordRows {
                let sid: Int64 = row["segment_id"]
                coordMap[sid, default: []].append(
                    CLLocationCoordinate2D(latitude: row["lat"], longitude: row["lon"])
                )
            }

            for i in segments.indices {
                segments[i].coords = coordMap[segments[i].id] ?? []
            }
            return segments
        }
    }
}
