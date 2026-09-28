import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

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
        let environment = ProcessInfo.processInfo.environment
        let home = environment["CODEX_HOME"] ?? NSHomeDirectory() + "/.codex"
        let data = ClaudeLiveSystem.dataDirectory(home: NSHomeDirectory(), environment: environment)
        #if os(macOS)
        let store: any ClaudeLoginDataStore = SecurityToolKeychainItem(service: "AIControl-codex-logins.v1", account: String(geteuid()))
        let keyringHoldsLogin = {
            (try? SecurityToolKeychainItem.runSecurity(["find-generic-password", "-s", "Codex Auth"], nil))?.status == 0
        }
        #else
        let store: any ClaudeLoginDataStore = ProtectedFileStore(path: data + "/codex-logins.json")
        // Codex on Linux defaults to auth.json; a Secret Service login is not detected here.
        let keyringHoldsLogin = { false }
        #endif
        return .init(
            authPath: home + "/auth.json", store: store,
            acquireLock: { try ManagerFileLock.acquire(directory: data + "/codex") },
            keyringHoldsLogin: keyringHoldsLogin
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

    func savedLogins() throws -> [String: Data] { try load().logins }

    /// Saves a renewed copy of a saved login, only if it still belongs to the same account.
    func replaceSaved(_ alias: String, with login: Data) throws {
        let lock = try system.acquireLock()
        defer { lock.release() }
        var state = try load()
        guard let saved = state.logins[alias] else { throw CodexLoginError.unknownAlias }
        guard try CodexAuthFile.identity(saved).accountID == CodexAuthFile.identity(login).accountID else {
            throw CodexLoginError.aliasTaken
        }
        state.logins[alias] = login
        try persist(state)
    }

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

extension CodexLoginSystem {
    func liveData() -> Data? { FileManager.default.contents(atPath: authPath) }
}

func runCodexLogins(arguments: [String], system: CodexLoginSystem = .current, output: (String) -> Void) -> Int32 {
    let usage = "Usage: AIControl codex-login save <alias> | list | use <alias> | rename <alias> <new-alias>"
    let valid = { (alias: String) in alias.range(of: #"\A[a-z][a-z0-9_-]{0,31}\z"#, options: .regularExpression) != nil }
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

/// Usage requests and sign-in for the Codex part of the app.
struct CodexAppServices {
    let fetch: (URLRequest) async throws -> Data
    /// Runs Codex's own sign-in; throws when it does not finish.
    let signIn: () throws -> Void
    /// Has Codex refresh a saved login in isolation and returns the refreshed copy.
    let renew: (Data) throws -> Data
    var now: () -> Date = Date.init
}

/// Serializes Codex login commands off the main actor; unavailable unless live switching is enabled.
actor CodexLoginAppAdapter {
    private let makeSystem: (() -> CodexLoginSystem)?
    private let services: CodexAppServices?

    init() { makeSystem = nil; services = nil }
    init(makeSystem: @escaping () -> CodexLoginSystem, services: CodexAppServices? = nil) {
        self.makeSystem = makeSystem
        self.services = services
    }

    /// Usage per saved alias, from auth.json for the live account and saved logins otherwise. An expired
    /// saved login that is not live is first renewed by Codex itself in isolation and saved again.
    func usage() async -> [String: LoginUsageResult] {
        guard let manager, let services, let saved = try? manager.savedLogins() else { return [:] }
        let live = manager.system.liveData()
        let liveAccount = live.flatMap { try? CodexAuthFile.identity($0) }?.accountID
        var results: [String: LoginUsageResult] = [:]
        for (alias, login) in saved {
            let account = (try? CodexAuthFile.identity(login))?.accountID
            let isLive = account != nil && account == liveAccount
            var data = isLive ? live! : login
            if !isLive && !Self.isFresh(data, at: services.now()) {
                guard let renewed = try? services.renew(login), (try? manager.replaceSaved(alias, with: renewed)) != nil else {
                    results[alias] = .unavailable("Use this account once to refresh its usage.")
                    continue
                }
                data = renewed
            }
            guard let tokens = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["tokens"] as? [String: Any],
                  let token = tokens["access_token"] as? String, let accountID = tokens["account_id"] as? String else {
                results[alias] = .unavailable("This login needs a new sign-in.")
                continue
            }
            do {
                let body = try await services.fetch(UsageRequests.codex(accessToken: token, accountID: accountID))
                results[alias] = .usage(try LoginUsage.codex(body, fetchedAt: services.now()))
            } catch {
                results[alias] = .unavailable("Usage could not be loaded.")
            }
        }
        return results
    }

    /// Has Codex refresh a saved login that is not the live one, and saves the refreshed login.
    func renew(alias: String) -> LoginEditResult {
        guard let manager, let services else { return .blocked("Login switching is off. Start AI Control with aic.") }
        guard let saved = (try? manager.savedLogins())?[alias] else { return .blocked("Blocked: no Codex login is saved as \(alias).") }
        if let live = manager.liveIdentity(), (try? CodexAuthFile.identity(saved))?.accountID == live.accountID {
            return .blocked("\(alias) is the live Codex login; Codex keeps it renewed.")
        }
        guard let renewed = try? services.renew(saved), (try? manager.replaceSaved(alias, with: renewed)) != nil else {
            return .blocked("Codex could not renew \(alias); its saved login is unchanged unless Codex already rotated it.")
        }
        return .done("Renewed Codex login \(alias).")
    }

    /// Detaches the live login so codex login cannot revoke it, signs in, and saves the new account;
    /// when sign-in does not finish, the previous login is put back.
    func add(alias: String) -> LoginEditResult {
        guard let manager, let services else { return .blocked("Login switching is off. Start AI Control with aic.") }
        let previous: String?
        do { previous = try manager.prepareLogin() } catch let error as CodexLoginError {
            return .blocked(error.message(name: alias, liveEmail: manager.liveIdentity()?.email))
        } catch { return .blocked("Blocked: saved Codex logins are unavailable.") }
        do { try services.signIn() } catch {
            if let previous { try? manager.use(previous) }
            let message = previous == nil ? "Sign-in did not finish." : "Sign-in did not finish; your previous Codex login is back."
            if let nativeError = error as? NativeCodexRequired {
                return .blocked(message + " " + nativeError.localizedDescription)
            }
            return .blocked(message)
        }
        do {
            let identity = try manager.save(alias)
            return .done("Saved Codex login \(alias) (\(identity.email ?? "unknown email")).")
        } catch let error as CodexLoginError {
            return .blocked(error.message(name: alias, liveEmail: manager.liveIdentity()?.email))
        } catch { return .blocked("Blocked: saved Codex logins are unavailable.") }
    }

    func rename(alias: String, to newAlias: String) -> LoginEditResult {
        guard let manager else { return .blocked("Login switching is off. Start AI Control with aic.") }
        do {
            try manager.rename(alias, to: newAlias)
            return .done("Renamed Codex login \(alias) to \(newAlias).")
        } catch let error as CodexLoginError {
            return .blocked(error.message(name: error == .aliasTaken ? newAlias : alias, liveEmail: nil))
        } catch { return .blocked("Blocked: saved Codex logins are unavailable.") }
    }

    private static func isFresh(_ login: Data, at now: Date) -> Bool {
        let tokens = (try? JSONSerialization.jsonObject(with: login) as? [String: Any])?["tokens"] as? [String: Any]
        guard let token = tokens?["access_token"] as? String, let expiry = expiry(ofJWT: token) else { return false }
        return expiry.timeIntervalSince(now) > 300
    }

    private static func expiry(ofJWT token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let exp = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["exp"] as? NSNumber else { return nil }
        return Date(timeIntervalSince1970: exp.doubleValue)
    }

    static func configured(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> CodexLoginAppAdapter {
        ClaudeLiveSystem.isEnabled(environment: environment) ? .init(makeSystem: { .current }, services: .live) : .init()
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

/// Lets the official Codex CLI refresh a saved login whose access has expired.
///
/// Codex runs one tiny request with a copy of the login in a throwaway `CODEX_HOME`, so `~/.codex` is never
/// touched. The copy is marked stale so Codex always refreshes it; Codex rotates the refresh token as it
/// refreshes, so the refreshed login is returned for saving before the directory is removed.
struct CodexIsolatedRenewal {
    enum Error: Swift.Error, Equatable { case notALogin, codexFailed, accountChanged }

    let codexExecutable: String
    let run: ClaudeIsolatedRenewal.Runner

    func renew(_ login: Data) throws -> Data {
        guard let identity = try? CodexAuthFile.identity(login),
              var root = try JSONSerialization.jsonObject(with: login) as? [String: Any],
              var tokens = root["tokens"] as? [String: Any] else { throw Error.notALogin }
        // An unreadable access token and an old refresh date make Codex refresh before its first request.
        tokens["access_token"] = "expired"
        root["tokens"] = tokens
        root["last_refresh"] = "2000-01-01T00:00:00Z"
        let directory = try PrivateTemporaryDirectory.create(prefix: "ai-control-renewal")
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let authPath = directory + "/auth.json"
        guard FileManager.default.createFile(
            atPath: authPath, contents: try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys, .withoutEscapingSlashes]),
            attributes: [.posixPermissions: 0o600]
        ) else { throw Error.codexFailed }

        var environment = ["HOME": NSHomeDirectory(), "CODEX_HOME": directory, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        for name in ["USER", "LOGNAME", "LANG", "TMPDIR"] { environment[name] = ProcessInfo.processInfo.environment[name] }
        // The exit status does not matter: a refresh can succeed even if the request after it fails.
        _ = try? run(codexExecutable, ["exec", "--skip-git-repo-check", "-s", "read-only", "Reply with exactly: OK"], environment, directory)

        // A refresh replaces the placeholder access token; if it is still there, nothing was renewed.
        guard let renewed = FileManager.default.contents(atPath: authPath),
              let renewedTokens = (try? JSONSerialization.jsonObject(with: renewed) as? [String: Any])?["tokens"] as? [String: Any],
              renewedTokens["access_token"] as? String != "expired" else { throw Error.codexFailed }
        guard (try? CodexAuthFile.identity(renewed))?.accountID == identity.accountID else { throw Error.accountChanged }
        return renewed
    }
}
