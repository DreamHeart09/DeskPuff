import Foundation

/// Deterministic MaxRects-style best-short-side-fit packing for the compact grid sizes
/// used by the inventory. Several stable item orderings are scored to preserve a large,
/// rectangular free area rather than only minimizing used cell count.
public enum InventoryPacker {
    private struct Rect: Equatable {
        var x: Int
        var y: Int
        var width: Int
        var height: Int
        var maxX: Int { x + width }
        var maxY: Int { y + height }
        var area: Int { width * height }
        func contains(_ other: Rect) -> Bool {
            x <= other.x && y <= other.y && maxX >= other.maxX && maxY >= other.maxY
        }
        func intersects(_ other: Rect) -> Bool {
            x < other.maxX && maxX > other.x && y < other.maxY && maxY > other.y
        }
    }

    private struct Placement {
        var item: InventoryItem
        var rect: Rect
        var shortSideFit: Int
        var longSideFit: Int
        var areaFit: Int
        var contact: Int
        var rotationChange: Int
    }

    public static func pack(_ source: InventoryLayout) -> InventoryLayout? {
        let stored = source.items.filter { $0.location == .stored }
        guard stored.reduce(0, { $0 + $1.footprint.width * $1.footprint.height }) <= source.columns * source.rows else { return nil }

        let orderings = [
            stored.sorted(by: areaThenLongSide),
            stored.sorted(by: widthThenHeight),
            stored.sorted(by: stableOriginalOrder)
        ]
        let desktop = source.items.filter { $0.location == .desktop }
        let packed = orderings.compactMap { pack(order: $0, desktop: desktop, source: source) }
        return packed.max { score($0, comparedTo: source) < score($1, comparedTo: source) }
    }

    private static func pack(order: [InventoryItem], desktop: [InventoryItem], source: InventoryLayout) -> InventoryLayout? {
        var freeRects = [Rect(x: 0, y: 0, width: source.columns, height: source.rows)]
        var arranged = desktop

        for original in order {
            var best: Placement?
            for free in freeRects {
                for turns in orientationOptions(for: original) {
                    var item = original
                    item.rotationQuarterTurns = turns
                    let size = item.footprint
                    guard size.width <= free.width, size.height <= free.height else { continue }
                    let rect = Rect(x: free.x, y: free.y, width: size.width, height: size.height)
                    let tentative = InventoryLayout(columns: source.columns, rows: source.rows, items: arranged)
                    guard tentative.canPlace(item, at: rect.x, row: rect.y) else { continue }
                    let candidate = Placement(item: item, rect: rect,
                                              shortSideFit: min(free.width - size.width, free.height - size.height),
                                              longSideFit: max(free.width - size.width, free.height - size.height),
                                              areaFit: free.area - size.width * size.height,
                                              contact: contactScore(rect, arranged: arranged, columns: source.columns, rows: source.rows),
                                              rotationChange: item.rotationQuarterTurns == original.rotationQuarterTurns ? 0 : 1)
                    if isBetter(candidate, than: best) { best = candidate }
                }
            }
            guard let best else { return nil }
            var item = best.item
            item.column = best.rect.x
            item.row = best.rect.y
            arranged.append(item)
            freeRects = split(freeRects, around: best.rect)
        }
        return InventoryLayout(columns: source.columns, rows: source.rows, items: arranged)
    }

    private static func orientationOptions(for item: InventoryItem) -> [Int] {
        let original = item.isRotated ? 1 : 0
        let turned = original == 0 ? 1 : 0
        return item.footprint.width == item.footprint.height ? [original] : [original, turned]
    }

    private static func isBetter(_ candidate: Placement, than current: Placement?) -> Bool {
        guard let current else { return true }
        if candidate.shortSideFit != current.shortSideFit { return candidate.shortSideFit < current.shortSideFit }
        if candidate.longSideFit != current.longSideFit { return candidate.longSideFit < current.longSideFit }
        if candidate.areaFit != current.areaFit { return candidate.areaFit < current.areaFit }
        if candidate.contact != current.contact { return candidate.contact > current.contact }
        if candidate.rotationChange != current.rotationChange { return candidate.rotationChange < current.rotationChange }
        if candidate.rect.y != current.rect.y { return candidate.rect.y < current.rect.y }
        return candidate.rect.x < current.rect.x
    }

    private static func split(_ rects: [Rect], around used: Rect) -> [Rect] {
        var result: [Rect] = []
        for free in rects {
            guard free.intersects(used) else { result.append(free); continue }
            if used.x > free.x { result.append(Rect(x: free.x, y: free.y, width: used.x - free.x, height: free.height)) }
            if used.maxX < free.maxX { result.append(Rect(x: used.maxX, y: free.y, width: free.maxX - used.maxX, height: free.height)) }
            if used.y > free.y { result.append(Rect(x: free.x, y: free.y, width: free.width, height: used.y - free.y)) }
            if used.maxY < free.maxY { result.append(Rect(x: free.x, y: used.maxY, width: free.width, height: free.maxY - used.maxY)) }
        }
        result.removeAll { $0.width <= 0 || $0.height <= 0 }
        var keep: [Rect] = []
        for index in result.indices {
            if result.indices.contains(where: { $0 != index && result[$0] != result[index] && result[$0].contains(result[index]) }) { continue }
            if !keep.contains(result[index]) { keep.append(result[index]) }
        }
        return keep
    }

    private static func contactScore(_ rect: Rect, arranged: [InventoryItem], columns: Int, rows: Int) -> Int {
        var score = 0
        if rect.x == 0 { score += rect.height }
        if rect.maxX == columns { score += rect.height }
        if rect.y == 0 { score += rect.width }
        if rect.maxY == rows { score += rect.width }
        for other in arranged where other.location == .stored {
            let size = other.footprint
            let overlapX = max(0, min(rect.maxX, other.column + size.width) - max(rect.x, other.column))
            let overlapY = max(0, min(rect.maxY, other.row + size.height) - max(rect.y, other.row))
            if rect.maxX == other.column || other.column + size.width == rect.x { score += overlapY }
            if rect.maxY == other.row || other.row + size.height == rect.y { score += overlapX }
        }
        return score
    }

    private static func score(_ layout: InventoryLayout, comparedTo original: InventoryLayout) -> Int {
        let columns = layout.columns, rows = layout.rows
        var occupied = Array(repeating: false, count: columns * rows)
        var changes = 0
        var rotations = 0
        for item in layout.items where item.location == .stored {
            let size = item.footprint
            for y in item.row..<(item.row + size.height) {
                for x in item.column..<(item.column + size.width) { occupied[y * columns + x] = true }
            }
            if let old = original.items.first(where: { $0.id == item.id }) {
                if old.column != item.column || old.row != item.row { changes += 1 }
                if old.rotationQuarterTurns != item.rotationQuarterTurns { rotations += 1 }
            }
        }

        var largestRectangle = 0
        for top in 0..<rows {
            var clear = Array(repeating: true, count: columns)
            for bottom in top..<rows {
                for x in 0..<columns { clear[x] = clear[x] && !occupied[bottom * columns + x] }
                var run = 0
                for open in clear {
                    run = open ? run + 1 : 0
                    largestRectangle = max(largestRectangle, run * (bottom - top + 1))
                }
            }
        }

        var seen = Array(repeating: false, count: columns * rows)
        var largestRegion = 0
        var tinyRegions = 0
        for index in occupied.indices where !occupied[index] && !seen[index] {
            var queue = [index]
            seen[index] = true
            var cursor = 0
            while cursor < queue.count {
                let cell = queue[cursor]; cursor += 1
                let x = cell % columns, y = cell / columns
                for neighbor in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] {
                    let (nx, ny) = neighbor
                    guard nx >= 0, nx < columns, ny >= 0, ny < rows else { continue }
                    let next = ny * columns + nx
                    if !occupied[next] && !seen[next] { seen[next] = true; queue.append(next) }
                }
            }
            largestRegion = max(largestRegion, queue.count)
            if queue.count <= 2 { tinyRegions += 1 }
        }
        return largestRectangle * 100_000 + largestRegion * 1_000 - tinyRegions * 100 - changes * 2 - rotations
    }

    private static func area(_ item: InventoryItem) -> Int { item.footprint.width * item.footprint.height }
    private static func longestSide(_ item: InventoryItem) -> Int { max(item.footprint.width, item.footprint.height) }
    private static func areaThenLongSide(_ lhs: InventoryItem, _ rhs: InventoryItem) -> Bool {
        if area(lhs) != area(rhs) { return area(lhs) > area(rhs) }
        if longestSide(lhs) != longestSide(rhs) { return longestSide(lhs) > longestSide(rhs) }
        return stableOriginalOrder(lhs, rhs)
    }
    private static func widthThenHeight(_ lhs: InventoryItem, _ rhs: InventoryItem) -> Bool {
        if lhs.footprint.width != rhs.footprint.width { return lhs.footprint.width > rhs.footprint.width }
        if lhs.footprint.height != rhs.footprint.height { return lhs.footprint.height > rhs.footprint.height }
        return stableOriginalOrder(lhs, rhs)
    }
    private static func stableOriginalOrder(_ lhs: InventoryItem, _ rhs: InventoryItem) -> Bool {
        if lhs.row != rhs.row { return lhs.row < rhs.row }
        if lhs.column != rhs.column { return lhs.column < rhs.column }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
