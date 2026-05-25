import AppKit
import XCTest
@testable import OsdNotify

final class OverlayCloseAffordanceTests: XCTestCase {
    func testCloseButtonRectSitsInTopRightContentArea() {
        let rect = OverlayCloseAffordance.closeButtonRect(in: NSRect(x: 0, y: 0, width: 560, height: 120))

        XCTAssertEqual(rect.width, 24)
        XCTAssertEqual(rect.height, 24)
        XCTAssertEqual(rect.maxX, 540)
        XCTAssertEqual(rect.maxY, 100)
    }

    func testTitleHitRectCoversRenderedTitleLineButNotMessageLine() {
        let hitRect = OverlayCloseAffordance.titleHitRect(
            contentRect: NSRect(x: 2, y: 2, width: 560, height: 120),
            titleY: 72,
            titleHeight: 19,
            textX: 40,
            textWidth: 480
        )

        XCTAssertTrue(hitRect.contains(NSPoint(x: 120, y: 80)))
        XCTAssertFalse(hitRect.contains(NSPoint(x: 120, y: 45)))
    }
}
