import SwiftUI

struct OCRResult: Identifiable {
    let id = UUID()
    var text: String
}

/// 展示 OCR 识别结果，文字可编辑、可复制。
struct OCRResultView: View {
    @State var result: OCRResult
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextEditor(text: $result.text)
                    .font(.body)
                    .padding()
                    .scrollContentBackground(.hidden)
                    .background(Color(.secondarySystemBackground))
            }
            .navigationTitle("识别结果")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        UIPasteboard.general.string = result.text
                        copied = true
                    } label: {
                        Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                }
            }
        }
    }
}
