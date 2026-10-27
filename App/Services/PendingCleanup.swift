import Foundation
import SwiftData

/// Dọn pending rác: pending CHƯA resolve mà ảnh giờ bị classifier loại
/// (tồn tại từ version cũ trước khi có filter) → xoá pending + ảnh, KHÔNG đụng
/// pending đã resolve và Transaction đã confirm.
enum PendingCleanup {

    /// Xoá pending chưa resolve có classification ≠ transaction.
    /// Trả số pending đã xoá. Chạy trên main actor vì dùng ModelContext.
    @MainActor
    static func removeUnrelatedUnresolved(context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<PendingExtraction>(
            predicate: #Predicate { $0.resolvedAt == nil }
        )
        guard let pendings = try? context.fetch(descriptor) else { return 0 }

        var removed = 0
        for pending in pendings {
            let lines = pending.ocrRawText
                .components(separatedBy: "\n")
                .filter { !$0.isEmpty }
            // Ảnh từng được ingest → nếu classifier giờ loại thì text phải đọc được;
            // .unreadable cũng coi như rác vì OCR rỗng không dùng được
            guard ImageClassifier.classify(lines: lines) != .transaction else { continue }

            let imagePath = pending.imagePath
            context.delete(pending)
            if !imagePath.isEmpty {
                ImageStore.shared?.delete(path: imagePath)
            }
            removed += 1
        }
        try? context.save()
        return removed
    }
}
