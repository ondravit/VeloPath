//
//  RoadGraph.swift
//  RoadNavigationDemo
//
//  Created by Ondřej Vít on 07.10.2025.
//

import Foundation
import CoreLocation

class RoadGraph {
    var nodes: Set<GraphNode> = []
    var edges: [GraphNode: [GraphEdge]] = [:]
    
    init(roadSegments: [RoadSegment]) {
        buildGraph(from: roadSegments)
    }
    
    private func buildGraph(from roadSegments: [RoadSegment]) {
        for segment in roadSegments {
            let coords = segment.coordinates
            guard coords.count >= 2 else { continue }
            
            for i in 0..<(coords.count - 1) {
                let startNode = GraphNode(coordinate: coords[i])
                let endNode = GraphNode(coordinate: coords[i + 1])
                
                nodes.insert(startNode)
                nodes.insert(endNode)
                
                let distance = distanceBetween(startNode.coordinate, endNode.coordinate)
                let weight = distance * conditionMultiplier(segment.condition)
                
                let edge = GraphEdge(from: startNode, to: endNode, weight: weight, condition: segment.condition)
                
                edges[startNode, default: []].append(edge)
                // For undirected graph, also add the reverse edge
                let reverseEdge = GraphEdge(from: endNode, to: startNode, weight: weight, condition: segment.condition)
                edges[endNode, default: []].append(reverseEdge)
            }
        }
    }
    
    private func distanceBetween(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let locA = CLLocation(latitude: a.latitude, longitude: a.longitude)
        let locB = CLLocation(latitude: b.latitude, longitude: b.longitude)
        return locA.distance(from: locB) // meters
    }
    
    private func conditionMultiplier(_ condition: RoadSegment.RoadCondition) -> Double {
        switch condition {
        case .excellent: return 1.0
        case .good: return 1.3
        case .satisfactory: return 1.5
        case .unsatisfactory: return 2.0
        case .emergency: return 2.5
        case .superemergency: return 3.0
        case .unknown: return 1.75
        }
    }
}
