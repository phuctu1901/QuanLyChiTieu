import XCTest
import UIKit
import SwiftData
@testable import QuanLyChiTieu

/// Test end-to-end: render ảnh kiểu screenshot giao dịch → Vision OCR → parser.
/// Chạy trên simulator (Vision khả dụng), xác nhận pipeline thật hoạt động.
final class OCREndToEndTests: XCTestCase {

    func testRenderedBankScreenshotThroughOCRandParser() async throws {
        let imageData = Self.renderBankScreenshot()
        let lines = try await OCRService().recognizeLines(imageData: imageData)
        XCTAssertFalse(lines.isEmpty, "OCR phải đọc được text từ ảnh rendered")

        let result = BankMessageParser.parse(lines)
        XCTAssertEqual(result.bankName, "MB Bank")
        XCTAssertEqual(result.amount, 500_000)
        XCTAssertEqual(result.direction, .expense)
        XCTAssertNotNil(result.occurredAt)
    }

    @MainActor
    func testIngestPipelineDedupsSameImage() async throws {
        let imageData = Self.renderBankScreenshot()
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocr-e2e-\(UUID().uuidString)")

        var persisted: [PendingProduct] = []
        let container = try ModelContainer(
            for: PendingExtraction.self, Transaction.self, SpendingCategory.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = PendingStore(container: container)
        let pipeline = ExtractionPipeline(
            imageStore: ImageStore(directory: tmp),
            persist: { product in
                let outcome = store.persist(product)
                if outcome == .created {
                    persisted.append(product)
                }
                return outcome
            }
        )

        let first = await pipeline.ingest(imageData: imageData, source: .manualPhoto)
        let second = await pipeline.ingest(imageData: imageData, source: .manualPhoto)

        XCTAssertEqual(first, .created)
        XCTAssertEqual(second, .duplicate, "Cùng ảnh ingest lần 2 phải bị dedup")
        XCTAssertEqual(persisted.count, 1)

        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: - Helpers

    /// Vẽ ảnh trắng đen kiểu screenshot thông báo giao dịch MB.
    private static func renderBankScreenshot() -> Data {
        let size = CGSize(width: 800, height: 500)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            let lines: [(String, CGFloat, UIFont.Weight)] = [
                ("MB Bank", 56, .bold),
                ("Giao dich thanh cong", 28, .regular),
                ("Chuyen tien cho NGUYEN VAN A", 30, .medium),
                ("-500,000d", 60, .bold),
                ("17:34 - 15/08/2026", 26, .regular),
            ]
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center

            var y: CGFloat = 30
            for (text, fontSize, weight) in lines {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: fontSize, weight: weight),
                    .foregroundColor: UIColor.black,
                    .paragraphStyle: paragraph,
                ]
                let str = NSAttributedString(string: text, attributes: attrs)
                str.draw(in: CGRect(x: 0, y: y, width: size.width, height: fontSize + 16))
                y += fontSize + 28
            }
        }
        return image.jpegData(compressionQuality: 0.95)!
    }
}
