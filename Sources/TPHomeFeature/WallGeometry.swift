import Foundation

/// A room rectangle in blueprint coordinate space, decoupled from `TPCore.MapConfig.Room`
/// so this file's math stays pure and testable without any wire-model dependency.
struct RoomRect: Equatable, Sendable {
    let x: Double
    let y: Double
    let w: Double
    let h: Double
}

struct WallSegment: Equatable, Sendable {
    let x1: Double
    let y1: Double
    let x2: Double
    let y2: Double
}

struct WallPoint: Equatable, Sendable {
    let x: Double
    let y: Double
}

/// Direct port of `Map.vue`'s wall-tracing algorithm: classify every candidate room-edge
/// segment as exterior (exactly one side inside a room) or a shared interior wall (both
/// sides inside a room), then trace the exterior segments into one closed polygon.
enum WallGeometry {
    /// Classifies every horizontal/vertical boundary segment between consecutive room-edge
    /// breakpoints. Each edge is tested only against the sub-intervals of the room that owns
    /// it, which avoids phantom walls cutting through unrelated rooms.
    static func computeWallSegments(rooms: [RoomRect]) -> (exterior: [WallSegment], interior: [WallSegment]) {
        guard !rooms.isEmpty else { return ([], []) }

        let xs = Set(rooms.flatMap { [$0.x, $0.x + $0.w] }).sorted()
        let ys = Set(rooms.flatMap { [$0.y, $0.y + $0.h] }).sorted()

        func inRoom(_ x: Double, _ y: Double) -> Bool {
            rooms.contains { x >= $0.x && x <= $0.x + $0.w && y >= $0.y && y <= $0.y + $0.h }
        }

        var exteriorSet: Set<WallSegment> = []
        var interiorSet: Set<WallSegment> = []
        var exterior: [WallSegment] = []
        var interior: [WallSegment] = []

        for y in ys {
            for room in rooms where room.y == y || room.y + room.h == y {
                let rxs = xs.filter { $0 >= room.x && $0 <= room.x + room.w }
                guard rxs.count >= 2 else { continue }
                for i in 0..<(rxs.count - 1) {
                    let xm = (rxs[i] + rxs[i + 1]) / 2
                    let above = inRoom(xm, y - 0.5)
                    let below = inRoom(xm, y + 0.5)
                    let segment = WallSegment(x1: rxs[i], y1: y, x2: rxs[i + 1], y2: y)
                    if above != below, !exteriorSet.contains(segment) {
                        exteriorSet.insert(segment)
                        exterior.append(segment)
                    } else if above, below, !interiorSet.contains(segment) {
                        interiorSet.insert(segment)
                        interior.append(segment)
                    }
                }
            }
        }

        for x in xs {
            for room in rooms where room.x == x || room.x + room.w == x {
                let rys = ys.filter { $0 >= room.y && $0 <= room.y + room.h }
                guard rys.count >= 2 else { continue }
                for j in 0..<(rys.count - 1) {
                    let ym = (rys[j] + rys[j + 1]) / 2
                    let left = inRoom(x - 0.5, ym)
                    let right = inRoom(x + 0.5, ym)
                    let segment = WallSegment(x1: x, y1: rys[j], x2: x, y2: rys[j + 1])
                    if left != right, !exteriorSet.contains(segment) {
                        exteriorSet.insert(segment)
                        exterior.append(segment)
                    } else if left, right, !interiorSet.contains(segment) {
                        interiorSet.insert(segment)
                        interior.append(segment)
                    }
                }
            }
        }

        return (exterior, interior)
    }

    /// Walks the exterior segments' adjacency graph into one closed polygon, starting at the
    /// topmost-then-leftmost point, and drops collinear vertices. Returns `[]` if the segments
    /// don't form a single closed loop of at least 3 distinct corners.
    static func traceExteriorPolygon(_ segments: [WallSegment]) -> [WallPoint] {
        guard !segments.isEmpty else { return [] }

        struct Node {
            let point: WallPoint
            var neighbors: [WallPoint] = []
        }

        var adjacency: [WallPoint: Node] = [:]
        for segment in segments {
            let p1 = WallPoint(x: segment.x1, y: segment.y1)
            let p2 = WallPoint(x: segment.x2, y: segment.y2)
            adjacency[p1, default: Node(point: p1)].neighbors.append(p2)
            adjacency[p2, default: Node(point: p2)].neighbors.append(p1)
        }

        guard let start = adjacency.keys.min(by: { a, b in (a.y, a.x) < (b.y, b.x) }) else { return [] }

        var raw: [WallPoint] = []
        var current = start
        var previous: WallPoint?
        repeat {
            guard let node = adjacency[current] else { break }
            raw.append(node.point)
            guard let next = node.neighbors.first(where: { $0 != previous }) ?? node.neighbors.first else { break }
            previous = current
            current = next
        } while current != start && raw.count <= segments.count

        let n = raw.count
        guard n >= 3 else { return [] }

        let poly = raw.indices.filter { i in
            let p = raw[(i - 1 + n) % n]
            let c = raw[i]
            let next = raw[(i + 1) % n]
            let cross = (c.x - p.x) * (next.y - p.y) - (c.y - p.y) * (next.x - p.x)
            return cross != 0
        }.map { raw[$0] }

        return poly.count >= 3 ? poly : []
    }
}

extension WallPoint: Hashable {}
extension WallSegment: Hashable {}
