import XCTest
import SwiftData
@testable import QuanLyChiTieu

final class ExtractionPipelineTests: XCTestCase {

    @MainActor
    func testPersistCreatesPendingAndDedups() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: PendingExtraction.self, Transaction.self, SpendingCategory.self,
            configurations: config
        )
        let store = PendingStore(container: container)

        let product = PendingProduct(
            hash: "abc",
            path: "abc.jpg",
            rawText: "MB Bank\n-500,000đ",
            parsed: ParsedTransaction(from: BankParseResult(
                amount: 500000, direction: .expense,
                occurredAt: Date(), note: "Chuyen tien",
                bankName: "MB Bank", suggestedCategoryName: "Chuyển tiền"
            )),
            source: .manualPhoto
        )

        XCTAssertEqual(store.persist(product), .created)

        // Cùng hash → duplicate
        XCTAssertEqual(store.persist(product), .duplicate)

        let all = try container.mainContext.fetch(FetchDescriptor<PendingExtraction>())
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.parsed?.amount, 500000)
    }

    @MainActor
    func testDedupKeyStableForSameTransaction() {
        let key1 = Transaction.dedupKey(bankName: "MB Bank", amount: 500000, occurredAt: Date(timeIntervalSince1970: 1_800_000_000), note: "Chuyen tien")
        let key2 = Transaction.dedupKey(bankName: "MB Bank", amount: 500000, occurredAt: Date(timeIntervalSince1970: 1_800_000_000), note: "Chuyen tien")
        XCTAssertEqual(key1, key2)

        let key3 = Transaction.dedupKey(bankName: "MB Bank", amount: 500001, occurredAt: Date(timeIntervalSince1970: 1_800_000_000), note: "Chuyen tien")
        XCTAssertNotEqual(key1, key3)
    }
}
