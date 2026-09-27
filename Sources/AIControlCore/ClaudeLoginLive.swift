#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Security)
import Security
#endif
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Recognizes Claude Code builds whose credential-storage derivation matches the reviewed builds.
///
/// Claude Code updates itself often, so an exact binary pin would disable switching after almost every
/// update. Instead the installed executable must contain the reviewed derivation of the Keychain service,
/// account and override variables. Only a SHA-256 digest of that derivation is kept here, taken after
/// short minified names are normalized away, so builds that differ only in those names still match and
/// any other change fails closed until it is reviewed.
enum ClaudeStorageContract {
    /// Digest of the derivation in reviewed Claude Code builds 2.1.280, 2.1.282 and 2.1.283.
    static let reviewedDigest = "022930836e5b0072c994be8a2be4bebcf17aaba9663b92618989576a2ccf768c"

    private static let anchor = Data(#""-credentials";function "#.utf8)
    private static let end = #""claude-code-user";return §}"#
    private static let keptWords: Set<String> = ["let", "var", "if", "try", "new", "void", "test", "env", "USER"]

    static func matches(_ data: Data, digest: String = reviewedDigest) -> Bool { self.digest(in: data) == digest }

    static func matches(executableAt path: String) -> Bool {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .alwaysMapped) else { return false }
        return matches(data)
    }

    /// The digest of the single derivation in an executable, or nil when it is missing or repeated.
    static func digest(in data: Data) -> String? {
        guard let first = data.range(of: anchor),
              data.range(of: anchor, in: first.upperBound..<data.endIndex) == nil else { return nil }
        return digest(of: String(decoding: data[first.lowerBound..<min(first.lowerBound + 4096, data.endIndex)], as: UTF8.self))
    }

    static func digest(of source: String) -> String? {
        guard let normalized = normalized(source, stoppingAfter: end) else { return nil }
        return SHA256.hash(data: Data(normalized.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Replaces identifiers of up to four characters with `§` outside string and template text,
    /// keeping keywords and the names the derivation depends on. With `stoppingAfter`, returns the
    /// normalized prefix ending with that text, or nil when it never appears.
    static func normalized(_ source: String, stoppingAfter terminator: String? = nil) -> String? {
        var output = ""
        var index = source.startIndex
        var quote: Character?
        var templateDepths: [Int] = []
        var braceDepth = 0
        while index < source.endIndex {
            let character = source[index]
            if let open = quote {
                output.append(character)
                if character == "\\" {
                    index = source.index(after: index)
                    if index < source.endIndex { output.append(source[index]) }
                } else if open == "`" && character == "$", source[source.index(after: index)...].first == "{" {
                    index = source.index(after: index)
                    output.append("{")
                    templateDepths.append(braceDepth)
                    quote = nil
                } else if character == open {
                    quote = nil
                }
                index = source.index(after: index)
                continue
            }
            if character == "\"" || character == "'" || character == "`" {
                quote = character
                output.append(character)
            } else if character == "{" {
                braceDepth += 1
                output.append(character)
            } else if character == "}" {
                output.append(character)
                if templateDepths.last == braceDepth {
                    templateDepths.removeLast()
                    quote = "`"
                } else {
                    braceDepth -= 1
                }
            } else if character.isLetter || character == "_" || character == "$" {
                var end = index
                while end < source.endIndex, source[end].isLetter || source[end].isNumber || source[end] == "_" || source[end] == "$" {
                    end = source.index(after: end)
                }
                let word = String(source[index..<end])
                output += word.count <= 4 && !keptWords.contains(word) ? "§" : word
                index = end
                continue
            } else {
                output.append(character)
            }
            index = source.index(after: index)
            if let terminator, quote == nil, output.hasSuffix(terminator) { return output }
        }
        return quote == nil && terminator == nil ? output : nil
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

    /// Live switching is on for the installed macOS app and on Linux; macOS development builds need `aic`
    /// to ask for it. `AI_CONTROL_CLAUDE_LIVE=0` turns it off everywhere.
    static func isEnabled(environment: [String: String], bundlePath: String = Bundle.main.bundlePath) -> Bool {
        switch environment["AI_CONTROL_CLAUDE_LIVE"] {
        case "1": return true
        case "0": return false
        default:
            #if os(macOS)
            return bundlePath.hasSuffix(".app")
            #else
            return true
            #endif
        }
    }

    static func configuredBackend(environment: [String: String]) -> (() -> any ClaudeLoginBackend)? {
        guard isEnabled(environment: environment), let executable = Bundle.main.executablePath else { return nil }
        let system = current
        return { system.makeBackend(managerExecutable: executable) }
    }

    var launcherPath: String { home + "/.local/bin/claude" }
    var versionsDirectory: String { home + "/.local/share/claude/versions" }
    var configurationPath: String { home + "/.claude.json" }
    var managerDirectory: String { Self.dataDirectory(home: home, environment: environment) }
    /// Claude Code keeps its Linux login in this file; on macOS it uses the Keychain instead.
    var credentialsPath: String { home + "/.claude/.credentials.json" }

    /// Where AI Control keeps its lock and, on Linux, its saved logins.
    static func dataDirectory(home: String, environment: [String: String]) -> String {
        #if os(macOS)
        return home + "/Library/Application Support/AIControl"
        #else
        return (environment["XDG_DATA_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? home + "/.local/share") + "/ai-control"
        #endif
    }

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
        #if os(macOS)
        // On macOS a credentials file means Claude fell back from the Keychain; on Linux it is the only store.
        if fileExists(credentialsPath) { conflicts.insert(.plaintextFallback) }
        #endif
        if fileExists(home + "/.claude/.config.json") { conflicts.insert(.legacyStorage) }
        return .init(
            storageContractVerified: executable.map(storageContractMatches) ?? false,
            resolvedConfigurationPath: configurationPath, defaultConfigurationPath: configurationPath,
            environmentUser: environment["USER"], operatingSystemUser: operatingSystemUser, conflicts: conflicts
        )
    }

    func makeBackend(managerExecutable: String) -> any ClaudeLoginBackend {
        // Open sessions are allowed, so the process scan never decides anything; Linux has no scan at all.
        #if os(macOS)
        let probe = NativeProcessProbe.system()
        #else
        let probe = NativeProcessProbe(snapshot: { [] })
        #endif
        let preflight = ClaudeProcessPreflight(
            expectedUID: geteuid(), trustedExecutablePath: resolveExecutable(launcherPath) ?? launcherPath,
            probe: probe, trustedExecutableDirectory: versionsDirectory, permitsOpenSessions: true
        )
        let savedLogins = managerDirectory + "/claude-logins.json"
        let custody = { (guardMutation: @escaping () throws -> Void) -> ClaudeLoginCustody in
            #if os(macOS)
            return ClaudeLoginCustody(store: try Self.managerStore(beforeMutation: guardMutation))
            #else
            return ClaudeLoginCustody(store: ProtectedFileStore(path: savedLogins, beforeMutation: guardMutation))
            #endif
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

    #if os(macOS)
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

    #endif

    static func resources(_ route: ClaudeStorageRoute) throws -> ClaudeLoginResourceIO {
        #if os(macOS)
        let item = SecurityToolKeychainItem(service: route.service, account: route.account)
        #else
        let home = (route.configurationPath as NSString).deletingLastPathComponent
        let item = ProtectedFileStore(path: home + "/.claude/.credentials.json")
        #endif
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

    #if os(macOS)
    private static func defaultKeychain() throws -> SecKeychain {
        var keychain: SecKeychain?
        let status = SecKeychainCopyDefault(&keychain)
        guard status == errSecSuccess, let keychain else { throw IsolatedKeychainError.operatingSystem(status) }
        return keychain
    }
    #endif
}

#if os(macOS)
/// Reads and writes a generic-password item through `/usr/bin/security`, exactly as Claude Code does.
///
/// Using the same Apple tool leaves the item's access list and partitions untouched, so neither Claude Code
/// nor AI Control triggers Keychain prompts after a switch. Payloads go on stdin; like Claude Code, payloads
/// above the `security -i` line limit fall back to argv, which only same-user processes can read and which
/// could already read this item through the same tool.
struct SecurityToolKeychainItem: ClaudeLoginDataStore, IsolatedCredentialItem {
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

    func delete() throws {
        try Self.check(try run(["delete-generic-password", "-a", account, "-s", service], nil).status)
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

#endif

/// Runs a program to completion with its output discarded; stops it after `timeout` seconds.
func runProcess(
    _ executable: String, _ arguments: [String], environment: [String: String]? = nil,
    directory: String? = nil, timeout: TimeInterval
) throws -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    if let environment { process.environment = environment }
    if let directory { process.currentDirectoryURL = URL(fileURLWithPath: directory) }
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    let finished = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in finished.signal() }
    try process.run()
    if finished.wait(timeout: .now() + timeout) == .timedOut {
        process.terminate()
        finished.wait()
        return -1
    }
    return process.terminationStatus
}

/// Fetches a usage endpoint, accepting only a successful response.
func fetchUsage(_ request: URLRequest) async throws -> Data {
    let (data, response) = try await URLSession.shared.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw LoginUsage.Error.unreadable }
    return data
}

extension ClaudeAppServices {
    static func live(_ system: ClaudeLiveSystem) -> Self {
        let claude = system.resolveExecutable(system.launcherPath) ?? system.launcherPath
        let route = { try ClaudeRoutingValidator.route(system.routingEvidence()) }
        return .init(
            liveSnapshot: {
                let roots = try ClaudeLiveSystem.resources(try route()).readRoots()
                return try ClaudeLoginSnapshot.capture(secureRoot: roots.secure, configurationRoot: roots.configuration)
            },
            renew: { snapshot in
                let account = try route().account
                return try ClaudeIsolatedRenewal(
                    claudeExecutable: claude, keychainAccount: account,
                    item: { service, directory in
                        #if os(macOS)
                        return SecurityToolKeychainItem(service: service, account: account)
                        #else
                        return ProtectedFileStore(path: directory + "/.credentials.json")
                        #endif
                    },
                    run: { try runProcess($0, $1, environment: $2, directory: $3, timeout: 120) }
                ).renew(snapshot)
            },
            fetch: fetchUsage,
            signIn: { email in
                let arguments = ["auth", "login", "--claudeai"] + (email.map { ["--email", $0] } ?? [])
                guard try runProcess(claude, arguments, timeout: 600) == 0 else { throw LoginUsage.Error.unreadable }
            }
        )
    }
}

extension CodexAppServices {
    static var live: Self {
        let codex: () throws -> String = {
            let home = NSHomeDirectory()
            guard let path = ExecutableLookup.first(
                named: "codex", path: ProcessInfo.processInfo.environment["PATH"] ?? "",
                extraDirectories: [home + "/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"],
                isExecutable: FileManager.default.isExecutableFile(atPath:),
                resolve: { candidate in
                    guard let resolved = realpath(candidate, nil) else { return nil }
                    defer { free(resolved) }
                    return String(cString: resolved)
                },
                windowsMounts: {
                    #if os(Linux)
                    return ExecutableLookup.windowsMounts(
                        fromMountTable: (try? String(contentsOfFile: "/proc/self/mounts", encoding: .utf8)) ?? "")
                    #else
                    return []
                    #endif
                }()
            ) else {
                throw NativeCodexRequired.missing
            }
            return path
        }
        return .init(
            fetch: fetchUsage,
            signIn: { guard try runProcess(try codex(), ["login"], timeout: 600) == 0 else { throw LoginUsage.Error.unreadable } },
            renew: { login in
                try CodexIsolatedRenewal(
                    codexExecutable: try codex(),
                    run: { try runProcess($0, $1, environment: $2, directory: $3, timeout: 120) }
                ).renew(login)
            }
        )
    }
}
