//
//  MapContainerView.swift
//  VeloPath
//
//  Created by Ondřej Vít on 07.10.2025.
//

import SwiftUI
import MapKit
import CoreLocation

struct MapContainerView: View {
    let roads: [RoadSegment]
    let roadDisplayMode: RoadDisplayMode
    var userLocation: CLLocationCoordinate2D?
    @State private var routeCoords: [CLLocationCoordinate2D] = []
    @State private var startCoord: CLLocationCoordinate2D?
    @State private var endCoord: CLLocationCoordinate2D?
    
    private var knownRoads: [RoadSegment] {
        roads.filter { $0.condition != .unknown }
    }
    private var unknownRoads: [RoadSegment] {
        roads.filter { $0.condition == .unknown }
    }
    
    private var knownToShow: [RoadSegment] {
            switch roadDisplayMode {
            case .none: return []
            case .knownOnly: return knownRoads
            case .all: return knownRoads
            }
        }
        private var unknownToShow: [RoadSegment] {
            switch roadDisplayMode {
            case .none: return []
            case .knownOnly: return []              // ← tady je ten rozdíl
            case .all: return unknownRoads
            }
        }
    
   
    var body: some View {
        ZStack {
            InteractiveMapView(
                routeCoords: $routeCoords,
                startCoord: $startCoord,
                endCoord: $endCoord,
                allRoads: roads,
                knownRoads: knownToShow,
                unknownRoads: unknownToShow,
                userLocation: userLocation
            )
            .edgesIgnoringSafeArea(.all)
        }
    }
}
