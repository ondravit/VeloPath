import Foundation

// Mirrors pipeline/velopath_pipeline/model.py – the numeric values are part of the
// binary graph format and must never be renumbered.

public enum RoadClass: UInt8, CaseIterable, Sendable, Codable {
    case cycleway = 0
    case sharedPath = 1
    case track = 2
    case livingStreet = 3
    case service = 4
    case residential = 5
    case unclassified = 6
    case tertiary = 7
    case secondary = 8
    case primary = 9
    case trunk = 10
}

public enum Surface: UInt8, CaseIterable, Sendable, Codable {
    case asphalt = 0
    case concretePlates = 1
    case pavingStones = 2
    case sett = 3
    case cobblestone = 4
    case unknown = 5
    case fineGravel = 6
    case otherPaved = 7
}

/// Pavement condition according to the Czech TP 87 classification.
public enum RoadCondition: UInt8, CaseIterable, Sendable, Codable, Comparable {
    case excellent = 0
    case good = 1
    case satisfactory = 2
    case unsatisfactory = 3
    case emergency = 4
    case superEmergency = 5
    case unknown = 7

    public static func < (lhs: RoadCondition, rhs: RoadCondition) -> Bool { lhs.rawValue < rhs.rawValue }

    /// All conditions with a known value, best first.
    public static let known: [RoadCondition] = [.excellent, .good, .satisfactory, .unsatisfactory, .emergency, .superEmergency]
}

public enum ConditionSource: UInt8, Sendable, Codable {
    case none = 0
    case official = 1
    case osmSmoothness = 2
    case community = 3
}

/// Decoded 16-bit attribute word of a road geometry.
public struct EdgeAttributes: Hashable, Sendable {
    public let raw: UInt16

    public init(raw: UInt16) { self.raw = raw }

    public init(roadClass: RoadClass, surface: Surface, condition: RoadCondition,
                source: ConditionSource, dismount: Bool = false) {
        var r = UInt16(roadClass.rawValue & 0xF)
        r |= UInt16(surface.rawValue & 0x7) << 4
        r |= UInt16(condition.rawValue & 0x7) << 7
        r |= UInt16(source.rawValue & 0x3) << 10
        if dismount { r |= 1 << 12 }
        raw = r
    }

    /// Index into a cost table (class, surface, condition, source, dismount).
    @inlinable public var costIndex: Int { Int(raw & 0x1FFF) }

    public var roadClass: RoadClass { RoadClass(rawValue: UInt8(raw & 0xF)) ?? .unclassified }
    public var surface: Surface { Surface(rawValue: UInt8((raw >> 4) & 0x7)) ?? .unknown }
    public var condition: RoadCondition { RoadCondition(rawValue: UInt8((raw >> 7) & 0x7)) ?? .unknown }
    public var conditionSource: ConditionSource { ConditionSource(rawValue: UInt8((raw >> 10) & 0x3)) ?? .none }
    public var requiresDismount: Bool { raw & (1 << 12) != 0 }
}
