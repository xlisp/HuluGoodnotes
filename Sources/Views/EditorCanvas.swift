import SwiftUI
import PencilKit

/// 把 CanvasViewController 桥接到 SwiftUI。
struct EditorCanvas: UIViewControllerRepresentable {
    let initialDrawing: PKDrawing
    @Binding var isOCRMode: Bool
    @Binding var showGrid: Bool
    /// 每次自增即触发一次"自动整理"。
    var tidyToken: Int
    /// 每次自增即"重置基准并整理"。
    var resetTidyToken: Int
    /// 已保存的整理基准字高（nil 表示尚未整理过）。
    var initialTidyHeight: CGFloat?
    var onDrawingChanged: (PKDrawing) -> Void
    var onOCRRegion: (UIImage) -> Void
    /// 首次确立整理基准时回调，用于持久化。
    var onTidyStandardEstablished: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(lastTidyToken: tidyToken, lastResetToken: resetTidyToken)
    }

    func makeUIViewController(context: Context) -> CanvasViewController {
        let vc = CanvasViewController()
        vc.setInitialDrawing(initialDrawing)
        vc.showGrid = showGrid
        vc.isOCRMode = isOCRMode
        vc.tidyStandardHeight = initialTidyHeight
        vc.onDrawingChanged = onDrawingChanged
        vc.onOCRRegion = onOCRRegion
        vc.onTidyStandardEstablished = onTidyStandardEstablished
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
        if resetTidyToken != context.coordinator.lastResetToken {
            context.coordinator.lastResetToken = resetTidyToken
            vc.resetTidyStandardAndTidy()
        }
    }

    final class Coordinator {
        var lastTidyToken: Int
        var lastResetToken: Int
        init(lastTidyToken: Int, lastResetToken: Int) {
            self.lastTidyToken = lastTidyToken
            self.lastResetToken = lastResetToken
        }
    }
}
