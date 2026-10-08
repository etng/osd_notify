import AppKit
import Darwin

func configuredSourceNameFromEnvironment() -> String? {
    let environment = ProcessInfo.processInfo.environment
    for key in ["OSD_NOTIFY_SOURCE", "CODEX_OSD_SOURCE"] {
        if let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            return value
        }
    }
    return nil
}

func sourceWasConfiguredByEnvironment() -> Bool {
    configuredSourceNameFromEnvironment() != nil
}

func inferredSourceName() -> String {
    if let configuredSource = configuredSourceNameFromEnvironment() {
        return configuredSource
    }

    var nameBuffer = [CChar](repeating: 0, count: 1024)
    let length = proc_name(getppid(), &nameBuffer, UInt32(nameBuffer.count))
    if length > 0 {
        let name = String(decoding: nameBuffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            return name
        }
    }

    return "default"
}

func parentApplicationDisplayName() -> String? {
    applicationDisplayName(for: getppid())
}

func applicationDisplayName(for pid: pid_t) -> String? {
    guard pid > 1,
          let application = NSRunningApplication(processIdentifier: pid) else {
        return nil
    }

    if let localizedName = cleanedDisplayName(application.localizedName),
       !isNonApplicationSourceName(localizedName) {
        return localizedName
    }

    if let bundleURL = application.bundleURL,
       let bundleName = bundleDisplayName(at: bundleURL) {
        return bundleName
    }

    return nil
}

func bundleDisplayName(at url: URL) -> String? {
    guard let bundle = Bundle(url: url) else {
        return cleanedDisplayName(url.deletingPathExtension().lastPathComponent)
    }

    for key in ["CFBundleDisplayName", "CFBundleName"] {
        if let value = bundle.object(forInfoDictionaryKey: key) as? String,
           let displayName = cleanedDisplayName(value),
           !isNonApplicationSourceName(displayName) {
            return displayName
        }
    }

    return cleanedDisplayName(url.deletingPathExtension().lastPathComponent)
}

func cleanedDisplayName(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
          !trimmed.isEmpty else {
        return nil
    }
    return trimmed
}

func safeSourceName(_ source: String) -> String {
    let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
    let sanitized = source.map { allowed.contains($0) ? $0 : "_" }
    var name = String(sanitized).trimmingCharacters(in: CharacterSet(charactersIn: "._-"))
    if name.isEmpty {
        name = "source"
    }

    if name == source {
        return String(name.prefix(80))
    }

    return "\(String(name.prefix(48)))-\(stableSourceHash(source))"
}

func stableSourceHash(_ source: String) -> String {
    var hash: UInt64 = 0xcbf29ce484222325
    for byte in source.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 0x100000001b3
    }
    return String(hash, radix: 16)
}

func displayTitle(for options: Options) -> String {
    if let titleOverride = cleanedDisplayName(options.titleOverride) {
        return titleOverride
    }

    if options.sourceWasProvidedByCaller {
        return sourceDisplayName(options.source) ?? options.parentApplicationName ?? options.level.title
    }

    return options.parentApplicationName ?? sourceDisplayName(options.source) ?? options.level.title
}

func isNonApplicationSourceName(_ source: String) -> Bool {
    let lowercased = source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let nonApplicationSources: Set<String> = [
        "default",
        "unknown",
        "osd-notify",
        "swift",
        "zsh",
        "bash",
        "sh",
        "fish",
        "env",
        "make",
        "login"
    ]
    return nonApplicationSources.contains(lowercased)
}

func sourceDisplayName(_ source: String) -> String? {
    let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return nil
    }

    let lowercased = trimmed.lowercased()
    guard !isNonApplicationSourceName(trimmed) else {
        return nil
    }

    let knownNames: [String: String] = [
        "browser": "Browser",
        "chrome": "Chrome",
        "codex": "Codex",
        "com.google.chrome": "Google Chrome",
        "computer-use": "Computer Use",
        "computer use": "Computer Use",
        "github-desktop": "GitHub Desktop",
        "github desktop": "GitHub Desktop",
        "google chrome": "Google Chrome",
        "playwright": "Playwright"
    ]
    if let knownName = knownNames[lowercased] {
        return knownName
    }

    let pathName = (trimmed as NSString).lastPathComponent
    let appName = pathName.hasSuffix(".app") ? String(pathName.dropLast(4)) : pathName
    let separated = appName
        .replacingOccurrences(of: "_", with: " ")
        .replacingOccurrences(of: "-", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !separated.isEmpty else {
        return nil
    }

    if separated == separated.uppercased() {
        return separated
    }

    if separated.rangeOfCharacter(from: .uppercaseLetters) != nil {
        return separated
    }

    return separated
        .split(separator: " ")
        .map { word in
            let lower = word.lowercased()
            return lower.prefix(1).uppercased() + String(lower.dropFirst())
        }
        .joined(separator: " ")
}
