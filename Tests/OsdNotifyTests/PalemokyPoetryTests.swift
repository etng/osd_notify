import XCTest
@testable import OsdNotify

final class PalemokyPoetryTests: XCTestCase {
    func testDecodePalemokyRandomPoemResponse() throws {
        let json = """
        {
          "ok": true,
          "status": 200,
          "url": "https://poetry.palemoky.com/api/poems/random?lang=zh-Hans",
          "data": {
            "data": {
              "id": 240843,
              "title": "驼山秋晚二首  其一",
              "content": [
                "诗翁老去无人数，晚岁移家在河浒。",
                "败絮蒙头那复霜，破屋穿天只愁雨。"
              ],
              "author": {
                "id": 6553,
                "name": "周紫芝"
              },
              "dynasty": {
                "id": 6,
                "name": "唐"
              },
              "type": {
                "id": 14,
                "name": "七言律诗"
              }
            },
            "lang": "zh-Hans"
          }
        }
        """

        let response = try decodePalemokyRandomPoemResponse(Data(json.utf8))

        XCTAssertEqual(response.poem.id, 240843)
        XCTAssertEqual(response.poem.title, "驼山秋晚二首  其一")
        XCTAssertEqual(response.poem.author.name, "周紫芝")
        XCTAssertEqual(response.poem.content.count, 2)
    }

    func testDecodePalemokyRandomPoemResponseAcceptsDirectPayloadShape() throws {
        let json = """
        {
          "data": {
            "id": 210832,
            "title": "句 其四",
            "content": [
              "前瞰琵琶洲，后枕思禅寺。"
            ],
            "author": {
              "id": 8695,
              "name": "杨亿"
            },
            "dynasty": {
              "id": 6,
              "name": "唐"
            },
            "type": {
              "id": 99,
              "name": "其他"
            }
          },
          "lang": "zh-Hans"
        }
        """

        let response = try decodePalemokyRandomPoemResponse(Data(json.utf8))

        XCTAssertEqual(response.ok, true)
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(response.poem.id, 210832)
        XCTAssertEqual(response.poem.title, "句 其四")
        XCTAssertEqual(response.poem.content, ["前瞰琵琶洲，后枕思禅寺。"])
    }

    func testDecodePalemokyRandomPoemResponseReportsUnexpectedJSONShape() {
        let json = #"{"success":false,"message":"challenge required"}"#

        XCTAssertThrowsError(try decodePalemokyRandomPoemResponse(Data(json.utf8))) { error in
            guard case CLIError.message(let message) = error else {
                return XCTFail("Expected CLIError.message, got \(error)")
            }
            XCTAssertTrue(message.contains("JSON 结构不符合预期"))
        }
    }

    func testPalemokyPoetryLinesPreserveContentArrayElements() {
        let poem = PalemokyPoem(
            id: 240843,
            title: "驼山秋晚二首  其一",
            content: [
                "诗翁老去无人数，晚岁移家在河浒。",
                "败絮蒙头那复霜，破屋穿天只愁雨。"
            ],
            author: PalemokyPoemNamedValue(id: 6553, name: "周紫芝"),
            dynasty: PalemokyPoemNamedValue(id: 6, name: "唐"),
            type: PalemokyPoemNamedValue(id: 14, name: "七言律诗")
        )

        let lines = timedTextLines(for: poem, interval: 15, limit: nil)

        XCTAssertEqual(lines.map { $0.text }, poem.content)
        XCTAssertEqual(lines.map { $0.start }, [0, 15])
    }

    func testParsePoetryOptionsDefaultsToRandomChinesePoetry() throws {
        let options = try parsePoetryOptions([])

        XCTAssertEqual(options.mode, .random)
        XCTAssertEqual(options.lang, "zh-Hans")
        XCTAssertEqual(options.interval, 15)
        XCTAssertFalse(options.dryRun)
    }

    func testParsePoetryOptionsAcceptsPlaybackControls() throws {
        let options = try parsePoetryOptions([
            "random",
            "--lang", "zh-Hans",
            "--interval", "2.5",
            "--dry-run",
            "--limit", "3",
            "--speed", "50",
            "--no-clear"
        ])

        XCTAssertEqual(options.mode, .random)
        XCTAssertEqual(options.lang, "zh-Hans")
        XCTAssertEqual(options.interval, 2.5)
        XCTAssertTrue(options.dryRun)
        XCTAssertEqual(options.limit, 3)
        XCTAssertEqual(options.speed, 50)
        XCTAssertFalse(options.clearWhenFinished)
    }
}
