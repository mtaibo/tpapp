import SwiftUI
import TPCore

struct WallsLayer: View {
    let rooms: [MapConfig.Room]
    let labels: [MapConfig.Label]
    let doors: [MapConfig.Door]

    var body: some View {
        let roomRects = rooms.map { RoomRect(x: $0.x, y: $0.y, w: $0.w, h: $0.h) }
        let (exterior, interior) = WallGeometry.computeWallSegments(rooms: roomRects)
        let outline = WallGeometry.traceExteriorPolygon(exterior)

        Canvas { context, _ in
            context.drawLayer { layer in
                var walls = Path()
                for segment in interior {
                    walls.move(to: CGPoint(x: segment.x1, y: segment.y1))
                    walls.addLine(to: CGPoint(x: segment.x2, y: segment.y2))
                }
                walls.addPath(Self.roundedPath(for: outline))
                layer.stroke(walls, with: .color(.white.opacity(0.80)), style: StrokeStyle(lineWidth: 2, lineCap: .round))

                var doorCuts = Path()
                for door in doors {
                    doorCuts.move(to: CGPoint(x: door.x1, y: door.y1))
                    doorCuts.addLine(to: CGPoint(x: door.x2, y: door.y2))
                }
                layer.blendMode = .destinationOut
                layer.stroke(doorCuts, with: .color(.black), style: StrokeStyle(lineWidth: 8, lineCap: .butt))
            }
        }
        .overlay {
            ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                Text(label.text.uppercased())
                    .font(.system(size: 11, weight: .medium))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.68))
                    // SVG `y` is the text baseline, not the vertical center SwiftUI positions on.
                    .position(x: label.x, y: label.y - 4)
            }
        }
    }

    /// Builds the closed outline path: convex corners get a rounded quadratic-Bézier corner,
    /// concave corners stay sharp to avoid visual gaps at inward notches.
    private static func roundedPath(for polygon: [WallPoint], radius: Double = 12) -> Path {
        var path = Path()
        guard polygon.count >= 3 else { return path }
        let m = polygon.count

        for i in 0..<m {
            let previous = polygon[(i - 1 + m) % m]
            let current = polygon[i]
            let next = polygon[(i + 1) % m]

            let dx1 = current.x - previous.x, dy1 = current.y - previous.y
            let len1 = (dx1 * dx1 + dy1 * dy1).squareRoot()
            let dx2 = next.x - current.x, dy2 = next.y - current.y
            let len2 = (dx2 * dx2 + dy2 * dy2).squareRoot()
            let cross = dx1 * dy2 - dy1 * dx2

            if cross > 0, len1 > 0, len2 > 0 {
                let cornerRadius = min(radius, len1 / 2, len2 / 2)
                let p1 = CGPoint(x: current.x - (dx1 / len1) * cornerRadius, y: current.y - (dy1 / len1) * cornerRadius)
                let p2 = CGPoint(x: current.x + (dx2 / len2) * cornerRadius, y: current.y + (dy2 / len2) * cornerRadius)
                if i == 0 { path.move(to: p1) } else { path.addLine(to: p1) }
                path.addQuadCurve(to: p2, control: CGPoint(x: current.x, y: current.y))
            } else {
                let p = CGPoint(x: current.x, y: current.y)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
        }
        path.closeSubpath()
        return path
    }
}
