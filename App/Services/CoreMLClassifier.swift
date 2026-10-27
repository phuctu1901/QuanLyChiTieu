import Foundation
import Vision
import CoreML
import UIKit

/// Phân loại ảnh bằng Core ML model đã train sẵn — thay thế FoundationModels AI
/// khi Apple Intelligence không khả dụng hoặc không ổn định.
///
/// Model: TransactionClassifier.mlmodel (Create ML Image Classifier)
/// Classes: "transaction" (giao dịch ngân hàng VN) | "other" (ảnh thường)
/// Chạy on-device qua Neural Engine — nhanh, nhẹ (~7KB), không cần Apple Intelligence.
struct CoreMLClassifier: @unchecked Sendable {

    /// Confidence tối thiểu để coi là giao dịch (0.7 = 70%)
    static let threshold: Float = 0.7

    private let model: VNCoreMLModel

    init?(modelName: String = UserDefaults.standard.string(forKey: "selectedCoreMLModel") ?? "TransactionClassifier") {
        guard let url = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc"),
              let mlModel = try? MLModel(contentsOf: url, configuration: MLModelConfiguration()),
              let vnModel = try? VNCoreMLModel(for: mlModel) else {
            return nil
        }
        self.model = vnModel
    }

    /// Phân loại ảnh — trả (isTransaction, confidence).
    /// VNCoreMLModel thread-safe cho inference — gọi từ bất kỳ thread/actor nào.
    func classify(imageData: Data) -> (isTransaction: Bool, confidence: Float)? {
        guard let image = UIImage(data: imageData),
              let ciImage = image.ciImage ?? CIImage(image: image) else {
            return nil
        }

        var result: (Bool, Float)?
        let request = VNCoreMLRequest(model: model) { request, _ in
            guard let observations = request.results as? [VNClassificationObservation],
                  let top = observations.first else { return }
            let isTransaction = top.identifier == "transaction"
            result = (isTransaction, top.confidence)
        }
        request.imageCropAndScaleOption = .centerCrop

        let handler = VNImageRequestHandler(ciImage: ciImage)
        try? handler.perform([request])
        return result
    }
}
