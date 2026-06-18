import PencilKit
import UIKit

/// 把零散、大小不一的手写笔迹自动整理成整齐的行列。
///
/// 只移动 / 缩放整个字、不改变笔画形状，所以"写得大才好看"的字依旧好看。
/// 流程（针对横排中文，按投影切分，比逐笔画聚类更稳）：
///   1. 按笔画中心的纵向位置把笔画切成若干"行"；
///   2. 每行内按横向间隙切成若干"字"（同一字的笔画在横向上彼此交叠，如「三」不会被拆开）；
///   3. 把每个字归一化到统一字高、底端对齐到同一条基线，按统一字距 / 行距重排，整体缩小。
enum StrokeArranger {

    struct Options {
        /// 目标字高（pt）。`nil` 表示自动取中位字高再适当缩小。
        var targetGlyphHeight: CGFloat? = nil
        /// 自动模式下，相对中位字高的缩放比例（< 1 即整体缩小）。
        var autoShrink: CGFloat = 0.62
        /// 单个字相对目标字高的缩放下限 / 上限。
        /// 上限设得较大，才能把"忽小"的字放大到和别的字一样高，从而真正整齐。
        var minScale: CGFloat = 0.45
        var maxScale: CGFloat = 2.4
        /// 长横线 / 下划线等"非文字"笔画的宽高比阈值：超过它就不按字高归一化，避免被撑成粗条。
        var ruleAspectRatio: CGFloat = 3.5
        /// 排版起点（左上角）。
        var origin: CGPoint = CGPoint(x: 40, y: 60)
        /// 可用宽度，超出即换行。
        var maxWidth: CGFloat = 700
        /// 字间距相对目标字高的比例。
        var glyphSpacingRatio: CGFloat = 0.28
        /// 行间距相对目标字高的比例。
        var lineSpacingRatio: CGFloat = 0.7
        /// 行切分阈值：相邻笔画中心纵向间距超过 中位笔高 × 此比例 即视为换行。
        var lineDetectRatio: CGFloat = 1.4
        /// 字切分阈值：行内相邻笔画横向间隙超过 行高 × 此比例 即视为换字。
        var charGapRatio: CGFloat = 0.32
    }

    struct Result {
        /// 整理后的新笔迹。
        var drawing: PKDrawing
        /// 本次实际采用的目标字高；`0` 表示未发生整理（笔画过少）。
        /// 第一次整理后应把它锁定为"整理基准"，之后再整理都传回来。
        var glyphHeight: CGFloat
    }

    private struct Item {
        var index: Int
        var bounds: CGRect
    }

    private struct Glyph {
        var strokeIndices: [Int]
        var bounds: CGRect
    }

    /// 整理笔迹。
    /// - 若 `options.targetGlyphHeight` 非空，则严格按这个"基准字高"排版（保证多次整理大小一致）；
    /// - 否则自动取中位字高 × `autoShrink` 作为本次基准，并通过 `Result.glyphHeight` 返回，便于上层锁定。
    static func arrange(_ drawing: PKDrawing, options: Options = Options()) -> Result {
        let strokes = drawing.strokes
        guard strokes.count > 1 else { return Result(drawing: drawing, glyphHeight: 0) }

        let items = strokes.enumerated().map { Item(index: $0.offset, bounds: $0.element.renderBounds) }

        // 全局笔高中位数，作为行切分的尺度参照。
        let strokeHeights = items.map { $0.bounds.height }.sorted()
        let medianStrokeHeight = max(1, strokeHeights[strokeHeights.count / 2])

        // 1. 切行 → 2. 每行切字
        let lines = splitIntoLines(items, medianStrokeHeight: medianStrokeHeight, options: options)
            .map { splitLineIntoGlyphs($0, options: options) }
            .filter { !$0.isEmpty }

        let allGlyphs = lines.flatMap { $0 }
        guard allGlyphs.count > 1 else { return Result(drawing: drawing, glyphHeight: 0) }

        // 3. 估计典型字高（用近似方形的"正文字"，排除下划线等扁笔画）
        let bodyHeights = allGlyphs
            .filter { $0.bounds.width / max($0.bounds.height, 1) < options.ruleAspectRatio }
            .map { $0.bounds.height }
            .sorted()
        let heights = bodyHeights.isEmpty ? allGlyphs.map { $0.bounds.height }.sorted() : bodyHeights
        let median = heights[heights.count / 2]

        let target = max(12, options.targetGlyphHeight ?? median * options.autoShrink)
        let spacing = target * options.glyphSpacingRatio
        let lineSpacing = target * options.lineSpacingRatio

        // 4. 逐行重排：每个字归一化到统一字高，底端对齐到同一条基线。
        var newStrokes = strokes
        var penY = options.origin.y

        for line in lines {
            var penX = options.origin.x

            for glyph in line {
                let scale = scaleFor(glyph.bounds, target: target, options: options)
                let w = glyph.bounds.width * scale
                let h = glyph.bounds.height * scale

                if penX > options.origin.x, penX + w > options.origin.x + options.maxWidth {
                    penY += target + lineSpacing
                    penX = options.origin.x
                }

                // 底端对齐：每个字底边都落在基线 penY + target 上；字高统一后顶边自然也齐。
                let newY = penY + (target - h)
                let t = CGAffineTransform(translationX: -glyph.bounds.minX, y: -glyph.bounds.minY)
                    .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                    .concatenating(CGAffineTransform(translationX: penX, y: newY))

                for idx in glyph.strokeIndices {
                    newStrokes[idx].transform = newStrokes[idx].transform.concatenating(t)
                }

                penX += w + spacing
            }

            penY += target + lineSpacing
        }

        return Result(drawing: PKDrawing(strokes: newStrokes), glyphHeight: target)
    }

    // MARK: - 切行

    /// 按笔画中心 Y 把笔画切成若干行；行内笔画按 X 排序。
    /// 用中心而非包围盒，避免高个笔画把下一行一起吞进同一行。
    private static func splitIntoLines(_ items: [Item],
                                       medianStrokeHeight: CGFloat,
                                       options: Options) -> [[Item]] {
        let sorted = items.sorted { $0.bounds.midY < $1.bounds.midY }
        guard let first = sorted.first else { return [] }

        let threshold = max(8, medianStrokeHeight * options.lineDetectRatio)
        var lines: [[Item]] = [[first]]
        var lastCenter = first.bounds.midY

        for it in sorted.dropFirst() {
            if it.bounds.midY - lastCenter > threshold {
                lines.append([it])
            } else {
                lines[lines.count - 1].append(it)
            }
            lastCenter = it.bounds.midY
        }

        return lines.map { $0.sorted { $0.bounds.minX < $1.bounds.minX } }
    }

    // MARK: - 行内切字

    /// 在一行内按横向间隙把笔画切成字：横向交叠或贴近的笔画归为同一字
    /// （如「三」「言」这类竖直分离的部件因横向交叠而被正确保留为一个字）。
    private static func splitLineIntoGlyphs(_ lineItems: [Item], options: Options) -> [Glyph] {
        guard !lineItems.isEmpty else { return [] }

        // 用本行的高度作为字间隙的尺度参照，比单个笔画更稳。
        let lineMinY = lineItems.map { $0.bounds.minY }.min() ?? 0
        let lineMaxY = lineItems.map { $0.bounds.maxY }.max() ?? 0
        let lineHeight = max(8, lineMaxY - lineMinY)
        let gapThreshold = lineHeight * options.charGapRatio

        let sorted = lineItems.sorted { $0.bounds.minX < $1.bounds.minX }
        var glyphs: [Glyph] = []
        var currentIndices: [Int] = []
        var currentBounds: CGRect = .null
        var currentMaxX: CGFloat = -.greatestFiniteMagnitude

        for it in sorted {
            // 与当前字横向有交叠或间隙小 → 同一字；否则另起一字。
            if !currentIndices.isEmpty, it.bounds.minX - currentMaxX > gapThreshold {
                glyphs.append(Glyph(strokeIndices: currentIndices, bounds: currentBounds))
                currentIndices = []
                currentBounds = .null
                currentMaxX = -.greatestFiniteMagnitude
            }
            currentIndices.append(it.index)
            currentBounds = currentBounds.isNull ? it.bounds : currentBounds.union(it.bounds)
            currentMaxX = max(currentMaxX, it.bounds.maxX)
        }
        if !currentIndices.isEmpty {
            glyphs.append(Glyph(strokeIndices: currentIndices, bounds: currentBounds))
        }
        return glyphs
    }

    // MARK: - 缩放

    /// 计算单个字的缩放：正文字归一化到目标字高；过宽的下划线 / 长横不放大，避免变成粗条。
    private static func scaleFor(_ bounds: CGRect, target: CGFloat, options: Options) -> CGFloat {
        let h = max(bounds.height, 1)
        let aspect = bounds.width / h
        let raw = target / h
        if aspect > options.ruleAspectRatio {
            return min(raw, 1.0)
        }
        return min(max(raw, options.minScale), options.maxScale)
    }
}
