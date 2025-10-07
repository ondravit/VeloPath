//
//  ContentView.swift
//  RoadNavigationDemo
//
//  Created by Ondřej Vít on 07.10.2025.
//

import SwiftUI

struct ContentView: View {
    let roads = GeoJSONService.loadRoads(from: "roads")
    
    var body: some View {
        MapView(roads: roads)
    }
}

#Preview {
    ContentView()
}

