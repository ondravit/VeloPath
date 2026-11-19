import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum RoadGraphError: Error, LocalizedError, Equatable {
    case cannotOpen(String)
    case invalidFormat(String)

    public var errorDescription: String? {
        switch self {
        case .cannotOpen(let s): return "Mapová data nelze otevřít (\(s))."
        case .invalidFormat(let s): return "Mapová data jsou poškozená (\(s))."
        }
    }
}

/// Description of one data source, stored in the graph's metadata block.
public struct GraphDataSource: Codable, Sendable, Hashable, Identifiable {
    public var name: String
    public var attribution: String
    public var license: String?
    public var url: String?
    public var date: String?
    public var years: [Int]?
    public var id: String { name }
}

public struct GraphMetadata: Codable, Sendable, Hashable {
    public var format: String?
    public var region: String
    public var built: String
    public var profile: String?
    public var sources: [GraphDataSource]
}

/// Read-only road graph backed by a memory-mapped `VPGRAPH1` file
/// (format: docs/graph-format.md). Loading is O(1); pages are read lazily by the OS.
///
/// The type is immutable after initialisation and therefore safe to share between threads.
public final class RoadGraph: @unchecked Sendable {
    public static let reversedBit: UInt32 = 0x8000_0000

    public let nodeCount: Int
    public let edgeCount: Int
    public let geometryCount: Int
    public let coordinateCount: Int
    public let bounds: GeoBounds
    public let metadata: GraphMetadata

    // CSR graph
    let nodeLat: UnsafeBufferPointer<Int32>
    let nodeLon: UnsafeBufferPointer<Int32>
    let firstEdge: UnsafeBufferPointer<UInt32>
    let edgeTarget: UnsafeBufferPointer<UInt32>
    let edgeGeometry: UnsafeBufferPointer<UInt32>
    // geometries
    let geomLength: UnsafeBufferPointer<Float32>
    let geomAttr: UnsafeBufferPointer<UInt16>
    let geomYear: UnsafeBufferPointer<UInt8>
    let geomAscent: UnsafeBufferPointer<UInt16>
    let geomDescent: UnsafeBufferPointer<UInt16>
    let geomFirstCoord: UnsafeBufferPointer<UInt32>
    let geomNodeU: UnsafeBufferPointer<UInt32>
    let geomNodeV: UnsafeBufferPointer<UInt32>
    let coordLat: UnsafeBufferPointer<Int32>
    let coordLon: UnsafeBufferPointer<Int32>
    let coordEle: UnsafeBufferPointer<Int16>
    // spatial grid
    let gridCellStart: UnsafeBufferPointer<UInt32>
    let gridItems: UnsafeBufferPointer<UInt32>
    let gridRows: Int
    let gridCols: Int
    let gridOriginLat: Double
    let gridOriginLon: Double
    let gridCellLat: Double
    let gridCellLon: Double

    private let storage: Storage

    /// Owns the mapped (or allocated) bytes.
    private final class Storage {
        let base: UnsafeRawPointer
        let size: Int
        let isMapped: Bool
        init(base: UnsafeRawPointer, size: Int, isMapped: Bool) {
            self.base = base
            self.size = size
            self.isMapped = isMapped
        }
        deinit {
            if isMapped {
                munmap(UnsafeMutableRawPointer(mutating: base), size)
            } else {
                UnsafeMutableRawPointer(mutating: base).deallocate()
            }
        }
    }

    /// Memory-maps the graph file at `url`.
    public convenience init(contentsOf url: URL) throws {
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { throw RoadGraphError.cannotOpen(url.lastPathComponent) }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0, st.st_size > 0 else { throw RoadGraphError.cannotOpen(url.lastPathComponent) }
        let size = Int(st.st_size)
        guard let ptr = mmap(nil, size, PROT_READ, MAP_PRIVATE, fd, 0),
              ptr != UnsafeMutableRawPointer(bitPattern: -1) else {
            throw RoadGraphError.cannotOpen(url.lastPathComponent)
        }
        try self.init(storage: Storage(base: UnsafeRawPointer(ptr), size: size, isMapped: true))
    }

    /// Copies `data` into memory owned by the graph (used by tests and previews).
    public convenience init(data: Data) throws {
        guard !data.isEmpty else { throw RoadGraphError.invalidFormat("empty") }
        let mem = UnsafeMutableRawPointer.allocate(byteCount: data.count, alignment: 16)
        data.withUnsafeBytes { raw in
            mem.copyMemory(from: raw.baseAddress!, byteCount: data.count)
        }
        try self.init(storage: Storage(base: UnsafeRawPointer(mem), size: data.count, isMapped: false))
    }

    private struct Section {
        let offset: Int
        let length: Int
    }

    private init(storage: Storage) throws {
        self.storage = storage
        let base = storage.base
        let size = storage.size
        guard size >= 512 else { throw RoadGraphError.invalidFormat("too small") }
        let magic = (0..<8).map { base.load(fromByteOffset: $0, as: UInt8.self) }
        guard magic == Array("VPGRAPH1".utf8) else { throw RoadGraphError.invalidFormat("magic") }
        func u32(_ o: Int) -> Int { Int(base.loadUnaligned(fromByteOffset: o, as: UInt32.self).littleEndian) }
        func i32(_ o: Int) -> Int32 { base.loadUnaligned(fromByteOffset: o, as: Int32.self).littleEndian }
        func u64(_ o: Int) -> Int { Int(base.loadUnaligned(fromByteOffset: o, as: UInt64.self).littleEndian) }

        guard u32(8) == 1 else { throw RoadGraphError.invalidFormat("version \(u32(8))") }
        let headerSize = u32(12)
        let n = u32(16), e = u32(20), g = u32(24), c = u32(28)
        let rows = u32(32), cols = u32(36), items = u32(40)
        let sectionCount = u32(76)
        guard sectionCount >= 19, 80 + sectionCount * 16 <= headerSize else {
            throw RoadGraphError.invalidFormat("section table")
        }
        var sections: [Section] = []
        for i in 0..<sectionCount {
            let s = Section(offset: u64(80 + 16 * i), length: u64(88 + 16 * i))
            guard s.offset >= headerSize, s.offset + s.length <= size else {
                throw RoadGraphError.invalidFormat("section \(i) out of bounds")
            }
            sections.append(s)
        }

        func buffer<T>(_ index: Int, _ type: T.Type, _ count: Int) throws -> UnsafeBufferPointer<T> {
            let s = sections[index]
            guard s.length == count * MemoryLayout<T>.stride else {
                throw RoadGraphError.invalidFormat("section \(index) length")
            }
            guard s.offset % MemoryLayout<T>.alignment == 0 else {
                throw RoadGraphError.invalidFormat("section \(index) alignment")
            }
            let p = base.advanced(by: s.offset).bindMemory(to: T.self, capacity: max(count, 1))
            return UnsafeBufferPointer(start: p, count: count)
        }

        nodeLat = try buffer(0, Int32.self, n)
        nodeLon = try buffer(1, Int32.self, n)
        firstEdge = try buffer(2, UInt32.self, n + 1)
        edgeTarget = try buffer(3, UInt32.self, e)
        edgeGeometry = try buffer(4, UInt32.self, e)
        geomLength = try buffer(5, Float32.self, g)
        geomAttr = try buffer(6, UInt16.self, g)
        geomYear = try buffer(7, UInt8.self, g)
        geomAscent = try buffer(8, UInt16.self, g)
        geomDescent = try buffer(9, UInt16.self, g)
        geomFirstCoord = try buffer(10, UInt32.self, g + 1)
        coordLat = try buffer(11, Int32.self, c)
        coordLon = try buffer(12, Int32.self, c)
        coordEle = try buffer(13, Int16.self, c)
        gridCellStart = try buffer(14, UInt32.self, rows * cols + 1)
        gridItems = try buffer(15, UInt32.self, items)
        geomNodeU = try buffer(17, UInt32.self, g)
        geomNodeV = try buffer(18, UInt32.self, g)

        let metaSection = sections[16]
        let metaData = Data(bytes: base.advanced(by: metaSection.offset), count: metaSection.length)
        do {
            metadata = try JSONDecoder().decode(GraphMetadata.self, from: metaData)
        } catch {
            throw RoadGraphError.invalidFormat("metadata")
        }

        nodeCount = n
        edgeCount = e
        geometryCount = g
        coordinateCount = c
        gridRows = rows
        gridCols = cols
        gridOriginLat = Double(i32(60)) / 1e7
        gridOriginLon = Double(i32(64)) / 1e7
        gridCellLat = Double(i32(68)) / 1e7
        gridCellLon = Double(i32(72)) / 1e7
        bounds = GeoBounds(minLatitude: Double(i32(44)) / 1e7, minLongitude: Double(i32(48)) / 1e7,
                           maxLatitude: Double(i32(52)) / 1e7, maxLongitude: Double(i32(56)) / 1e7)

        guard Int(firstEdge[n]) == e, Int(geomFirstCoord[g]) == c, Int(gridCellStart[rows * cols]) == items else {
            throw RoadGraphError.invalidFormat("index consistency")
        }
    }

    // MARK: - Public accessors

    public func nodeCoordinate(_ node: Int) -> GeoCoordinate {
        GeoCoordinate(latitude: Double(nodeLat[node]) / 1e7, longitude: Double(nodeLon[node]) / 1e7)
    }

    public func attributes(ofGeometry g: Int) -> EdgeAttributes { EdgeAttributes(raw: geomAttr[g]) }

    /// Length of a geometry in metres.
    public func length(ofGeometry g: Int) -> Double { Double(geomLength[g]) }

    /// Survey year of the official condition value, if any.
    public func surveyYear(ofGeometry g: Int) -> Int? {
        let y = geomYear[g]
        return y == 0 ? nil : 2000 + Int(y)
    }

    /// Ascent / descent in metres when travelling the geometry in its stored direction.
    public func climb(ofGeometry g: Int) -> (ascent: Double, descent: Double) {
        (Double(geomAscent[g]) / 10, Double(geomDescent[g]) / 10)
    }

    public func coordinateRange(ofGeometry g: Int) -> Range<Int> {
        Int(geomFirstCoord[g])..<Int(geomFirstCoord[g + 1])
    }

    public func coordinate(at index: Int) -> GeoCoordinate {
        GeoCoordinate(latitude: Double(coordLat[index]) / 1e7, longitude: Double(coordLon[index]) / 1e7)
    }

    /// Elevation in metres, `nil` when the DEM did not cover the point.
    public func elevation(at index: Int) -> Double? {
        let v = coordEle[index]
        return v == Int16.min ? nil : Double(v) / 10
    }

    public func coordinates(ofGeometry g: Int) -> [GeoCoordinate] {
        coordinateRange(ofGeometry: g).map(coordinate(at:))
    }

    public func endpoints(ofGeometry g: Int) -> (start: Int, end: Int) {
        (Int(geomNodeU[g]), Int(geomNodeV[g]))
    }

    /// Whether the geometry may be travelled in its stored direction / against it.
    public func allowedDirections(ofGeometry g: Int) -> (forward: Bool, backward: Bool) {
        let gid = UInt32(g)
        var forward = false
        var backward = false
        let u = Int(geomNodeU[g])
        for k in Int(firstEdge[u])..<Int(firstEdge[u + 1]) where edgeGeometry[k] == gid {
            forward = true
            break
        }
        let v = Int(geomNodeV[g])
        for k in Int(firstEdge[v])..<Int(firstEdge[v + 1]) where edgeGeometry[k] == gid | RoadGraph.reversedBit {
            backward = true
            break
        }
        return (forward, backward)
    }

    /// Geometry ids whose shape passes through grid cells overlapping `bounds`.
    /// May contain geometries slightly outside the box; never misses one inside it.
    public func geometries(intersecting box: GeoBounds) -> [Int] {
        guard gridRows > 0, gridCols > 0 else { return [] }
        let r0 = max(0, Int(floor((box.minLatitude - gridOriginLat) / gridCellLat)))
        let r1 = min(gridRows - 1, Int(floor((box.maxLatitude - gridOriginLat) / gridCellLat)))
        let c0 = max(0, Int(floor((box.minLongitude - gridOriginLon) / gridCellLon)))
        let c1 = min(gridCols - 1, Int(floor((box.maxLongitude - gridOriginLon) / gridCellLon)))
        guard r0 <= r1, c0 <= c1 else { return [] }
        var seen = Set<Int>()
        var result: [Int] = []
        for r in r0...r1 {
            for c in c0...c1 {
                let cell = r * gridCols + c
                for k in Int(gridCellStart[cell])..<Int(gridCellStart[cell + 1]) {
                    let g = Int(gridItems[k])
                    if seen.insert(g).inserted { result.append(g) }
                }
            }
        }
        return result
    }

    /// Iterates over every geometry in id order.
    public func forEachGeometry(_ body: (Int, EdgeAttributes) -> Void) {
        for g in 0..<geometryCount { body(g, EdgeAttributes(raw: geomAttr[g])) }
    }
}
