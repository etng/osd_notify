import XCTest
@testable import OsdNotify

final class GuidanceTests: XCTestCase {
    func testMissingMessageShowsGuidance() throws {
        let options = try parseOptions([])
        XCTAssertEqual(options.titleOverride, "欢迎使用OSD Notify")
        XCTAssertTrue(options.message.contains("osd-notify show"))
        XCTAssertTrue(options.message.contains("osd-notify --help"))
        XCTAssertTrue(options.message.contains("--ttl 10"))
        XCTAssertTrue(options.message.contains("双击标题栏"))
        XCTAssertTrue(options.message.contains("关闭图标"))
        XCTAssertTrue(options.message.contains("点击"))
        XCTAssertTrue(options.message.contains("\n"))
        XCTAssertEqual(options.level, .info)
        XCTAssertEqual(options.ttl, 60)
    }

    func testGuidanceHonorsExplicitOptions() throws {
        let options = try parseOptions(["--ttl", "10", "--level", "warn"])
        XCTAssertEqual(options.ttl, 10)
        XCTAssertEqual(options.level, .warn)
    }

    func testCustomMessageKeepsExistingDefaults() throws {
        let options = try parseOptions(["任务正在进行"])
        XCTAssertEqual(options.message, "任务正在进行")
        XCTAssertNil(options.titleOverride)
        XCTAssertEqual(options.level, .busy)
        XCTAssertEqual(options.ttl, 3600)
    }
}
