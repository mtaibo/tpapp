import Testing
@testable import TPPhotosFeature

@Suite struct PhotoGridDensityTests {
    private func level(_ columns: Int) -> Int {
        PhotoGridDensity.columnLevels.firstIndex(of: columns)!
    }

    @Test func tappingInDenseGridsZoomsInsteadOfOpening() {
        #expect(PhotoGridDensity.tapZoomLevel(fromLevel: level(31)) == level(15))
        #expect(PhotoGridDensity.tapZoomLevel(fromLevel: level(15)) == level(5))
        #expect(PhotoGridDensity.tapZoomLevel(fromLevel: level(9)) == level(5))
    }

    @Test func tappingAtFiveColumnsOrFewerOpensThePhoto() {
        #expect(PhotoGridDensity.tapZoomLevel(fromLevel: level(5)) == nil)
        #expect(PhotoGridDensity.tapZoomLevel(fromLevel: level(3)) == nil)
    }

    @Test func everyLevelHasAnOddColumnCount() {
        // Zooming about the middle column only lines the columns of two levels up when both
        // counts are odd.
        #expect(PhotoGridDensity.columnLevels.allSatisfy { $0 % 2 == 1 })
    }
}
