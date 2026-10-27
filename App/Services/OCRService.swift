import Foundation
import Vision
import UIKit

/// OCR ảnh screenshot bằng Vision — offline, hỗ trợ tiếng Việt.
struct OCRService: Sendable {
    /// Nhận diện text, trả về mảng dòng (đã sắp xếp theo vị trí đọc).
    /// Thử với language correction trước (chính xác hơn cho tiếng Việt).
    /// Nếu vi.lm chưa tải → fallback không dùng correction (vẫn hoạt động tốt).
    func recognizeLines(cgImage: CGImage) async throws -> [String] {
        // Thử với language correction (cần vi.lm asset)
        if let lines = try? await _recognize(cgImage: cgImage, useCorrection: true), !lines.isEmpty {
            return lines
        }
        // Fallback: không correction — tránh lỗi vi.lm/lm.dat
        return try await _recognize(cgImage: cgImage, useCorrection: false)
    }

    private func _recognize(cgImage: CGImage, useCorrection: Bool) async throws -> [String] {
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
            request.recognitionLanguages = ["vi", "en"]
            request.usesLanguageCorrection = useCorrection

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
