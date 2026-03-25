import SwiftUI

struct SidePanel: View {
    @Binding var roadDisplayMode: RoadDisplayMode

    var body: some View {
        VStack {
            HStack {
                Spacer()
                VStack(spacing: 12) {
                    // Layers button — cycles None → KnownOnly → All
                    Button {
                        cycleDisplayMode()
                    } label: {
                        Image(systemName: iconName(for: roadDisplayMode))
                            .font(.system(size: 18, weight: .medium))
                            // Fixed frame prevents layout jitter when the icon switches
                            // between symbols with different intrinsic widths.
                            .frame(width: 24, height: 24)
                            .padding(13)
                            .background(.ultraThinMaterial, in: Circle())
                    }

                    // Location button — recenters map to user position
                    Button {
                        NotificationCenter.default.post(name: .recenterMap, object: nil)
                    } label: {
                        Image(systemName: "location.fill")
                            .font(.system(size: 18, weight: .medium))
                            .frame(width: 24, height: 24)
                            .padding(13)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .padding(.trailing, 4)
                // Use safe-area-relative top padding instead of a hardcoded magic number.
                .padding(.top, 12)
            }
            Spacer()
        }
    }

    // MARK: - Helpers

    private func cycleDisplayMode() {
        let next = (roadDisplayMode.rawValue + 1) % RoadDisplayMode.allCases.count
        roadDisplayMode = RoadDisplayMode(rawValue: next)!
    }

    private func iconName(for mode: RoadDisplayMode) -> String {
        switch mode {
        case .none:      return "map"           // no road overlays (iOS 13+)
        case .knownOnly: return "road.lanes"    // quality roads only (iOS 17+)
        case .all:       return "map.fill"      // all roads including unknown (iOS 13+)
        }
    }
}

// MARK: - Road display mode

enum RoadDisplayMode: Int, CaseIterable {
    case none       // nothing drawn
    case knownOnly  // known condition roads only
    case all        // known + unknown
}
