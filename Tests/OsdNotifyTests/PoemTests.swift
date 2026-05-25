import XCTest
@testable import OsdNotify

final class PoemTests: XCTestCase {
    func testTestTargetCanAccessRecitationHelpers() {
        let segments = splitRecitationText("君子曰：学不可以已。", delimiters: "。")
        XCTAssertEqual(segments, ["君子曰：学不可以已。"])
    }

    func testParseGuwendaoEntryLinksFromMainContent() throws {
        let html = """
        <div class="main3"><div class="left">
        <a href="/shiwenv_9b5ed8061abe.aspx">劝学</a>
        <a href="/shiwenv_178197fd7202.aspx">师说</a>
        <a href="/shiwenv_9b5ed8061abe.aspx">劝学重复</a>
        </div><div class="right"><a href="/shiwenv_deadbeef0000.aspx">噪声</a></div></div>
        """
        let links = parseGuwendaoEntryLinks(html, baseURL: guwendaoBaseURL)
        XCTAssertEqual(links.map(\.id), ["9b5ed8061abe", "178197fd7202"])
        XCTAssertEqual(links[0].entryTitle, "劝学")
        XCTAssertEqual(links[0].url.absoluteString, "https://www.guwendao.net/shiwenv_9b5ed8061abe.aspx")
    }

    func testParseGuwendaoPoemPageExtractsOriginalOnly() throws {
        let html = """
        <div id="zhengwen9b5ed8061abe">
        <h1>劝学(节选)</h1>
        <p class="source"><a>荀子</a><a>〔先秦〕</a></p>
        <div class="contson" id="contson9b5ed8061abe">
        <p>君子曰：学不可以已。</p><p>青，取之于蓝。</p>
        </div></div>
        <h2>译文及注释</h2><p>君子说：学习不可以停止。</p>
        """
        let link = GuwendaoPoemLink(
            id: "9b5ed8061abe",
            entryTitle: "劝学",
            url: URL(string: "https://www.guwendao.net/shiwenv_9b5ed8061abe.aspx")!
        )

        let item = try parseGuwendaoPoemPage(html, link: link)

        XCTAssertEqual(item.title, "劝学(节选)")
        XCTAssertEqual(item.author, "荀子")
        XCTAssertEqual(item.dynasty, "先秦")
        XCTAssertEqual(item.content, "君子曰：学不可以已。\n青，取之于蓝。")
        XCTAssertFalse(item.content.contains("君子说"))
    }

    func testFindBestPoemTitleMatchPrefersContainsRelationship() throws {
        let items = [
            GuwendaoPoemItem(
                id: "1",
                title: "师说",
                entryTitle: "师说",
                author: "韩愈",
                dynasty: "唐代",
                url: "https://example.com/1",
                content: "古之学者必有师。"
            ),
            GuwendaoPoemItem(
                id: "2",
                title: "劝学(节选)",
                entryTitle: "劝学",
                author: "荀子",
                dynasty: "先秦",
                url: "https://example.com/2",
                content: "君子曰：学不可以已。"
            )
        ]

        let match = try bestPoemMatch(for: "劝学", in: items)

        XCTAssertEqual(match.id, "2")
    }
}
