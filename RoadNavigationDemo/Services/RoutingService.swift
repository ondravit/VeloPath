//
//  RoutingService.swift
//  RoadNavigationDemo
//
//  Created by Ondřej Vít on 07.10.2025.
//

import Foundation
import CoreLocation

class RoutingService {
    
    private let graph: RoadGraph
    
    init(roadSegments: [RoadSegment]) {
        self.graph = RoadGraph(roadSegments: roadSegments)
    }
    
    /// Returns the shortest/best path between two coordinates
    func route(from startCoord: CLLocationCoordinate2D, to endCoord: CLLocationCoordinate2D) -> [CLLocationCoordinate2D] {
        
        // Find the nearest nodes in the graph to the requested coordinates
        guard let startNode = nearestNode(to: startCoord),
              let endNode = nearestNode(to: endCoord) else {
            return []
        }
        
        // Run Dijkstra
        let pathNodes = Dijkstra.shortestPath(from: startNode, to: endNode, graph: graph)
        
        // Convert nodes to coordinates
        return pathNodes.map { $0.coordinate }
    }
    
    /// Finds the nearest graph node to a coordinate
    private func nearestNode(to coord: CLLocationCoordinate2D) -> GraphNode? {
        var nearest: GraphNode?
        var minDistance = Double.infinity
        
        for node in graph.nodes {
            let locNode = CLLocation(latitude: node.coordinate.latitude, longitude: node.coordinate.longitude)
            let locTarget = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            let distance = locNode.distance(from: locTarget)
            
            if distance < minDistance {
                minDistance = distance
                nearest = node
            }
        }
        
        return nearest
    }
}
