import SwiftUI
import PencilKit

/// 笔记编辑页：手写画布 + 工具栏（网格开关、OCR 框选）。
struct NoteEditorView: View {
    @ObservedObject var store: NoteStore
    let note: NoteMetadata

    @State private var drawing = PKDrawing()
    @State private var isLoaded = false
    @State private var isOCRMode = false
    @State private var showGrid = true
    @State private var tidyToken = 0
    @State private var isRecognizing = false
    @State private var ocrResult: OCRResult?
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            if isLoaded {
                EditorCanvas(
                    initialDrawing: drawing,
                    isOCRMode: $isOCRMode,
                    showGrid: $showGrid,
                    tidyToken: tidyToken,
                    onDrawingChanged: { newDrawing in
                        drawing = newDrawing
                        scheduleSave(newDrawing)
                    },
                    onOCRRegion: { image in
                        runOCR(image)
                    }
                )
                .ignoresSafeArea(edges: .bottom)
            } else {
                ProgressView()
            }

            if isOCRMode {
                hintBanner
            }

            if isRecognizing {
                recognizingOverlay
            }
        }
        .navigationTitle(note.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    tidyToken += 1
                } label: {
                    Label("整理", systemImage: "wand.and.stars")
                }
                .disabled(isOCRMode)

                Button {
                    showGrid.toggle()
                } label: {
                    Label("网格", systemImage: showGrid ? "grid" : "square")
                }

                Button {
                    isOCRMode.toggle()
                } label: {
                    Label("OCR", systemImage: "text.viewfinder")
                        .foregroundStyle(isOCRMode ? Color.accentColor : Color.primary)
                }
            }
        }
        .onAppear(perform: load)
        .onDisappear {
            saveTask?.cancel()
            save(drawing)
        }
        .sheet(item: $ocrResult) { result in
            OCRResultView(result: result)
        }
    }

    // MARK: - 提示与加载浮层

    private var hintBanner: some View {
        VStack {
            Text("框选要识别的文字区域")
                .font(.callout.weight(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.top, 12)
            Spacer()
        }
    }

    private var recognizingOverlay: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("识别中…")
                .font(.callout)
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - 逻辑

    private func load() {
        guard !isLoaded else { return }
        drawing = store.loadDrawing(note.id)
        isLoaded = true
    }

    private func scheduleSave(_ drawing: PKDrawing) {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            if Task.isCancelled { return }
            save(drawing)
        }
    }

    private func save(_ drawing: PKDrawing) {
        let thumb = makeThumbnail(drawing)
        store.saveDrawing(note.id, drawing: drawing, thumbnail: thumb)
    }

    private func makeThumbnail(_ drawing: PKDrawing) -> UIImage {
        let pageRect = CGRect(x: 0, y: 0, width: 600, height: 800)
        let ink = drawing.image(from: pageRect, scale: 0.5)
        // 合成到白底，作为卡片缩略图。
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: pageRect.size, format: format)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(pageRect)
            ink.draw(in: pageRect)
        }
    }

    private func runOCR(_ image: UIImage) {
        isRecognizing = true
        OCRService.recognize(image: image) { text in
            isRecognizing = false
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            ocrResult = OCRResult(text: trimmed.isEmpty ? "未识别到文字" : trimmed)
            if !trimmed.isEmpty {
                UIPasteboard.general.string = trimmed
            }
            isOCRMode = false
        }
    }
}
