import Foundation

struct SemanticVersion: Comparable, CustomStringConvertible, Equatable {
    let major: Int
    let minor: Int
    let patch: Int
    let prereleaseIdentifiers: [String]

    init?(_ rawValue: String) {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("v") {
            value.removeFirst()
        }

        let buildParts = value.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)
        guard !buildParts[0].isEmpty else {
            return nil
        }

        let releaseParts = buildParts[0].split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let coreParts = releaseParts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard coreParts.count == 3,
              let major = Int(coreParts[0]),
              let minor = Int(coreParts[1]),
              let patch = Int(coreParts[2]),
              major >= 0,
              minor >= 0,
              patch >= 0 else {
            return nil
        }

        if coreParts.contains(where: { $0.count > 1 && $0.hasPrefix("0") }) {
            return nil
        }

        let prereleaseIdentifiers: [String]
        if releaseParts.count == 2 {
            prereleaseIdentifiers = releaseParts[1].split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            guard !prereleaseIdentifiers.isEmpty,
                  prereleaseIdentifiers.allSatisfy({ identifier in
                      !identifier.isEmpty && identifier.allSatisfy { character in
                          character.isLetter || character.isNumber || character == "-"
                      }
                  }),
                  prereleaseIdentifiers.allSatisfy({ identifier in
                      !identifier.allSatisfy(\.isNumber) || identifier == "0" || !identifier.hasPrefix("0")
                  }) else {
                return nil
            }
        } else {
            prereleaseIdentifiers = []
        }

        self.major = major
        self.minor = minor
        self.patch = patch
        self.prereleaseIdentifiers = prereleaseIdentifiers
    }

    var description: String {
        let core = "\(major).\(minor).\(patch)"
        guard !prereleaseIdentifiers.isEmpty else {
            return core
        }
        return "\(core)-\(prereleaseIdentifiers.joined(separator: "."))"
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let lhsCore = [lhs.major, lhs.minor, lhs.patch]
        let rhsCore = [rhs.major, rhs.minor, rhs.patch]
        if lhsCore != rhsCore {
            return lhsCore.lexicographicallyPrecedes(rhsCore)
        }

        if lhs.prereleaseIdentifiers.isEmpty {
            return false
        }
        if rhs.prereleaseIdentifiers.isEmpty {
            return true
        }

        for (lhsIdentifier, rhsIdentifier) in zip(lhs.prereleaseIdentifiers, rhs.prereleaseIdentifiers) {
            if lhsIdentifier == rhsIdentifier {
                continue
            }

            let lhsNumber = Int(lhsIdentifier)
            let rhsNumber = Int(rhsIdentifier)
            switch (lhsNumber, rhsNumber) {
            case let (.some(lhsValue), .some(rhsValue)):
                return lhsValue < rhsValue
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return lhsIdentifier < rhsIdentifier
            }
        }

        return lhs.prereleaseIdentifiers.count < rhs.prereleaseIdentifiers.count
    }
}

enum AppVersion {
    static let currentString = "1.0.0"
    static let current = SemanticVersion(currentString)!
    static let repository = "etng/osd_notify"
}

struct GitHubRelease: Decodable {
    let tagName: String
    let url: String
}

func decodeGitHubRelease(_ data: Data) throws -> GitHubRelease {
    try JSONDecoder().decode(GitHubRelease.self, from: data)
}

func fetchLatestGitHubRelease() throws -> GitHubRelease {
    guard let ghExecutable = findExecutable("gh") else {
        throw CLIError.message("检查更新需要 GitHub CLI。请先安装 gh 并登录后重试。")
    }

    let result = try runCapturedProcess(
        executable: ghExecutable,
        arguments: [
            "release",
            "view",
            "--repo",
            AppVersion.repository,
            "--json",
            "tagName,url"
        ]
    )

    guard result.status == 0 else {
        let reason = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        throw CLIError.message(reason.isEmpty
            ? "无法读取最新版本。请确认 gh 已登录且有权访问仓库。"
            : "无法读取最新版本：\(reason)")
    }

    return try decodeGitHubRelease(Data(result.stdout.utf8))
}

func printVersion() {
    print("osd-notify \(AppVersion.currentString)")
}

func checkForUpdates() throws {
    let release = try fetchLatestGitHubRelease()
    guard let latestVersion = SemanticVersion(release.tagName) else {
        throw CLIError.message("最新 Release 的标签不是有效的 SemVer：\(release.tagName)")
    }

    if AppVersion.current < latestVersion {
        print("发现新版本 \(latestVersion)（当前版本 \(AppVersion.current)）。")
        print(release.url)
    } else if latestVersion < AppVersion.current {
        print("当前版本 \(AppVersion.current) 比最新发布版本 \(latestVersion) 更新。")
    } else {
        print("当前已是最新版本 \(AppVersion.current)。")
    }
}
