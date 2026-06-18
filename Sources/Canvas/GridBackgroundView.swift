import UIKit

/// 网格背景，辅助写字与画图。作为 PKCanvasView 的子视图放在笔迹下方，随内容一起滚动。
final class GridBackgroundView: UIView {
    var spacing: CGFloat = 28 { didSet { setNeedsDisplay() } }
    var lineColor: UIColor = UIColor.systemGray4 { didSet { setNeedsDisplay() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.setStrokeColor(lineColor.cgColor)
        ctx.setLineWidth(0.5)

        var x: CGFloat = 0
        while x <= bounds.width {
            ctx.move(to: CGPoint(x: x, y: 0))
            ctx.addLine(to: CGPoint(x: x, y: bounds.height))
            x += spacing
        }

        var y: CGFloat = 0
        while y <= bounds.height {
            ctx.move(to: CGPoint(x: 0, y: y))
            ctx.addLine(to: CGPoint(x: bounds.width, y: y))
            y += spacing
        }

        ctx.strokePath()
    }
}

/// OCR 选择模式下，用于绘制虚线选择框的透明覆盖层。
final class SelectionOverlayView: UIView {
    var selectionRect: CGRect? { didSet { setNeedsDisplay() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        guard let r = selectionRect, let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.setFillColor(UIColor.systemBlue.withAlphaComponent(0.12).cgColor)
        ctx.fill(r)
        ctx.setStrokeColor(UIColor.systemBlue.cgColor)
        ctx.setLineWidth(1.5)
        ctx.setLineDash(phase: 0, lengths: [6, 4])
        ctx.stroke(r)
    }
}
