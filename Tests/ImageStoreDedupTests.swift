import XCTest
@testable import QuanLyChiTieu

final class ImageStoreDedupTests: XCTestCase {
    var store: ImageStore!

    override func setUp() {
        super.setUp()
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("dedup-tests-\(UUID().uuidString)")
        store = ImageStore(directory: tmp)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: store.directory)
        store = nil
        super.tearDown()
    }

    func testSaveSameDataTwiceSameHash() {
        let data = solidImageData(width: 100, height: 100)
        let first = store.save(data)
        let second = store.save(data)
        XCTAssertEqual(first?.hash, second?.hash)
        XCTAssertEqual(first?.path, second?.path)
    }

    func testHashStableAcrossContent() {
        let a = solidImageData(width: 100, height: 100)
        let b = solidImageData(width: 120, height: 120)
        XCTAssertNotEqual(ImageStore.sha256(a), ImageStore.sha256(b))
    }

    func testLoadImageRoundTrip() {
        let data = solidImageData(width: 80, height: 80)
        let saved = store.save(data)
        XCTAssertNotNil(saved)
        let loaded = store.loadImage(path: saved!.path)
        XCTAssertNotNil(loaded)
    }

    func testCleanupOrphans() {
        let data = solidImageData(width: 80, height: 80)
        let saved = store.save(data)
        XCTAssertNotNil(saved)
        store.cleanupOrphans(referencedPaths: [])
        XCTAssertNil(store.loadImage(path: saved!.path))
    }

    // Tạo ảnh JPEG solid color nhỏ
    private func solidImageData(width: Int, height: Int) -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        let image = renderer.image { ctx in
            UIColor.systemBlue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return image.jpegData(compressionQuality: 0.9)!
    }
}
