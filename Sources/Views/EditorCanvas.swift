import SwiftUI
import PencilKit

/// 把 CanvasViewController 桥接到 SwiftUI。
struct EditorCanvas: UIViewControllerRepresentable {
    let initialDrawing: PKDrawing
    @Binding var isOCRMode: Bool
    @Binding var showGrid: Bool
    /// 每次自增即触发一次"自动整理"。
    var tidyToken: Int
    var onDrawingChanged: (PKDrawing) -> Void
    var onOCRRegion: (UIImage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(lastTidyToken: tidyToken) }

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

        if tidyToken != context.coordinator.lastTidyToken {
            context.coordinator.lastTidyToken = tidyToken
            vc.tidyDrawing()
        }
    }

    final class Coordinator {
        var lastTidyToken: Int
        init(lastTidyToken: Int) { self.lastTidyToken = lastTidyToken }
    }
}
