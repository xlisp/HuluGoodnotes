import UIKit
import PencilKit

/// 承载手写画布的控制器：PKCanvasView + 网格背景 + OCR 选择覆盖层 + 系统工具面板。
final class CanvasViewController: UIViewController {

    let canvasView = PKCanvasView()
    private let gridView = GridBackgroundView()
    private let selectionOverlay = SelectionOverlayView()
    private let toolPicker = PKToolPicker()

    /// 画布的高度（宽度跟随屏幕，可纵向滚动）。
    private let pageHeight: CGFloat = 2600

    var showGrid: Bool = true {
        didSet { gridView.isHidden = !showGrid }
    }

    var isOCRMode: Bool = false {
        didSet { updateOCRMode() }
    }

    /// 笔迹发生变化时回调（用于自动保存）。
    var onDrawingChanged: ((PKDrawing) -> Void)?
    /// 用户框选完成后回调，参数为框选区域内笔迹渲染出的图片。
    var onOCRRegion: ((UIImage) -> Void)?

    private var selectionStart: CGPoint = .zero

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        canvasView.translatesAutoresizingMaskIntoConstraints = false
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.alwaysBounceVertical = true
        canvasView.minimumZoomScale = 1
        canvasView.maximumZoomScale = 3
        canvasView.drawingPolicy = .anyInput   // 手指和 Apple Pencil 均可书写
        canvasView.delegate = self
        view.addSubview(canvasView)
        NSLayoutConstraint.activate([
            canvasView.topAnchor.constraint(equalTo: view.topAnchor),
            canvasView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            canvasView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            canvasView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        gridView.isHidden = !showGrid
        canvasView.insertSubview(gridView, at: 0)   // 放在笔迹下方

        selectionOverlay.frame = view.bounds
        selectionOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        selectionOverlay.isHidden = true
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleSelectionPan(_:)))
        selectionOverlay.addGestureRecognizer(pan)
        view.addSubview(selectionOverlay)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = canvasView.bounds.width
        guard width > 0 else { return }
        let size = CGSize(width: width, height: max(pageHeight, canvasView.bounds.height))
        canvasView.contentSize = size
        gridView.frame = CGRect(origin: .zero, size: size)
        selectionOverlay.frame = canvasView.frame
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        toolPicker.addObserver(canvasView)
        toolPicker.setVisible(!isOCRMode, forFirstResponder: canvasView)
        if !isOCRMode {
            canvasView.becomeFirstResponder()
        }
    }

    // MARK: - 公开方法

    func setInitialDrawing(_ drawing: PKDrawing) {
        canvasView.drawing = drawing
    }

    /// 自动把当前画布上的手写整理成整齐的行列并适当缩小，可撤销。
    func tidyDrawing() {
        let current = canvasView.drawing
        guard current.strokes.count > 1 else { return }

        let options = StrokeArranger.Options(
            origin: CGPoint(x: 40, y: 60),
            maxWidth: max(200, canvasView.bounds.width - 80)
        )
        let arranged = StrokeArranger.arrange(current, options: options)
        // 笔画数量应保持不变；不一致说明出现异常，放弃整理。
        guard arranged.strokes.count == current.strokes.count else { return }

        applyDrawing(arranged, undo: current)
    }

    /// 应用新的笔迹，并把反向操作登记到撤销栈（支持撤销 / 重做）。
    private func applyDrawing(_ newDrawing: PKDrawing, undo oldDrawing: PKDrawing) {
        canvasView.drawing = newDrawing
        onDrawingChanged?(newDrawing)
        undoManager?.registerUndo(withTarget: self) { vc in
            vc.applyDrawing(oldDrawing, undo: newDrawing)
        }
    }

    // MARK: - OCR 模式

    private func updateOCRMode() {
        guard isViewLoaded else { return }
        selectionOverlay.isHidden = !isOCRMode
        canvasView.drawingGestureRecognizer.isEnabled = !isOCRMode
        toolPicker.setVisible(!isOCRMode, forFirstResponder: canvasView)
        if isOCRMode {
            canvasView.resignFirstResponder()
        } else {
            canvasView.becomeFirstResponder()
        }
    }

    @objc private func handleSelectionPan(_ gesture: UIPanGestureRecognizer) {
        let point = gesture.location(in: selectionOverlay)
        switch gesture.state {
        case .began:
            selectionStart = point
            selectionOverlay.selectionRect = CGRect(origin: point, size: .zero)
        case .changed:
            selectionOverlay.selectionRect = makeRect(selectionStart, point)
        case .ended, .cancelled:
            let rect = makeRect(selectionStart, point)
            selectionOverlay.selectionRect = nil
            captureAndOCR(screenRect: rect)
        default:
            break
        }
    }

    private func makeRect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
               width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    private func captureAndOCR(screenRect: CGRect) {
        guard screenRect.width > 8, screenRect.height > 8 else { return }
        // 覆盖层坐标 -> 画布内容坐标（考虑滚动偏移与缩放）。
        let zoom = canvasView.zoomScale
        let contentRect = CGRect(
            x: (screenRect.minX + canvasView.contentOffset.x) / zoom,
            y: (screenRect.minY + canvasView.contentOffset.y) / zoom,
            width: screenRect.width / zoom,
            height: screenRect.height / zoom
        )
        // 只渲染笔迹（不含网格），作为干净的 OCR 输入。
        let image = canvasView.drawing.image(from: contentRect, scale: 3.0)
        onOCRRegion?(image)
    }
}

// MARK: - PKCanvasViewDelegate

extension CanvasViewController: PKCanvasViewDelegate {
    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        onDrawingChanged?(canvasView.drawing)
    }
}
