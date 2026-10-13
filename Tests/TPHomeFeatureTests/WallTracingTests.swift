import Testing
@testable import TPHomeFeature

@Suite struct WallTracingTests {
    @Test func twoRoomsSharingAnEdge() {
        let rooms = [
            RoomRect(x: 0, y: 0, w: 100, h: 100),
            RoomRect(x: 100, y: 0, w: 100, h: 100)
        ]

        let (exterior, interior) = WallGeometry.computeWallSegments(rooms: rooms)

        #expect(exterior.count == 6)
        #expect(interior == [WallSegment(x1: 100, y1: 0, x2: 100, y2: 100)])

        let polygon = WallGeometry.traceExteriorPolygon(exterior)
        #expect(polygon.count == 4)
        #expect(Set(polygon) == Set([
            WallPoint(x: 0, y: 0),
            WallPoint(x: 200, y: 0),
            WallPoint(x: 200, y: 100),
            WallPoint(x: 0, y: 100)
        ]))
    }

    @Test func lShapedThreeRooms() {
        let rooms = [
            RoomRect(x: 0, y: 0, w: 100, h: 100),
            RoomRect(x: 100, y: 0, w: 100, h: 100),
            RoomRect(x: 0, y: 100, w: 100, h: 100)
        ]

        let (exterior, interior) = WallGeometry.computeWallSegments(rooms: rooms)

        #expect(exterior.count == 8)
        #expect(Set(interior) == Set([
            WallSegment(x1: 0, y1: 100, x2: 100, y2: 100),
            WallSegment(x1: 100, y1: 0, x2: 100, y2: 100)
        ]))

        let polygon = WallGeometry.traceExteriorPolygon(exterior)
        #expect(polygon.count == 6)
        #expect(Set(polygon) == Set([
            WallPoint(x: 0, y: 0),
            WallPoint(x: 200, y: 0),
            WallPoint(x: 200, y: 100),
            WallPoint(x: 100, y: 100),
            WallPoint(x: 100, y: 200),
            WallPoint(x: 0, y: 200)
        ]))
    }
}
