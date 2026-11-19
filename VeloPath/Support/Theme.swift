import SwiftUI
import UIKit
import VeloCore

extension RoadCondition {
    var title: String {
        switch self {
        case .excellent: return "Výborný"
        case .good: return "Dobrý"
        case .satisfactory: return "Vyhovující"
        case .unsatisfactory: return "Nevyhovující"
        case .emergency: return "Havarijní"
        case .superEmergency: return "Velmi havarijní"
        case .unknown: return "Neznámý"
        }
    }

    var uiColor: UIColor {
        switch self {
        case .excellent: return UIColor(red: 0.10, green: 0.62, blue: 0.29, alpha: 1)
        case .good: return UIColor(red: 0.49, green: 0.76, blue: 0.20, alpha: 1)
        case .satisfactory: return UIColor(red: 0.96, green: 0.76, blue: 0.10, alpha: 1)
        case .unsatisfactory: return UIColor(red: 0.96, green: 0.52, blue: 0.10, alpha: 1)
        case .emergency: return UIColor(red: 0.89, green: 0.20, blue: 0.18, alpha: 1)
        case .superEmergency: return UIColor(red: 0.56, green: 0.14, blue: 0.62, alpha: 1)
        case .unknown: return UIColor.systemGray3
        }
    }

    var color: Color { Color(uiColor: uiColor) }
}

extension Surface {
    var title: String {
        switch self {
        case .asphalt: return "Asfalt / beton"
        case .concretePlates: return "Betonové panely"
        case .pavingStones: return "Zámková dlažba"
        case .sett: return "Kostky"
        case .cobblestone: return "Hrubé kostky"
        case .unknown: return "Zpevněný (neověřeno)"
        case .fineGravel: return "Mlat / jemný štěrk"
        case .otherPaved: return "Dřevo / kov (mosty)"
        }
    }

    /// Surfaces worth pointing out to a road cyclist.
    var isNoteworthy: Bool {
        switch self {
        case .sett, .cobblestone, .fineGravel, .concretePlates, .pavingStones: return true
        default: return false
        }
    }
}

extension RoadClass {
    var title: String {
        switch self {
        case .cycleway: return "Cyklostezky"
        case .sharedPath: return "Stezky pro chodce a cyklisty"
        case .track: return "Zpevněné polní a lesní cesty"
        case .livingStreet: return "Obytné a pěší zóny"
        case .service: return "Účelové komunikace"
        case .residential: return "Místní ulice"
        case .unclassified: return "Místní silnice"
        case .tertiary: return "Silnice III. třídy"
        case .secondary: return "Silnice II. třídy"
        case .primary: return "Silnice I. třídy"
        case .trunk: return "Rychlostní silnice"
        }
    }
}

extension SurfacePriority {
    var title: String {
        switch self {
        case .direct: return "Přímá"
        case .balanced: return "Vyvážená"
        case .best: return "Nejlepší povrch"
        }
    }

    var subtitle: String {
        switch self {
        case .direct: return "Co nejkratší trasa, jen se vyhýbá kostkám a mlatu."
        case .balanced: return "Malé zajížďky za výrazně lepší silnice."
        case .best: return "Delší zajížďky, aby trasa vedla po nejlepším povrchu."
        }
    }
}

enum Format {
    static func distance(_ meters: Double) -> String {
        if meters < 1000 {
            return "\(Int((meters / 10).rounded()) * 10) m"
        }
        let km = meters / 1000
        let digits = km < 100 ? 1 : 0
        return km.formatted(.number.precision(.fractionLength(digits)).locale(Locale(identifier: "cs_CZ"))) + " km"
    }

    static func elevation(_ meters: Double) -> String {
        "\(Int(meters.rounded())) m"
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded())) %"
    }
}
