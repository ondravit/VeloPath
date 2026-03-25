import SwiftUI
import MapKit
import CoreLocation

struct MapContainerView: View {
    @Binding var segments: [DBSegment]
    let graph: ImmutableGraph?
    let roadDisplayMode: RoadDisplayMode
    var userLocation: CLLocationCoordinate2D?
    @Binding var qualityBalance: Double
    @Binding var routePlan: RoutePlan
    @Binding var isPlacingWaypoint: Bool
    @Binding var insertionIndex: Int?
    @Binding var plannerOffset: CGFloat
    @Binding var routeDistance: Double
    @State private var routeCoords: [CLLocationCoordinate2D] = []
    @State private var startCoord: CLLocationCoordinate2D?
    @State private var endCoord: CLLocationCoordinate2D?

    // MARK: - Filtering

    private var knownSegments: [DBSegment]   { segments.filter { $0.condition != 6 } }
    private var unknownSegments: [DBSegment] { segments.filter { $0.condition == 6 } }

    private var knownToShow: [DBSegment] {
        switch roadDisplayMode {
        case .none:      return []
        case .knownOnly: return knownSegments
        case .all:       return knownSegments
        }
    }
    private var unknownToShow: [DBSegment] {
        switch roadDisplayMode {
        case .none, .knownOnly: return []
        case .all:              return unknownSegments
        }
    }

    // MARK: - Body

    var body: some View {
        InteractiveMapView(
            segments:         $segments,
            routeCoords:      $routeCoords,
            routePlan:        $routePlan,
            startCoord:       $startCoord,
            endCoord:         $endCoord,
            isPlacingWaypoint: $isPlacingWaypoint,
            insertionIndex:   $insertionIndex,
            graph:            graph,
            knownSegments:    knownToShow,
            unknownSegments:  unknownToShow,
            userLocation:     userLocation,
            qualityBalance:   $qualityBalance,
            routeDistance:    $routeDistance
        )
        .edgesIgnoringSafeArea(.all)
    }
}
