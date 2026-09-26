import Foundation
import Security
import Darwin

/// Recognizes Claude Code builds whose credential-storage derivation matches the reviewed builds.
///
/// Claude Code updates itself often, so an exact binary pin would disable switching after almost every
/// update. Instead the installed executable must contain the reviewed derivation of the Keychain service,
/// account and override variables, with only minified identifiers allowed to differ. Any other change fails
/// closed until it is reviewed.
enum ClaudeStorageContract {
    private static let anchor = Data(#""-credentials";function "#.utf8)
    private static let template = #"<removed third-party source>"#
    private static let expression = try? NSRegularExpression(pattern: "\\A" + template
        .components(separatedBy: "§")
        .map(NSRegularExpression.escapedPattern(for:))
        .joined(separator: "[A-Za-z_$][A-Za-z0-9_$]*"))

    static func matches(_ data: Data) -> Bool {
        guard let expression, let first = data.range(of: anchor),
              data.range(of: anchor, in: first.upperBound..<data.endIndex) == nil else { return false }
        let window = String(decoding: data[first.lowerBound..<min(first.lowerBound + 4096, data.endIndex)], as: UTF8.self)
        return expression.firstMatch(in: window, range: NSRange(window.startIndex..., in: window)) != nil
    }

    static func matches(executableAt path: String) -> Bool {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .alwaysMapped) else { return false }
        return matches(data)
    }
}

/// Production wiring for the native-installer Claude Code: Keychain, `~/.claude.json` and process checks.
struct ClaudeLiveSystem {
    let home: String
    let environment: [String: String]
    let operatingSystemUser: String?
    let fileExists: (String) -> Bool
    let resolveExecutable: (String) -> String?
    let storageContractMatches: (String) -> Bool

    static var current: Self {
        .init(
            home: NSHomeDirectory(), environment: ProcessInfo.processInfo.environment,
            operatingSystemUser: NSUserName(), fileExists: { FileManager.default.fileExists(atPath: $0) },
            resolveExecutable: { path in
                guard let resolved = realpath(path, nil) else { return nil }
                defer { free(resolved) }
                return String(cString: resolved)
            },
            storageContractMatches: ClaudeStorageContract.matches(executableAt:)
        )
    }

    static func isEnabled(environment: [String: String]) -> Bool { environment["AI_CONTROL_CLAUDE_LIVE"] == "1" }

    static func configuredBackend(environment: [String: String]) -> (() -> any ClaudeLoginBackend)? {
        guard isEnabled(environment: environment), let executable = Bundle.main.executablePath else { return nil }
        let system = current
        return { system.makeBackend(managerExecutable: executable) }
    }

    var launcherPath: String { home + "/.local/bin/claude" }
    var versionsDirectory: String { home + "/.local/share/claude/versions" }
    var configurationPath: String { home + "/.claude.json" }
    var managerDirectory: String { home + "/Library/Application Support/AIControl" }

    func routingEvidence() -> ClaudeRoutingEvidence {
        let executable = resolveExecutable(launcherPath).flatMap { $0.hasPrefix(versionsDirectory + "/") ? $0 : nil }
        func isSet(_ names: String...) -> Bool { names.contains { environment[$0] != nil } }
        var conflicts: Set<ClaudeRoutingConflict> = []
        if isSet("CLAUDE_CONFIG_DIR") { conflicts.insert(.configurationOverride) }
        if isSet("CLAUDE_SECURESTORAGE_CONFIG_DIR") { conflicts.insert(.secureStorageOverride) }
        if isSet("CLAUDE_CODE_CUSTOM_OAUTH_URL", "CLAUDE_CODE_OAUTH_CLIENT_ID", "CLAUDE_LOCAL_OAUTH_API_BASE",
                 "CLAUDE_LOCAL_OAUTH_APPS_BASE", "CLAUDE_LOCAL_OAUTH_CONSOLE_BASE") {
            conflicts.insert(.customOAuth)
        }
        if isSet("ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "CLAUDE_CODE_OAUTH_TOKEN",
                 "CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX") {
            conflicts.insert(.alternateAuthentication)
        }
        if fileExists(home + "/.claude/.credentials.json") { conflicts.insert(.plaintextFallback) }
        if fileExists(home + "/.claude/.config.json") { conflicts.insert(.legacyStorage) }
        return .init(
            storageContractVerified: executable.map(storageContractMatches) ?? false,
            resolvedConfigurationPath: configurationPath, defaultConfigurationPath: configurationPath,
            environmentUser: environment["USER"], operatingSystemUser: operatingSystemUser, conflicts: conflicts
        )
    }

    func makeBackend(managerExecutable: String) -> any ClaudeLoginBackend {
        let preflight = ClaudeProcessPreflight(
            expectedUID: geteuid(), trustedExecutablePath: resolveExecutable(launcherPath) ?? launcherPath,
            probe: .system(), trustedExecutableDirectory: versionsDirectory, permitsOpenSessions: true
        )
        let custody = { (guardMutation: @escaping () throws -> Void) in
            ClaudeLoginCustody(store: try Self.managerStore(beforeMutation: guardMutation))
        }
        return CommandScopedClaudeLoginBackend(
            acquireLock: { [managerDirectory] in try ManagerFileLock.acquire(directory: managerDirectory) },
            routingEvidence: { routingEvidence() },
            readCustody: { try custody({}) },
            writeCustody: { _, guardMutation in try custody(guardMutation) },
            processPreflight: preflight,
            currentSnapshot: { route in
                let roots = try Self.resources(route).readRoots()
                return try ClaudeLoginSnapshot.capture(secureRoot: roots.secure, configurationRoot: roots.configuration)
            },
            selectionResources: Self.resources
        )
    }

    static func managerStore(beforeMutation: @escaping () throws -> Void) throws -> MigratingKeychainStore {
        let account = String(geteuid())
        let legacy = IsolatedKeychainAdapter(
            keychain: try defaultKeychain(), service: "AIControl-claude-logins.v1", account: account
        )
        return .init(
            primary: .init(service: "AIControl-claude-logins.v2", account: account, beforeMutation: beforeMutation),
            legacyRead: legacy.read, legacyDelete: legacy.delete
        )
    }

    static func resources(_ route: ClaudeStorageRoute) throws -> ClaudeLoginResourceIO {
        let item = SecurityToolKeychainItem(service: route.service, account: route.account)
        let file = ProtectedConfigurationFile(path: route.configurationPath)
        return .init(
            readRoots: {
                guard let secure = String(data: try item.read(), encoding: .utf8) else { throw IsolatedKeychainError.corrupt }
                return .init(secure: secure, configuration: try String(contentsOfFile: route.configurationPath, encoding: .utf8))
            },
            replaceSecure: { expected, replacement, guardMutation in
                try item.replace(expectedData: Data(expected.utf8), with: Data(replacement.utf8), guardedBy: guardMutation)
            },
            replaceConfiguration: { expected, replacement, guardMutation in
                try replaceConfiguration(file, expected: expected, replacement: replacement, guardedBy: guardMutation)
            }
        )
    }

    /// Rewrites only the owned configuration keys, refusing any replacement that edits anything else.
    static func replaceConfiguration(
        _ file: ProtectedConfigurationFile, expected: String, replacement: String,
        guardedBy guardMutation: () throws -> Void
    ) throws {
        let owned = try ClaudeLoginOwnedFields.capture(.init(secure: "{}", configuration: replacement)).configuration
        guard try ScopedJSON(expected).replacing(owned) == replacement else { throw ClaudeLoginSelectionError.changedRoots }
        try file.replace(expectedSource: expected, with: .init(changes: owned), guardedBy: guardMutation)
    }

    private static func defaultKeychain() throws -> SecKeychain {
        var keychain: SecKeychain?
        let status = SecKeychainCopyDefault(&keychain)
        guard status == errSecSuccess, let keychain else { throw IsolatedKeychainError.operatingSystem(status) }
        return keychain
    }
}

/// Reads and writes a generic-password item through `/usr/bin/security`, exactly as Claude Code does.
///
/// Using the same Apple tool leaves the item's access list and partitions untouched, so neither Claude Code
/// nor AI Control triggers Keychain prompts after a switch. Payloads go on stdin; like Claude Code, payloads
/// above the `security -i` line limit fall back to argv, which only same-user processes can read and which
/// could already read this item through the same tool.
struct SecurityToolKeychainItem: ClaudeLoginDataStore {
    typealias Runner = (_ arguments: [String], _ input: Data?) throws -> (status: Int32, output: Data)
    static let interactiveLimit = 4032

    let service: String
    let account: String
    var beforeMutation: () throws -> Void = {}
    var run: Runner = Self.runSecurity

    func read() throws -> Data {
        let result = try run(["find-generic-password", "-a", account, "-s", service, "-w"], nil)
        try Self.check(result.status)
        return try Self.decodePassword(result.output)
    }

    func create(data: Data) throws { try create(data: data, guardedBy: beforeMutation) }
    func update(data: Data) throws { try update(data: data, guardedBy: beforeMutation) }

    func create(data: Data, guardedBy guardMutation: () throws -> Void) throws {
        try guardMutation()
        try write(data, updating: false)
    }

    func update(data: Data, guardedBy guardMutation: () throws -> Void) throws {
        _ = try read()
        try guardMutation()
        try write(data, updating: true)
    }

    func replace(expectedData: Data, with data: Data, guardedBy guardMutation: () throws -> Void) throws {
        guard try read() == expectedData else { throw IsolatedKeychainError.corrupt }
        try guardMutation()
        try write(data, updating: true)
    }

    private func write(_ data: Data, updating: Bool) throws {
        let safe = #"^[A-Za-z0-9._ -]+$"#
        guard service.range(of: safe, options: .regularExpression) != nil,
              account.range(of: safe, options: .regularExpression) != nil else { throw IsolatedKeychainError.corrupt }
        let hex = data.map { String(format: "%02x", $0) }.joined()
        let update = updating ? ["-U"] : []
        let command = "add-generic-password \(updating ? "-U " : "")-a \"\(account)\" -s \"\(service)\" -X \"\(hex)\"\n"
        let result = command.utf8.count <= Self.interactiveLimit
            ? try run(["-i"], Data(command.utf8))
            : try run(["add-generic-password"] + update + ["-a", account, "-s", service, "-X", hex], nil)
        try Self.check(result.status)
    }

    private static func decodePassword(_ output: Data) throws -> Data {
        var text = String(decoding: output, as: UTF8.self)
        if text.hasSuffix("\n") { text.removeLast() }
        if text.hasPrefix("{") { return Data(text.utf8) }
        // `security -w` prints non-ASCII passwords as hex.
        guard text.count.isMultiple(of: 2), !text.isEmpty,
              text.allSatisfy(\.isHexDigit) else { throw IsolatedKeychainError.corrupt }
        var bytes = [UInt8]()
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2)
            guard let byte = UInt8(text[index..<next], radix: 16) else { throw IsolatedKeychainError.corrupt }
            bytes.append(byte)
            index = next
        }
        return Data(bytes)
    }

    private static func check(_ status: Int32) throws {
        switch status {
        case 0: return
        case 44: throw IsolatedKeychainError.missing
        case 45: throw IsolatedKeychainError.duplicate
        case 36: throw IsolatedKeychainError.locked
        case 51: throw IsolatedKeychainError.denied
        case 128: throw IsolatedKeychainError.cancelled
        default: throw IsolatedKeychainError.operatingSystem(OSStatus(status))
        }
    }

    static func runSecurity(_ arguments: [String], _ input: Data?) throws -> (status: Int32, output: Data) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments
        let standardInput = Pipe()
        let standardOutput = Pipe()
        process.standardInput = standardInput
        process.standardOutput = standardOutput
        process.standardError = FileHandle.nullDevice
        try process.run()
        if let input { standardInput.fileHandleForWriting.write(input) }
        try standardInput.fileHandleForWriting.close()
        let output = standardOutput.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, output)
    }
}

/// Manager state in a `security`-owned item, migrating the earlier AI Control-owned item on first write.
struct MigratingKeychainStore: ClaudeLoginDataStore {
    let primary: SecurityToolKeychainItem
    let legacyRead: () throws -> Data
    let legacyDelete: () throws -> Void

    func read() throws -> Data {
        do { return try primary.read() } catch IsolatedKeychainError.missing { return try legacyRead() }
    }

    func create(data: Data) throws { try primary.create(data: data) }
    func update(data: Data) throws { try update(data: data, guardedBy: primary.beforeMutation) }
    func create(data: Data, guardedBy guardMutation: () throws -> Void) throws {
        try primary.create(data: data, guardedBy: guardMutation)
    }

    func update(data: Data, guardedBy guardMutation: () throws -> Void) throws {
        do {
            _ = try primary.read()
        } catch IsolatedKeychainError.missing {
            _ = try legacyRead()
            try primary.create(data: data, guardedBy: guardMutation)
            try? legacyDelete()
            return
        }
        try primary.update(data: data, guardedBy: guardMutation)
    }
}
