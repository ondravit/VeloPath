//
//  AStar.swift
//  RoadNavigationDemo
//
//  Created by Ondřej Vít on 08.10.2025.
//

import Foundation
import CoreLocation

/// A* search for shortest path on RoadGraph
enum AStar {
    static func findPath(
        in graph: RoadGraph,
        from start: GraphNode,
        to goal: GraphNode
    ) -> [GraphNode] {

        // Min-heap by fScore
        var open = PriorityQueue<OpenItem>(sort: { $0.f < $1.f })
        var cameFrom: [GraphNode: GraphNode] = [:]

        var gScore: [GraphNode: Double] = [start: 0]
        var fScore: [GraphNode: Double] = [start: h(start, goal)]

        open.push(OpenItem(node: start, f: fScore[start]!))

        var inOpen: Set<GraphNode> = [start]

        while let current = open.pop()?.node {
            inOpen.remove(current)

            if current == goal {
                return reconstructPath(cameFrom: cameFrom, current: current)
            }

            for edge in graph.neighbors(of: current) {
                let tentative = (gScore[current] ?? .infinity) + edge.cost
                if tentative < (gScore[edge.to] ?? .infinity) {
                    cameFrom[edge.to] = current
                    gScore[edge.to] = tentative
                    let f = tentative + h(edge.to, goal)
                    fScore[edge.to] = f
                    if !inOpen.contains(edge.to) {
                        open.push(OpenItem(node: edge.to, f: f))
                        inOpen.insert(edge.to)
                    }
                }
            }
        }

        return [] // no path
    }

    private static func h(_ a: GraphNode, _ b: GraphNode) -> Double {
        // straight-line distance as an admissible heuristic (meters)
        a.coordinate.distance(to: b.coordinate)
    }

    private static func reconstructPath(cameFrom: [GraphNode: GraphNode], current: GraphNode) -> [GraphNode] {
        var path: [GraphNode] = [current]
        var cur = current
        while let prev = cameFrom[cur] {
            path.append(prev)
            cur = prev
        }
        return path.reversed()
    }

    private struct OpenItem {
        let node: GraphNode
        let f: Double
    }
}

/// Simple binary-heap priority queue
struct PriorityQueue<T> {
    private var heap: [T] = []
    private let areSorted: (T, T) -> Bool

    init(sort: @escaping (T, T) -> Bool) {
        self.areSorted = sort
    }

    var isEmpty: Bool { heap.isEmpty }

    mutating func push(_ element: T) {
        heap.append(element)
        siftUp(heap.count - 1)
    }

    mutating func pop() -> T? {
        guard !heap.isEmpty else { return nil }
        heap.swapAt(0, heap.count - 1)
        let item = heap.removeLast()
        siftDown(0)
        return item
    }

    private mutating func siftUp(_ index: Int) {
        var child = index
        while child > 0 {
            let parent = (child - 1) / 2
            if areSorted(heap[child], heap[parent]) {
                heap.swapAt(child, parent)
                child = parent
            } else { break }
        }
    }

    private mutating func siftDown(_ index: Int) {
        var parent = index
        while true {
            let left = 2*parent + 1
            let right = left + 1
            var candidate = parent
            if left < heap.count && areSorted(heap[left], heap[candidate]) { candidate = left }
            if right < heap.count && areSorted(heap[right], heap[candidate]) { candidate = right }
            if candidate == parent { return }
            heap.swapAt(parent, candidate)
            parent = candidate
        }
    }
}
