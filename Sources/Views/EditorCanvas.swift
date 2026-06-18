import SwiftUI
import PencilKit

/// 把 CanvasViewController 桥接到 SwiftUI。
struct EditorCanvas: UIViewControllerRepresentable {
    let initialDrawing: PKDrawing
    @Binding var isOCRMode: Bool
    @Binding var showGrid: Bool
    var onDrawingChanged: (PKDrawing) -> Void
    var onOCRRegion: (UIImage) -> Void

    func makeUIViewController(context: Context) -> CanvasViewController {
        let vc = CanvasViewController()
        vc.setInitialDrawing(initialDrawing)
        vc.showGrid = showGrid
        vc.isOCRMode = isOCRMode
        vc.onDrawingChanged = onDrawingChanged
        vc.onOCRRegion = onOCRRegion
        return vc
    }

    func updateUIViewController(_ vc: CanvasViewController, context: Context) {
        // 仅同步模式开关，避免回写 drawing 造成循环。
        vc.showGrid = showGrid
        vc.isOCRMode = isOCRMode
    }
}
