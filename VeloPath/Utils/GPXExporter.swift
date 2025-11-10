//
//  GPXExporter.swift
//  VeloPath
//
//  Created by Ondřej Vít on 10.11.2025.
//

import CoreGPX
import CoreLocation

class GPXExporter {
    static func exportRoute(_ coords: [CLLocationCoordinate2D]) -> URL? {
        let gpx = GPXRoot(creator: "VeloPath")
        let track = GPXTrack()
        let segment = GPXTrackSegment()

        coords.forEach {
            segment.add(trackpoint: GPXTrackPoint(latitude: $0.latitude, longitude: $0.longitude))
        }

        track.add(trackSegment: segment)
        gpx.add(track: track)

        let output = gpx.gpx()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("VeloPathRoute.gpx")
        do {
            try output.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            print("❌ GPX export failed:", error)
            return nil
        }
    }
}
