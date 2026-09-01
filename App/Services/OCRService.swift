import Foundation
import Vision
import UIKit

/// OCR ảnh screenshot bằng Vision — offline, hỗ trợ tiếng Việt.
struct OCRService: Sendable {
    /// Nhận diện text, trả về mảng dòng (đã sắp xếp theo vị trí đọc).
    func recognizeLines(cgImage: CGImage) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let lines = observations.compactMap { obs in
                    obs.topCandidates(1).first?.string
                }
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["vi-VN", "en-US"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage)
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    func recognizeLines(imageData: Data) async throws -> [String] {
        guard let image = UIImage(data: imageData)?.cgImage else {
            throw URLError(.cannotDecodeRawData)
        }
        return try await recognizeLines(cgImage: image)
    }
}
