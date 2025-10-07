//
//  GeoJSONService.swift
//  RoadNavigationDemo
//
//  Created by Ondřej Vít on 07.10.2025.
//

import Foundation
import MapKit

class GeoJSONService {
    static func loadRoads(from fileName: String) -> [RoadSegment] {
        guard let url = Bundle.main.url(forResource: "Stav_povrchu_silnic", withExtension: "geojson") else {
            print("GeoJSON not found: \(fileName).geojson")
            return []
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = MKGeoJSONDecoder()
            let features = try decoder.decode(data)
            
            var roads: [RoadSegment] = []
            
            for feature in features {
                if let feature = feature as? MKGeoJSONFeature {
                    let condition = feature.propertiesAsCondition()
                    
                    for geometry in feature.geometry {
                        if let polyline = geometry as? MKPolyline {
                            let coords = polyline.coordinates
                            let road = RoadSegment(coordinates: coords, condition: condition)
                            roads.append(road)
                        }
                    }
                }
            }
            
            return roads
            
        } catch {
            print("Failed to parse GeoJSON: \(error)")
            return []
        }
    }
}

extension MKGeoJSONFeature {
    func propertiesAsCondition() -> RoadSegment.RoadCondition {
        guard let propData = self.properties,
              let dict = try? JSONSerialization.jsonObject(with: propData, options: .allowFragments) as? [String: Any],
              let stav = dict["stav_sil"] as? String else {
            return .unknown
        }
        
        switch stav {
        case "výborný": return .excellent
        case "dobrý": return .good
        case "nevyhovující": return .poor
        case "havarijní": return .bad
        case "SUPERhavarijní": return .superbad
        default: return .unknown
        }
    }
}

extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: self.pointCount)
        self.getCoordinates(&coords, range: NSRange(location: 0, length: self.pointCount))
        return coords
    }
}
