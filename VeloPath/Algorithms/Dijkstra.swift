//
//  Dijkstra.swift
//  VeloPath
//
//  Created by Ondřej Vít on 07.10.2025.
//

import Foundation
import CoreLocation

class Dijkstra {
    
    static func shortestPath(from start: GraphNode, to end: GraphNode, graph: RoadGraph) -> [GraphNode] {
        var distances: [GraphNode: Double] = [:]
        var previous: [GraphNode: GraphNode] = [:]
        var unvisited = Set(graph.nodes)
        
        // Initialize distances
        for node in graph.nodes {
            distances[node] = Double.infinity
        }
        distances[start] = 0
        
        while !unvisited.isEmpty {
            // Get the node with the smallest distance
            let current = unvisited.min { (distances[$0] ?? Double.infinity) < (distances[$1] ?? Double.infinity) }!
            
            if current == end {
                break
            }
            
            unvisited.remove(current)
            
            guard let neighbors = graph.edges[current] else { continue }
            
            for edge in neighbors {
                let neighbor = edge.to
                if !unvisited.contains(neighbor) { continue }
                
                let tentative = (distances[current] ?? Double.infinity) + edge.cost
                if tentative < (distances[neighbor] ?? Double.infinity) {
                    distances[neighbor] = tentative
                    previous[neighbor] = current
                }
            }
        }
        
        // Reconstruct path
        var path: [GraphNode] = []
        var current: GraphNode? = end
        
        while let node = current {
            path.insert(node, at: 0)
            current = previous[node]
        }
        
        if path.first != start {
            return [] // no path found
        }
        
        return path
    }
}
