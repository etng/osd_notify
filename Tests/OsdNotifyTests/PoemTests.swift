import XCTest
@testable import OsdNotify

final class PoemTests: XCTestCase {
    func testTestTargetCanAccessRecitationHelpers() {
        let segments = splitRecitationText("君子曰：学不可以已。", delimiters: "。")
        XCTAssertEqual(segments, ["君子曰：学不可以已。"])
    }
}
