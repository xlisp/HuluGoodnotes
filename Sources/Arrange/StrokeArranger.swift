import PencilKit
import UIKit

/// 把零散、大小不一的手写笔迹自动整理成整齐的行列。
///
/// 思路（只移动 / 缩放整个字，不改变笔画本身的形状，所以"写得大才好看"的字依旧好看）：
///   1. 把空间上邻近的笔画聚成一个"字"（glyph）；
///   2. 把纵向重叠的"字"聚成一"行"（row）；
///   3. 统一字高、字距、行距重新排版，并整体缩小，以节省白板空间。
enum StrokeArranger {

    struct Options {
        /// 目标字高（pt）。`nil` 表示自动取中位字高再适当缩小。
        var targetGlyphHeight: CGFloat? = nil
        /// 自动模式下，相对中位字高的缩放比例（< 1 即整体缩小）。
        var autoShrink: CGFloat = 0.6
        /// 单个字相对目标字高最多放大多少（避免标点等小字被撑得过大）。
        var maxUpscale: CGFloat = 1.15
        /// 排版起点（左上角）。
        var origin: CGPoint = CGPoint(x: 40, y: 60)
        /// 可用宽度，超出即换行。
        var maxWidth: CGFloat = 700
        /// 字间距相对目标字高的比例。
        var glyphSpacingRatio: CGFloat = 0.22
        /// 行间距相对目标字高的比例。
        var lineSpacingRatio: CGFloat = 0.55
        /// 判定两笔画属于同一个字时，允许的横向间距（相对字高的比例）。
        var glyphMergeGapRatio: CGFloat = 0.2
    }

    private struct Glyph {
        var strokeIndices: [Int]
        var bounds: CGRect
    }

    /// 返回整理后的新 `PKDrawing`。若笔画过少则原样返回。
    static func arrange(_ drawing: PKDrawing, options: Options = Options()) -> PKDrawing {
        let strokes = drawing.strokes
        guard strokes.count > 1 else { return drawing }

        let items: [(index: Int, bounds: CGRect)] = strokes.enumerated().map {
            ($0.offset, $0.element.renderBounds)
        }

        // 1. 聚成字
        let glyphGroups = clusterIntoGlyphs(items, options: options)
        var glyphs: [Glyph] = glyphGroups.compactMap { group in
            let rects = group.map { items[$0].bounds }
            guard let box = rects.unionRect() else { return nil }
            return Glyph(strokeIndices: group.map { items[$0].index }, bounds: box)
        }
        guard glyphs.count > 1 else { return drawing }

        // 2. 聚成行
        let rows = clusterIntoRows(glyphs)

        // 3. 确定目标字高
        let heights = glyphs.map { $0.bounds.height }.sorted()
        let median = heights[heights.count / 2]
        let target = max(12, options.targetGlyphHeight ?? median * options.autoShrink)
        let spacing = target * options.glyphSpacingRatio
        let lineSpacing = target * options.lineSpacingRatio

        // 4. 逐行重新排版，生成每个字的仿射变换
        var newStrokes = strokes
        var penX = options.origin.x
        var penY = options.origin.y

        for row in rows {
            penX = options.origin.x
            var lineHeight: CGFloat = 0

            for glyph in row {
                let h = max(glyph.bounds.height, 1)
                let scale = min(target / h, options.maxUpscale)
                let w = glyph.bounds.width * scale
                let scaledH = glyph.bounds.height * scale

                // 行内超宽则软换行
                if penX > options.origin.x, penX + w > options.origin.x + options.maxWidth {
                    penY += lineHeight + lineSpacing
                    penX = options.origin.x
                    lineHeight = 0
                }

                // 把字从原位置缩放并平移到笔头位置（顶端对齐）
                let t = CGAffineTransform(translationX: -glyph.bounds.minX, y: -glyph.bounds.minY)
                    .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                    .concatenating(CGAffineTransform(translationX: penX, y: penY))

                for idx in glyph.strokeIndices {
                    newStrokes[idx].transform = newStrokes[idx].transform.concatenating(t)
                }

                penX += w + spacing
                lineHeight = max(lineHeight, scaledH)
            }

            penY += lineHeight + lineSpacing
        }

        return PKDrawing(strokes: newStrokes)
    }

    // MARK: - 聚类

    /// 用并查集把横向贴近且纵向重叠的笔画并成同一个字。
    private static func clusterIntoGlyphs(_ items: [(index: Int, bounds: CGRect)],
                                          options: Options) -> [[Int]] {
        let n = items.count
        var parent = Array(0..<n)
        func find(_ x: Int) -> Int {
            var r = x
            while parent[r] != r { parent[r] = parent[parent[r]]; r = parent[r] }
            return r
        }
        func union(_ a: Int, _ b: Int) { parent[find(a)] = find(b) }

        for i in 0..<n {
            for j in (i + 1)..<n where sameGlyph(items[i].bounds, items[j].bounds, options: options) {
                union(i, j)
            }
        }

        var groups: [Int: [Int]] = [:]
        for i in 0..<n { groups[find(i), default: []].append(i) }
        return Array(groups.values)
    }

    private static func sameGlyph(_ a: CGRect, _ b: CGRect, options: Options) -> Bool {
        let h = max(a.height, b.height, 1)
        let xGap = max(0, max(a.minX - b.maxX, b.minX - a.maxX))
        let yOverlap = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        return xGap < options.glyphMergeGapRatio * h && yOverlap > -0.2 * h
    }

    /// 按纵向重叠把字聚成行；行内按 x 排序，行按 y 排序。
    private static func clusterIntoRows(_ glyphs: [Glyph]) -> [[Glyph]] {
        let sorted = glyphs.sorted { $0.bounds.midY < $1.bounds.midY }
        var rows: [[Glyph]] = []
        var rowMaxY: CGFloat = -.greatestFiniteMagnitude

        for g in sorted {
            if !rows.isEmpty, g.bounds.midY <= rowMaxY {
                rows[rows.count - 1].append(g)
                rowMaxY = max(rowMaxY, g.bounds.maxY)
            } else {
                rows.append([g])
                rowMaxY = g.bounds.maxY
            }
        }

        return rows.map { $0.sorted { $0.bounds.minX < $1.bounds.minX } }
    }
}

private extension Array where Element == CGRect {
    /// 数组中所有矩形的并集；空数组返回 nil。
    func unionRect() -> CGRect? {
        guard var box = first else { return nil }
        for r in dropFirst() { box = box.union(r) }
        return box
    }
}
