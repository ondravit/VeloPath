//
//  GraphEdge.swift
//  RoadNavigationDemo
//
//  Created by Ondřej Vít on 07.10.2025.
//

import Foundation
import CoreLocation

struct GraphEdge {
    let from: GraphNode
    let to: GraphNode
    let weight: Double // Lower = better (e.g., distance adjusted by road condition)
    let condition: RoadSegment.RoadCondition
}
