import simd

struct TagAnchor {
    let id: Int
    private(set) var worldPosition: SIMD3<Float>          // center, for minimap
    private(set) var worldCorners: [SIMD3<Float>]          // 4 corners, for exact overlay
    private(set) var observationCount: Int

    init(id: Int, position: SIMD3<Float>, corners: [SIMD3<Float>]) {
        self.id = id
        self.worldPosition = position
        self.worldCorners = corners
        self.observationCount = 1
    }

    mutating func merge(position newPosition: SIMD3<Float>, corners newCorners: [SIMD3<Float>]) {
        observationCount += 1
        let alpha = max(0.3, 1.0 / Float(observationCount))
        worldPosition = mix(worldPosition, newPosition, t: alpha)
        guard newCorners.count == worldCorners.count else { return }
        worldCorners = zip(worldCorners, newCorners).map { mix($0, $1, t: alpha) }
    }
}

@MainActor
final class TagPositionStore {
    private(set) var anchors: [Int: TagAnchor] = [:]

    func update(id: Int, worldPosition: SIMD3<Float>, worldCorners: [SIMD3<Float>]) {
        if anchors[id] != nil {
            anchors[id]!.merge(position: worldPosition, corners: worldCorners)
        } else {
            anchors[id] = TagAnchor(id: id, position: worldPosition, corners: worldCorners)
        }
    }

    func position(for id: Int) -> SIMD3<Float>? {
        anchors[id]?.worldPosition
    }

    func reset() {
        anchors.removeAll()
    }
}
