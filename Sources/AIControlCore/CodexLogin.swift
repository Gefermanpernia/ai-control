import Foundation
import Darwin

struct CodexLoginIdentity: Equatable, Sendable {
    let accountID: String
    let email: String?
}

enum CodexLoginError: Error, Equatable {
    case unsupportedAuth, noLiveLogin, unknownAlias, unsavedLiveLogin, alreadySaved(String), aliasTaken
    case tooMany, keyringStorage, changedDuringSwitch, readbackMismatch, writeFailed

    /// `name` is the alias the command targeted; `liveEmail` names the account in auth.json.
    func message(name: String, liveEmail: String?) -> String {
        switch self {
        case .unsupportedAuth: return "Blocked: only ChatGPT sign-in Codex logins can be saved or switched."
        case .noLiveLogin: return "Blocked: Codex is not signed in; run codex login first."
        case .unknownAlias: return "Blocked: no Codex login is saved as \(name)."
        case .unsavedLiveLogin:
            return "Blocked: the current Codex login (\(liveEmail ?? "unknown email")) is not saved; save it first."
        case .alreadySaved(let alias): return "Blocked: this Codex login is already saved as \(alias)."
        case .aliasTaken: return "Blocked: \(name) belongs to another Codex account."
        case .tooMany: return "Blocked: \(ClaudeLoginEnvelopeCodec.maxAliases) Codex logins are already saved."
        case .keyringStorage: return "Blocked: Codex keeps its login in the Keychain; only auth.json logins can be switched."
        case .changedDuringSwitch: return "Blocked: Codex changed its login during the switch; try again."
        case .readbackMismatch, .writeFailed: return "Blocked: the Codex login could not be written; check ~/.codex/auth.json."
        }
    }
}

/// Codex CLI's `auth.json` for ChatGPT sign-in. The account is identified offline from the file itself,
/// so AI Control never has to guess which saved login is live.
enum CodexAuthFile {
    static func identity(_ data: Data) throws -> CodexLoginIdentity {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["auth_mode"] as? String == "chatgpt",
              let tokens = root["tokens"] as? [String: Any],
              let accountID = tokens["account_id"] as? String, !accountID.isEmpty,
              let refresh = tokens["refresh_token"] as? String, !refresh.isEmpty,
              let idToken = tokens["id_token"] as? String else { throw CodexLoginError.unsupportedAuth }
        return .init(accountID: accountID, email: email(fromIDToken: idToken))
    }

    private static func email(fromIDToken token: String) -> String? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var payload = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return claims["email"] as? String
    }

    /// Replaces `auth.json` in one rename, only if it still holds `expected`, keeping owner-only access.
    static func replace(path: String, expected: Data?, with data: Data) throws {
        guard FileManager.default.contents(atPath: path) == expected else { throw CodexLoginError.changedDuringSwitch }
        let temporary = (path as NSString).deletingLastPathComponent + "/.auth.json.aicontrol-" + UUID().uuidString
        let descriptor = open(temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw CodexLoginError.writeFailed }
        var renamed = false
        defer { if !renamed { unlink(temporary) } }
        let written = data.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
        let synced = fsync(descriptor) == 0
        close(descriptor)
        guard written == data.count, synced, rename(temporary, path) == 0 else { throw CodexLoginError.writeFailed }
        renamed = true
    }
}

struct CodexLoginSystem {
    let authPath: String
    let store: any ClaudeLoginDataStore
    let acquireLock: () throws -> ManagerFileLock
    let keyringHoldsLogin: () -> Bool
    var beforeReplace: () -> Void = {}

    static var current: Self {
        let home = ProcessInfo.processInfo.environment["CODEX_HOME"] ?? NSHomeDirectory() + "/.codex"
        return .init(
            authPath: home + "/auth.json",
            store: SecurityToolKeychainItem(service: "AIControl-codex-logins.v1", account: String(geteuid())),
            acquireLock: { try ManagerFileLock.acquire(directory: NSHomeDirectory() + "/Library/Application Support/AIControl/codex") },
            keyringHoldsLogin: {
                (try? SecurityToolKeychainItem.runSecurity(["find-generic-password", "-s", "Codex Auth"], nil))?.status == 0
            }
        )
    }
}

/// Saved Codex logins, keyed by alias, each an exact copy of `auth.json`.
struct CodexLoginState: Codable, Equatable {
    var version = 1
    var logins: [String: Data] = [:]
}

struct CodexLoginManager {
    let system: CodexLoginSystem

    func list() throws -> (logins: [(alias: String, email: String?)], live: String?) {
        let state = try load()
        let liveIdentity = system.liveData().flatMap { try? CodexAuthFile.identity($0) }
        let logins = state.logins.sorted { $0.key < $1.key }.map { entry -> (alias: String, email: String?) in
            (entry.key, (try? CodexAuthFile.identity(entry.value))?.email)
        }
        return (logins, liveIdentity.flatMap { alias(for: $0, in: state) })
    }

    func save(_ alias: String) throws -> CodexLoginIdentity {
        let lock = try system.acquireLock()
        defer { lock.release() }
        guard let live = system.liveData() else { throw CodexLoginError.noLiveLogin }
        let identity = try CodexAuthFile.identity(live)
        var state = try load()
        if let saved = state.logins[alias], try CodexAuthFile.identity(saved).accountID != identity.accountID {
            throw CodexLoginError.aliasTaken
        }
        if let existing = self.alias(for: identity, in: state), existing != alias { throw CodexLoginError.alreadySaved(existing) }
        guard state.logins[alias] != nil || state.logins.count < ClaudeLoginEnvelopeCodec.maxAliases else {
            throw CodexLoginError.tooMany
        }
        state.logins[alias] = live
        try persist(state)
        return identity
    }

    func use(_ alias: String) throws {
        let lock = try system.acquireLock()
        defer { lock.release() }
        guard !system.keyringHoldsLogin() else { throw CodexLoginError.keyringStorage }
        var state = try load()
        guard let target = state.logins[alias] else { throw CodexLoginError.unknownAlias }
        _ = try CodexAuthFile.identity(target)
        let live = system.liveData()
        if let live {
            // Keep the outgoing account's latest refresh token: Codex rotates it on every refresh.
            guard let source = self.alias(for: try CodexAuthFile.identity(live), in: state) else {
                throw CodexLoginError.unsavedLiveLogin
            }
            if state.logins[source] != live {
                state.logins[source] = live
                try persist(state)
            }
        }
        guard live != state.logins[alias] else { return }
        system.beforeReplace()
        try CodexAuthFile.replace(path: system.authPath, expected: live, with: target)
        guard system.liveData() == target else { throw CodexLoginError.readbackMismatch }
    }

    /// `codex login` revokes whatever login auth.json holds, so re-save it and move it out of the way first.
    /// Returns the alias that holds the detached login, or nil when Codex was not signed in.
    func prepareLogin() throws -> String? {
        let lock = try system.acquireLock()
        defer { lock.release() }
        guard let live = system.liveData() else { return nil }
        var state = try load()
        guard let source = alias(for: try CodexAuthFile.identity(live), in: state) else {
            throw CodexLoginError.unsavedLiveLogin
        }
        if state.logins[source] != live {
            state.logins[source] = live
            try persist(state)
        }
        guard system.liveData() == live else { throw CodexLoginError.changedDuringSwitch }
        guard unlink(system.authPath) == 0 else { throw CodexLoginError.writeFailed }
        return source
    }

    func rename(_ alias: String, to newAlias: String) throws {
        let lock = try system.acquireLock()
        defer { lock.release() }
        var state = try load()
        guard state.logins[newAlias] == nil else { throw CodexLoginError.aliasTaken }
        guard let login = state.logins.removeValue(forKey: alias) else { throw CodexLoginError.unknownAlias }
        state.logins[newAlias] = login
        try persist(state)
    }

    func liveIdentity() -> CodexLoginIdentity? { system.liveData().flatMap { try? CodexAuthFile.identity($0) } }

    private func alias(for identity: CodexLoginIdentity, in state: CodexLoginState) -> String? {
        state.logins.first { (try? CodexAuthFile.identity($0.value))?.accountID == identity.accountID }?.key
    }

    private func load() throws -> CodexLoginState {
        do { return try JSONDecoder().decode(CodexLoginState.self, from: system.store.read()) }
        catch IsolatedKeychainError.missing { return .init() }
    }

    private func persist(_ state: CodexLoginState) throws {
        let data = try JSONEncoder().encode(state)
        do {
            _ = try system.store.read()
            try system.store.update(data: data)
        } catch IsolatedKeychainError.missing {
            try system.store.create(data: data)
        }
        guard try system.store.read() == data else { throw CodexLoginError.readbackMismatch }
    }
}

private extension CodexLoginSystem {
    func liveData() -> Data? { FileManager.default.contents(atPath: authPath) }
}

func runCodexLogins(arguments: [String], system: CodexLoginSystem = .current, output: (String) -> Void) -> Int32 {
    let usage = "Usage: AIControl codex-login save <alias> | list | use <alias> | rename <alias> <new-alias>"
    let valid = { (alias: String) in alias.range(of: #"^[a-z][a-z0-9_-]{0,31}$"#, options: .regularExpression) != nil }
    let manager = CodexLoginManager(system: system)
    let command = Array(arguments.dropFirst())
    do {
        switch command.first {
        case "list" where command.count == 1:
            let listing = try manager.list()
            if listing.logins.isEmpty { output("No saved Codex logins.") }
            for login in listing.logins {
                output("\(login.alias): \(login.email ?? "unknown email")\(listing.live == login.alias ? " (in use)" : "")")
            }
        case "save" where command.count == 2 && valid(command[1]):
            let identity = try manager.save(command[1])
            output("Saved Codex login \(command[1]) (\(identity.email ?? "unknown email")).")
        case "use" where command.count == 2 && valid(command[1]):
            try manager.use(command[1])
            output("Switched Codex to \(command[1]).")
        case "prepare-login" where command.count == 1:
            if let alias = try manager.prepareLogin() {
                output("Saved \(alias); auth.json cleared for codex login.")
            } else {
                output("No Codex login to clear.")
            }
        case "rename" where command.count == 3 && valid(command[1]) && valid(command[2]):
            try manager.rename(command[1], to: command[2])
            output("Renamed Codex login \(command[1]) to \(command[2]).")
        default:
            output(usage)
            return 2
        }
        return 0
    } catch let error as CodexLoginError {
        let name = error == .aliasTaken ? command.last : (command.count > 1 ? command[1] : nil)
        output(error.message(name: name ?? "that name", liveEmail: manager.liveIdentity()?.email))
        return 3
    } catch {
        output("Blocked: saved Codex logins are unavailable.")
        if ProcessInfo.processInfo.environment["AI_CONTROL_DEBUG"] == "1" { output("Debug: \(String(reflecting: error))") }
        return 3
    }
}

struct CodexLoginListing: Equatable, Sendable {
    struct Login: Equatable, Sendable {
        let name: String
        let email: String?
    }

    let logins: [Login]
    let inUse: String?
}

enum CodexLoginAppResult: Equatable, Sendable {
    case listed(CodexLoginListing)
    case switched(String)
    case blocked(String)
    case unavailable
}

/// Serializes Codex login commands off the main actor; unavailable unless live switching is enabled.
actor CodexLoginAppAdapter {
    private let makeSystem: (() -> CodexLoginSystem)?

    init() { makeSystem = nil }
    init(makeSystem: @escaping () -> CodexLoginSystem) { self.makeSystem = makeSystem }

    static func configured(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> CodexLoginAppAdapter {
        ClaudeLiveSystem.isEnabled(environment: environment) ? .init(makeSystem: { .current }) : .init()
    }

    func list() -> CodexLoginAppResult {
        guard let manager else { return .unavailable }
        guard let listing = try? manager.list() else { return .blocked("Saved Codex logins could not be read.") }
        return .listed(.init(logins: listing.logins.map { .init(name: $0.alias, email: $0.email) }, inUse: listing.live))
    }

    func use(alias: String) -> CodexLoginAppResult {
        guard let manager else { return .unavailable }
        do {
            try manager.use(alias)
            return .switched(alias)
        } catch let error as CodexLoginError {
            return .blocked(error.message(name: alias, liveEmail: manager.liveIdentity()?.email))
        } catch {
            return .blocked("Blocked: saved Codex logins are unavailable.")
        }
    }

    private var manager: CodexLoginManager? { makeSystem.map { CodexLoginManager(system: $0()) } }
}
