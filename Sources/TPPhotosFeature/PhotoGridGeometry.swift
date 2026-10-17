#if os(iOS)
import CoreGraphics

/// Where every tile of the grid sits for one column count: plain arithmetic on the item index.
/// Rows are cut from the newest end, so the partial row is the oldest one at the very top
/// (right-aligned): older photos arriving only ever add rows above, and no tile below them moves.
struct PhotoGridGeometry {
    let columns: Int
    let spacing: CGFloat
    let width: CGFloat
    let itemCount: Int
    let scale: CGFloat

    init(columns: Int, width: CGFloat, itemCount: Int, scale: CGFloat) {
        self.columns = columns
        self.spacing = Self.spacing(forColumns: columns)
        self.width = width
        self.itemCount = itemCount
        self.scale = scale > 0 ? scale : 2
    }

    static func spacing(forColumns columns: Int) -> CGFloat {
        columns >= 9 ? 1 : 2
    }

    /// A tile's width in points for `columns` across `width`.
    static func itemSide(width: CGFloat, columns: Int) -> CGFloat {
        let spacing = spacing(forColumns: columns)
        return max((width + spacing) / CGFloat(columns) - spacing, 0)
    }

    /// One tile plus the gap after it.
    var pitch: CGFloat {
        (width + spacing) / CGFloat(columns)
    }

    var leadingBlanks: Int {
        (columns - itemCount % columns) % columns
    }

    var rowCount: Int {
        (itemCount + leadingBlanks + columns - 1) / columns
    }

    var contentHeight: CGFloat {
        max(CGFloat(rowCount) * pitch - spacing, 0)
    }

    func frame(forItem item: Int) -> CGRect {
        let slot = item + leadingBlanks
        let row = CGFloat(slot / columns)
        let column = CGFloat(slot % columns)
        // Snapped to whole pixels so neighbouring tiles never blur or leave uneven seams.
        let minX = pixelRound(column * pitch)
        let maxX = pixelRound(column * pitch + pitch - spacing)
        let minY = pixelRound(row * pitch)
        let maxY = pixelRound(row * pitch + pitch - spacing)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// The items whose rows overlap `minY...maxY`.
    func items(fromY minY: CGFloat, toY maxY: CGFloat) -> Range<Int> {
        guard itemCount > 0, pitch > 0 else { return 0..<0 }
        let firstRow = max(Int((minY / pitch).rounded(.down)), 0)
        let lastRow = min(Int((maxY / pitch).rounded(.down)), rowCount - 1)
        guard firstRow <= lastRow else { return 0..<0 }
        let lower = max(firstRow * columns - leadingBlanks, 0)
        let upper = min((lastRow + 1) * columns - leadingBlanks, itemCount)
        return lower < upper ? lower..<upper : 0..<0
    }

    private func pixelRound(_ value: CGFloat) -> CGFloat {
        (value * scale).rounded() / scale
    }
}
#endif
