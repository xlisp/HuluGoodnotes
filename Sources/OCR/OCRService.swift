import UIKit
import Vision

/// 使用 Apple Vision 框架做本地文字识别（OCR）。支持中英文。
enum OCRService {

    /// 识别图片中的文字，结果在主线程回调。
    static func recognize(image: UIImage, completion: @escaping (String) -> Void) {
        // 手写笔迹通常是透明背景，先合成到白底上，识别更稳定。
        let prepared = whitened(image)
        guard let cgImage = prepared.cgImage else {
            DispatchQueue.main.async { completion("") }
            return
        }

        let request = VNRecognizeTextRequest { request, _ in
            let text = (request.results as? [VNRecognizedTextObservation])?
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n") ?? ""
            DispatchQueue.main.async { completion(text) }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                DispatchQueue.main.async { completion("") }
            }
        }
    }

    /// 把（可能透明的）图片绘制到白色背景上。
    private static func whitened(_ image: UIImage) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: image.size))
            image.draw(at: .zero)
        }
    }
}
