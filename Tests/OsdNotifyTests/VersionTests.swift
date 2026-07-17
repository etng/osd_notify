import Foundation
import XCTest
@testable import OsdNotify

final class VersionTests: XCTestCase {
    func testParsesStableAndPrereleaseVersions() {
        XCTAssertEqual(SemanticVersion("v1.2.3")?.description, "1.2.3")
        XCTAssertEqual(SemanticVersion("2.0.0-rc.1+build.9")?.description, "2.0.0-rc.1")
    }

    func testRejectsInvalidVersions() {
        XCTAssertNil(SemanticVersion("1.2"))
        XCTAssertNil(SemanticVersion("01.2.3"))
        XCTAssertNil(SemanticVersion("1.2.3-rc.01"))
    }

    func testComparesSemVerPrecedence() throws {
        let prerelease = try XCTUnwrap(SemanticVersion("1.0.0-rc.1"))
        let stable = try XCTUnwrap(SemanticVersion("1.0.0"))
        let nextPatch = try XCTUnwrap(SemanticVersion("1.0.1"))

        XCTAssertLessThan(prerelease, stable)
        XCTAssertLessThan(stable, nextPatch)
    }

    func testDecodesGitHubReleaseMetadata() throws {
        let release = try decodeGitHubRelease(Data(#"{"tagName":"v1.2.3","url":"https://example.com/release"}"#.utf8))

        XCTAssertEqual(release.tagName, "v1.2.3")
        XCTAssertEqual(release.url, "https://example.com/release")
    }
}
