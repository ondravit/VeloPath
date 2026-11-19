import MapKit
import Observation
import SwiftUI
import VeloCore

/// Autocomplete for places and addresses inside the covered region.
@MainActor
@Observable
final class PlaceSearchModel: NSObject, MKLocalSearchCompleterDelegate {
    var query = "" {
        didSet { completer.queryFragment = query }
    }
    private(set) var results: [MKLocalSearchCompletion] = []
    private(set) var isSearching = false
    @ObservationIgnored private let completer: MKLocalSearchCompleter

    init(region: GeoBounds?) {
        let c = MKLocalSearchCompleter()
        completer = c
        super.init()
        c.delegate = self
        c.resultTypes = [.address, .pointOfInterest]
        if let region {
            let center = region.center
            c.region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude),
                span: MKCoordinateSpan(latitudeDelta: (region.maxLatitude - region.minLatitude) * 1.2,
                                       longitudeDelta: (region.maxLongitude - region.minLongitude) * 1.2))
        }
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated {
            self.results = completer.results
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            self.results = []
        }
    }

    /// Resolves a completion to a coordinate.
    func resolve(_ completion: MKLocalSearchCompletion) async -> (GeoCoordinate, String)? {
        isSearching = true
        defer { isSearching = false }
        let request = MKLocalSearch.Request(completion: completion)
        guard let response = try? await MKLocalSearch(request: request).start(),
              let item = response.mapItems.first else { return nil }
        let c = item.placemark.coordinate
        return (GeoCoordinate(latitude: c.latitude, longitude: c.longitude), completion.title)
    }
}

struct PlaceSearchView: View {
    @Environment(PlannerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let target: SearchTarget
    @State private var model: PlaceSearchModel?

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    SearchResultsList(model: model, onPick: pick, onCurrentLocation: useCurrentLocation)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zrušit") { dismiss() }
                }
            }
        }
        .onAppear {
            if model == nil { model = PlaceSearchModel(region: store.coverage) }
        }
    }

    private var title: String {
        switch target {
        case .append: return store.waypoints.isEmpty ? "Odkud vyrazíte?" : "Přidat cíl"
        case .replace: return "Nahradit bod"
        }
    }

    private func pick(_ coordinate: GeoCoordinate, _ name: String) {
        switch target {
        case .append:
            store.addWaypoint(at: coordinate, name: name, frame: true)
        case .replace(let id):
            store.replaceWaypoint(id, with: coordinate, name: name)
        }
        dismiss()
    }

    private func useCurrentLocation() {
        let target = self.target
        store.location.requestCurrentLocation { coordinate in
            guard let coordinate else {
                store.showToast("Polohu se nepodařilo zjistit.", "location.slash")
                return
            }
            switch target {
            case .append:
                store.addWaypoint(at: coordinate, index: store.waypoints.isEmpty ? 0 : nil, name: "Moje poloha", frame: true)
            case .replace(let id):
                store.replaceWaypoint(id, with: coordinate, name: "Moje poloha")
            }
        }
        dismiss()
    }
}

private struct SearchResultsList: View {
    @Bindable var model: PlaceSearchModel
    let onPick: (GeoCoordinate, String) -> Void
    let onCurrentLocation: () -> Void

    var body: some View {
        List {
            if model.query.isEmpty {
                Button(action: onCurrentLocation) {
                    Label("Moje poloha", systemImage: "location.fill")
                }
            }
            ForEach(model.results, id: \.self) { result in
                Button {
                    Task {
                        if let found = await model.resolve(result) {
                            onPick(found.0, found.1)
                        }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.title)
                            .foregroundStyle(.primary)
                        if !result.subtitle.isEmpty {
                            Text(result.subtitle)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if model.isSearching { ProgressView() }
        }
        .searchable(text: $model.query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Obec, ulice nebo místo")
    }
}
