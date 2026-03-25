import Foundation
import SQLite3

// ─── Error type ──────────────────────────────────────────────────────────────

enum SQLiteError: Error, CustomStringConvertible {
    case cannotOpen(String)
    case exec(String)
    case prepare(String)
    case step(String)

    var description: String {
        switch self {
        case .cannotOpen(let p): return "Cannot open database at '\(p)'"
        case .exec(let m):       return "sqlite3_exec failed: \(m)"
        case .prepare(let s):    return "sqlite3_prepare_v2 failed for: \(s)"
        case .step(let m):       return "sqlite3_step failed: \(m)"
        }
    }
}

// ─── Writer ──────────────────────────────────────────────────────────────────

final class SQLiteWriter {

    private let path: String

    init(path: String) {
        self.path = path
    }

    /// Writes the full graph + original segment geometry to a new SQLite file.
    /// Replaces any existing file at `path`.
    func write(graph: BuiltGraph, features: [ParsedFeature]) throws {

        // Remove stale file so we always start with a clean database.
        try? FileManager.default.removeItem(atPath: path)

        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK, let db else {
            throw SQLiteError.cannotOpen(path)
        }
        defer { sqlite3_close(db) }

        // ── Performance pragmas ───────────────────────────────────────────────
        // Applied before any writes; dramatically reduces write time.
        try exec(db, "PRAGMA journal_mode = WAL")
        try exec(db, "PRAGMA synchronous  = NORMAL")
        try exec(db, "PRAGMA temp_store   = MEMORY")
        try exec(db, "PRAGMA cache_size   = -65536")   // 64 MB page cache
        try exec(db, "PRAGMA mmap_size    = 268435456") // 256 MB mmap window

        // ── Schema ───────────────────────────────────────────────────────────
        print("      Creating schema…")
        try createSchema(db)

        // ── Single transaction for all inserts ───────────────────────────────
        // Wrapping everything in ONE transaction is the critical performance
        // lever for SQLite — reduces fsync calls from N to 1.
        try exec(db, "BEGIN TRANSACTION")

        print("      Inserting \(graph.nodes.count) nodes…")
        try writeNodes(db, nodes: graph.nodes)

        print("      Inserting \(graph.edges.count) directed edges…")
        try writeEdges(db, edges: graph.edges)

        let totalPolylines = features.reduce(0) { $0 + $1.polylines.count }
        print("      Inserting \(features.count) features / \(totalPolylines) segments…")
        try writeSegments(db, features: features)

        try writeMetadata(db, graph: graph)

        try exec(db, "COMMIT")

        // ── Post-write optimisation ──────────────────────────────────────────
        print("      Running PRAGMA optimize + VACUUM…")
        try exec(db, "PRAGMA optimize")
        // VACUUM rewrites the file to be as compact as possible.
        // It must run outside a transaction.
        try exec(db, "VACUUM")
    }

    // ─── Schema ──────────────────────────────────────────────────────────────

    private func createSchema(_ db: OpaquePointer) throws {
        // sqlite3_exec supports multiple statements separated by semicolons.
        let ddl = """
        CREATE TABLE metadata (
            key   TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );

        CREATE TABLE nodes (
            id  INTEGER PRIMARY KEY,
            lat REAL    NOT NULL,
            lon REAL    NOT NULL
        );

        CREATE VIRTUAL TABLE nodes_rtree USING rtree (
            id,
            min_lat, max_lat,
            min_lon, max_lon
        );

        CREATE TABLE edges (
            id          INTEGER PRIMARY KEY,
            from_node   INTEGER NOT NULL,
            to_node     INTEGER NOT NULL,
            distance_m  REAL    NOT NULL,
            condition   INTEGER NOT NULL
        );
        CREATE INDEX edges_from ON edges(from_node);
        CREATE INDEX edges_to   ON edges(to_node);

        CREATE TABLE segments (
            id        INTEGER PRIMARY KEY,
            condition INTEGER NOT NULL
        );

        CREATE VIRTUAL TABLE segments_rtree USING rtree (
            id,
            min_lat, max_lat,
            min_lon, max_lon
        );

        CREATE TABLE segment_coords (
            segment_id INTEGER NOT NULL,
            seq        INTEGER NOT NULL,
            lat        REAL    NOT NULL,
            lon        REAL    NOT NULL,
            PRIMARY KEY (segment_id, seq)
        );
        """
        try exec(db, ddl)
    }

    // ─── Nodes ───────────────────────────────────────────────────────────────

    private func writeNodes(_ db: OpaquePointer, nodes: [BuiltNode]) throws {
        let nodeSQL  = "INSERT INTO nodes (id, lat, lon) VALUES (?, ?, ?)"
        let rtreeSQL = """
            INSERT INTO nodes_rtree (id, min_lat, max_lat, min_lon, max_lon)
            VALUES (?, ?, ?, ?, ?)
            """

        let nodeStmt  = try prepare(db, nodeSQL)
        let rtreeStmt = try prepare(db, rtreeSQL)
        defer { sqlite3_finalize(nodeStmt); sqlite3_finalize(rtreeStmt) }

        for node in nodes {
            // nodes table
            sqlite3_bind_int64(nodeStmt,  1, node.id)
            sqlite3_bind_double(nodeStmt, 2, node.lat)
            sqlite3_bind_double(nodeStmt, 3, node.lon)
            try step(db, nodeStmt, sql: nodeSQL)
            sqlite3_reset(nodeStmt)
            sqlite3_clear_bindings(nodeStmt)

            // R-Tree (point: min == max)
            sqlite3_bind_int64(rtreeStmt,  1, node.id)
            sqlite3_bind_double(rtreeStmt, 2, node.lat)   // min_lat
            sqlite3_bind_double(rtreeStmt, 3, node.lat)   // max_lat
            sqlite3_bind_double(rtreeStmt, 4, node.lon)   // min_lon
            sqlite3_bind_double(rtreeStmt, 5, node.lon)   // max_lon
            try step(db, rtreeStmt, sql: rtreeSQL)
            sqlite3_reset(rtreeStmt)
            sqlite3_clear_bindings(rtreeStmt)
        }
    }

    // ─── Edges ───────────────────────────────────────────────────────────────

    private func writeEdges(_ db: OpaquePointer, edges: [BuiltEdge]) throws {
        let sql = """
            INSERT INTO edges (from_node, to_node, distance_m, condition)
            VALUES (?, ?, ?, ?)
            """
        let stmt = try prepare(db, sql)
        defer { sqlite3_finalize(stmt) }

        for edge in edges {
            sqlite3_bind_int64(stmt,  1, edge.fromNode)
            sqlite3_bind_int64(stmt,  2, edge.toNode)
            sqlite3_bind_double(stmt, 3, edge.distanceM)
            sqlite3_bind_int64(stmt,  4, Int64(edge.condition))
            try step(db, stmt, sql: sql)
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
        }
    }

    // ─── Segments ────────────────────────────────────────────────────────────

    private func writeSegments(_ db: OpaquePointer, features: [ParsedFeature]) throws {
        let segSQL = """
            INSERT INTO segments (id, condition) VALUES (?, ?)
            """
        let rtreeSQL = """
            INSERT INTO segments_rtree (id, min_lat, max_lat, min_lon, max_lon)
            VALUES (?, ?, ?, ?, ?)
            """
        let coordSQL = """
            INSERT INTO segment_coords (segment_id, seq, lat, lon)
            VALUES (?, ?, ?, ?)
            """

        let segStmt   = try prepare(db, segSQL)
        let rtreeStmt = try prepare(db, rtreeSQL)
        let coordStmt = try prepare(db, coordSQL)
        defer {
            sqlite3_finalize(segStmt)
            sqlite3_finalize(rtreeStmt)
            sqlite3_finalize(coordStmt)
        }

        var segID: Int64 = 0
        var progress = 0
        let total = features.reduce(0) { $0 + $1.polylines.count }
        let progressStep = max(1, total / 20)

        for feature in features {
            let cond = Int64(feature.condition.rawValue)

            for polyline in feature.polylines {
                guard !polyline.isEmpty else { continue }

                // Compute bounding box for segments_rtree
                var minLat = polyline[0].lat, maxLat = polyline[0].lat
                var minLon = polyline[0].lon, maxLon = polyline[0].lon
                for pt in polyline.dropFirst() {
                    if pt.lat < minLat { minLat = pt.lat }
                    if pt.lat > maxLat { maxLat = pt.lat }
                    if pt.lon < minLon { minLon = pt.lon }
                    if pt.lon > maxLon { maxLon = pt.lon }
                }

                // segments row
                sqlite3_bind_int64(segStmt, 1, segID)
                sqlite3_bind_int64(segStmt, 2, cond)
                try step(db, segStmt, sql: segSQL)
                sqlite3_reset(segStmt)
                sqlite3_clear_bindings(segStmt)

                // segments_rtree row
                sqlite3_bind_int64(rtreeStmt,  1, segID)
                sqlite3_bind_double(rtreeStmt, 2, minLat)
                sqlite3_bind_double(rtreeStmt, 3, maxLat)
                sqlite3_bind_double(rtreeStmt, 4, minLon)
                sqlite3_bind_double(rtreeStmt, 5, maxLon)
                try step(db, rtreeStmt, sql: rtreeSQL)
                sqlite3_reset(rtreeStmt)
                sqlite3_clear_bindings(rtreeStmt)

                // segment_coords rows (original precision — not snapped)
                for (seq, pt) in polyline.enumerated() {
                    sqlite3_bind_int64(coordStmt,  1, segID)
                    sqlite3_bind_int64(coordStmt,  2, Int64(seq))
                    sqlite3_bind_double(coordStmt, 3, pt.lat)
                    sqlite3_bind_double(coordStmt, 4, pt.lon)
                    try step(db, coordStmt, sql: coordSQL)
                    sqlite3_reset(coordStmt)
                    sqlite3_clear_bindings(coordStmt)
                }

                segID += 1
                progress += 1
                if progress % progressStep == 0 {
                    let pct = Int(Double(progress) / Double(total) * 100)
                    print("      \(pct)%  — segments written: \(segID)")
                }
            }
        }
    }

    // ─── Metadata ────────────────────────────────────────────────────────────

    private func writeMetadata(_ db: OpaquePointer, graph: BuiltGraph) throws {
        let sql  = "INSERT INTO metadata (key, value) VALUES (?, ?)"
        let stmt = try prepare(db, sql)
        defer { sqlite3_finalize(stmt) }

        let pairs: [(String, String)] = [
            ("schema_version", "1"),
            ("build_date",     ISO8601DateFormatter().string(from: Date())),
            ("node_count",     "\(graph.nodes.count)"),
            ("edge_count",     "\(graph.edges.count)"),
            ("snap_tolerance", "0.0001deg"),
            // Condition integer encoding for future readers
            ("condition_0",    "excellent"),
            ("condition_1",    "good"),
            ("condition_2",    "satisfactory"),
            ("condition_3",    "unsatisfactory"),
            ("condition_4",    "emergency"),
            ("condition_5",    "superemergency"),
            ("condition_6",    "unknown"),
        ]

        for (key, value) in pairs {
            sqlite3_bind_text(stmt, 1, key,   -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_text(stmt, 2, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            try step(db, stmt, sql: sql)
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
        }
    }

    // ─── SQLite helpers ──────────────────────────────────────────────────────

    /// Executes one or more semicolon-separated SQL statements with no result rows.
    @discardableResult
    private func exec(_ db: OpaquePointer, _ sql: String) throws -> Int32 {
        var errMsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if rc != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "code \(rc)"
            sqlite3_free(errMsg)
            throw SQLiteError.exec(msg)
        }
        return rc
    }

    private func prepare(_ db: OpaquePointer, _ sql: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw SQLiteError.prepare("\(sql) — \(msg)")
        }
        return stmt
    }

    private func step(_ db: OpaquePointer, _ stmt: OpaquePointer, sql: String) throws {
        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw SQLiteError.step("rc=\(rc) — \(msg) — SQL: \(sql.prefix(80))")
        }
    }
}
