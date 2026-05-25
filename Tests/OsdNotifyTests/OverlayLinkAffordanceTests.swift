import AppKit
import XCTest
@testable import OsdNotify

final class OverlayLinkAffordanceTests: XCTestCase {
    func testLinkButtonRectSitsInBottomRightContentArea() {
        let rect = OverlayLinkAffordance.linkButtonRect(in: NSRect(x: 0, y: 0, width: 560, height: 120))

        XCTAssertEqual(rect.width, 24)
        XCTAssertEqual(rect.height, 24)
        XCTAssertEqual(rect.maxX, 540)
        XCTAssertEqual(rect.minY, 20)
    }

    func testShowOptionsAcceptURLWithoutTreatingItAsMessageText() throws {
        let options = try parseOptions(["message", "--url", "https://example.com/item"])

        XCTAssertEqual(options.message, "message")
        XCTAssertEqual(options.linkURL, "https://example.com/item")
    }

    func testReciteOptionsAcceptURLAsDisplayOption() throws {
        let options = try parseReciteOptions(["--text", "君子曰：学不可以已。", "--url", "https://example.com/poem"])

        XCTAssertEqual(options.displayOptions.linkURL, "https://example.com/poem")
    }

    func testPoemOptionsAcceptURLAsDisplayOption() throws {
        let options = try parsePoemOptions(["劝学", "--url", "https://example.com/source"])

        XCTAssertEqual(options.query, "劝学")
        XCTAssertEqual(options.displayOptions.linkURL, "https://example.com/source")
    }

    func testPoemRecitationOptionsDefaultLinkToSourceURL() {
        let item = GuwendaoPoemItem(
            id: "9b5ed8061abe",
            title: "劝学(节选)",
            entryTitle: "劝学",
            author: "荀子",
            dynasty: "先秦",
            url: "https://www.guwendao.net/shiwenv_9b5ed8061abe.aspx",
            content: "君子曰：学不可以已。"
        )

        let reciteOptions = recitationOptions(for: item, poemOptions: PoemOptions())

        XCTAssertEqual(reciteOptions.source, "荀子《劝学(节选)》")
        XCTAssertEqual(reciteOptions.displayOptions.linkURL, "https://www.guwendao.net/shiwenv_9b5ed8061abe.aspx")
    }
}
