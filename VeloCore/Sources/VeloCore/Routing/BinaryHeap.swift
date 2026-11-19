/// Minimal binary min-heap of (priority, node) pairs used by the A* search.
/// Decrease-key is handled lazily: stale entries are skipped when popped.
struct BinaryHeap {
    private var keys: [Double] = []
    private var values: [UInt32] = []

    init(capacity: Int = 1024) {
        keys.reserveCapacity(capacity)
        values.reserveCapacity(capacity)
    }

    var isEmpty: Bool { keys.isEmpty }
    var count: Int { keys.count }
    var minKey: Double? { keys.first }

    mutating func removeAll() {
        keys.removeAll(keepingCapacity: true)
        values.removeAll(keepingCapacity: true)
    }

    mutating func push(_ key: Double, _ value: UInt32) {
        keys.append(key)
        values.append(value)
        var i = keys.count - 1
        while i > 0 {
            let parent = (i - 1) >> 1
            if keys[parent] <= key { break }
            keys[i] = keys[parent]
            values[i] = values[parent]
            i = parent
        }
        keys[i] = key
        values[i] = value
    }

    mutating func pop() -> (key: Double, value: UInt32)? {
        guard let topKey = keys.first else { return nil }
        let topValue = values[0]
        let lastKey = keys.removeLast()
        let lastValue = values.removeLast()
        let n = keys.count
        if n > 0 {
            var i = 0
            while true {
                let l = 2 * i + 1
                if l >= n { break }
                let r = l + 1
                let c = (r < n && keys[r] < keys[l]) ? r : l
                if keys[c] >= lastKey { break }
                keys[i] = keys[c]
                values[i] = values[c]
                i = c
            }
            keys[i] = lastKey
            values[i] = lastValue
        }
        return (topKey, topValue)
    }
}
