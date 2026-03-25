import Foundation

// ─── Usage ───────────────────────────────────────────────────────────────────

func printUsage() {
    fputs("""
    VeloGraphBuilder — Preprocesses GeoJSON road data into an optimised SQLite graph.

    Usage:
        VeloGraphBuilder <input.geojson> <output.sqlite>

    Example:
        swift run -c release VeloGraphBuilder \\
            /path/to/Silnice_KHK_all_merged.geojson \\
            /path/to/VeloGraph.sqlite

    The output file is safe to commit to the iOS app's Resources folder.
    It replaces the raw GeoJSON bundle asset entirely.

    """, stderr)
}

// ─── Argument validation ─────────────────────────────────────────────────────

guard CommandLine.arguments.count == 3 else {
    printUsage()
    exit(1)
}

let inputPath  = CommandLine.arguments[1]
let outputPath = CommandLine.arguments[2]

guard FileManager.default.fileExists(atPath: inputPath) else {
    fputs("❌  Input file not found: \(inputPath)\n", stderr)
    exit(1)
}

// ─── Pipeline ────────────────────────────────────────────────────────────────

func elapsed(since start: Date) -> String {
    let s = Date().timeIntervalSince(start)
    if s < 60 { return String(format: "%.1f s", s) }
    return String(format: "%.0f m %.0f s", floor(s / 60), s.truncatingRemainder(dividingBy: 60))
}

let totalStart = Date()

print("""
╔═══════════════════════════════════════════╗
║         VeloGraphBuilder  v1.0            ║
╚═══════════════════════════════════════════╝
Input:   \(inputPath)
Output:  \(outputPath)
""")

do {
    // ── Stage 1: Parse GeoJSON ───────────────────────────────────────────────
    var stageStart = Date()
    print("━━━  [1/4]  Parsing GeoJSON  ━━━")
    let parser   = GeoJSONParser()
    let features = try parser.parse(path: inputPath)
    let totalPolylines = features.reduce(0) { $0 + $1.polylines.count }
    print("     ✓  \(features.count) features, \(totalPolylines) polylines  (\(elapsed(since: stageStart)))\n")

    // ── Stage 2: Build graph topology ────────────────────────────────────────
    stageStart = Date()
    print("━━━  [2/4]  Building graph (snap tolerance: 0.0001° ≈ 11 m)  ━━━")
    let builder = GraphBuilder()
    let graph   = builder.build(from: features)
    print("     ✓  \(graph.nodes.count) unique nodes")
    print("     ✓  \(graph.edges.count) directed edges  (\(elapsed(since: stageStart)))\n")

    // ── Stage 3: Write SQLite ─────────────────────────────────────────────────
    stageStart = Date()
    print("━━━  [3/4]  Writing SQLite database  ━━━")
    let writer = SQLiteWriter(path: outputPath)
    try writer.write(graph: graph, features: features)
    print("     ✓  Database committed  (\(elapsed(since: stageStart)))\n")

    // ── Stage 4: Summary ─────────────────────────────────────────────────────
    let attrs   = try FileManager.default.attributesOfItem(atPath: outputPath)
    let bytes   = (attrs[.size] as? Int) ?? 0
    let sizeMB  = Double(bytes) / 1_048_576.0

    print("━━━  [4/4]  Summary  ━━━")
    print("     Nodes:        \(graph.nodes.count)")
    print("     Edges:        \(graph.edges.count)")
    print("     Segments:     \(totalPolylines)")
    print("     File size:    \(String(format: "%.1f", sizeMB)) MB")
    print("     Total time:   \(elapsed(since: totalStart))")
    print("""

  ✅  VeloGraph.sqlite is ready.
      Next step: drag it into VeloPath/Resources in Xcode
      and add it to the iOS app target.
  """)

} catch {
    fputs("\n❌  \(error)\n", stderr)
    exit(1)
}
