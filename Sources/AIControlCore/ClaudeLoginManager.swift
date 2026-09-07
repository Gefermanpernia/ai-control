import Foundation

struct ClaudeLoginIdentity: Equatable, Sendable {
    let accountUUID: String
    let organizationUUID: String?
}

enum ClaudeLoginUsability: Equatable, Sendable {
    case usable
    case reLoginNeeded
}

struct ClaudeLoginSnapshot: Equatable, Sendable {
    enum Error: Swift.Error { case missingAccount, ambiguousIdentity, identityDisagreement }

    let claudeAiOauth: JSONPresence
    let oauthAccount: JSONPresence
    let organizationUUID: JSONPresence
    let trustedDeviceToken: JSONPresence
    let identity: ClaudeLoginIdentity
    let usability: ClaudeLoginUsability

    static func capture(secureRoot: String, configurationRoot: String) throws -> Self {
        let secure = try ScopedJSON(secureRoot)
        let configuration = try ScopedJSON(configurationRoot)
        let credentials = secure.presence(of: "claudeAiOauth")
        let account = configuration.presence(of: "oauthAccount")
        guard case .value(let accountRaw) = account else { throw Error.missingAccount }
        let accountObject = try ScopedJSON(accountRaw)
        guard let accountUUID = string(accountObject.presence(of: "accountUuid")), !accountUUID.isEmpty else {
            throw Error.ambiguousIdentity
        }
        let accountOrganization = string(accountObject.presence(of: "organizationUuid"))
        let secureOrganization = secure.presence(of: "organizationUuid")
        if let secureValue = string(secureOrganization), secureValue != accountOrganization {
            throw Error.identityDisagreement
        }
        return Self(
            claudeAiOauth: credentials,
            oauthAccount: account,
            organizationUUID: secureOrganization,
            trustedDeviceToken: secure.presence(of: "trustedDeviceToken"),
            identity: .init(accountUUID: accountUUID, organizationUUID: accountOrganization),
            usability: isDead(credentials) ? .reLoginNeeded : .usable
        )
    }

    private static func string(_ presence: JSONPresence) -> String? {
        guard case .value(let raw) = presence,
              let data = raw.data(using: .utf8),
              let value = try? JSONDecoder().decode(String.self, from: data) else { return nil }
        return value
    }

    private static func isDead(_ presence: JSONPresence) -> Bool {
        guard case .value(let raw) = presence, let object = try? ScopedJSON(raw) else { return true }
        guard let accessToken = string(object.presence(of: "accessToken")), !accessToken.isEmpty,
              let refreshToken = string(object.presence(of: "refreshToken")), !refreshToken.isEmpty else {
            return true
        }
        guard case .value(let expiry) = object.presence(of: "expiresAt") else { return false }
        return expiry.range(
            of: #"^-?0(?:\.0+)?(?:[eE][+-]?[0-9]+)?$"#,
            options: .regularExpression
        ) != nil
    }
}

struct ClaudeLoginState: Equatable, Sendable {
    var snapshots: [String: ClaudeLoginSnapshot] = [:]
    var activeAlias: String?
}

protocol ClaudeLoginBackend {
    func loadState() throws -> ClaudeLoginState
    func currentSnapshot() throws -> ClaudeLoginSnapshot
    func saveState(_ state: ClaudeLoginState) throws
}

private struct UnavailableClaudeLoginBackend: ClaudeLoginBackend {
    struct Unavailable: Swift.Error {}

    func loadState() throws -> ClaudeLoginState { throw Unavailable() }
    func currentSnapshot() throws -> ClaudeLoginSnapshot { throw Unavailable() }
    func saveState(_ state: ClaudeLoginState) throws { throw Unavailable() }
}

private enum ClaudeLoginCommand {
    case save(String)
    case list
    case use(String)
    case recover

    init?(arguments: [String]) {
        switch arguments {
        case ["claude-login", "list"]: self = .list
        case ["claude-login", "recover"]: self = .recover
        default:
            guard arguments.count == 3, arguments[0] == "claude-login",
                  Self.valid(arguments[2]) else { return nil }
            switch arguments[1] {
            case "save": self = .save(arguments[2])
            case "use": self = .use(arguments[2])
            default: return nil
            }
        }
    }

    private static func valid(_ alias: String) -> Bool {
        alias.range(of: #"^[a-z][a-z0-9_-]{0,31}$"#, options: .regularExpression) != nil
    }
}

@MainActor
public func runClaudeLogins(arguments: [String]) -> Int32 {
    runClaudeLogins(
        arguments: arguments,
        makeBackend: { UnavailableClaudeLoginBackend() },
        output: { print($0) },
        runGUI: runAIControl
    )
}

func runClaudeLogins(
    arguments: [String],
    makeBackend: () -> any ClaudeLoginBackend,
    output: (String) -> Void,
    runGUI: () -> Void
) -> Int32 {
    guard !arguments.isEmpty else {
        runGUI()
        return 0
    }
    guard let command = ClaudeLoginCommand(arguments: arguments) else {
        output("Usage: AIControl claude-login save <alias> | list | use <alias> | recover")
        return 2
    }
    switch command {
    case .use:
        output("Blocked: account selection is not implemented.")
        return 3
    case .recover:
        output("Blocked: recovery is not implemented.")
        return 3
    case .save, .list:
        break
    }

    let backend = makeBackend()
    do {
        switch command {
        case .save(let alias): return try save(alias: alias, backend: backend, output: output)
        case .list: return try list(backend: backend, output: output)
        case .use, .recover: return 3
        }
    } catch {
        output("Blocked: credential backend unavailable.")
        return 3
    }
}

private func save(
    alias: String,
    backend: any ClaudeLoginBackend,
    output: (String) -> Void
) throws -> Int32 {
    let snapshot = try backend.currentSnapshot()
    guard snapshot.usability == .usable else {
        output("Re-login needed before saving this alias.")
        return 5
    }
    var state = try backend.loadState()
    if let existing = state.snapshots[alias], existing.identity != snapshot.identity {
        output("Blocked: alias belongs to another login.")
        return 3
    }
    if state.snapshots[alias] == nil {
        guard state.snapshots.count < 2 else {
            output("Blocked: two aliases are already saved.")
            return 3
        }
        guard !state.snapshots.values.contains(where: { $0.identity == snapshot.identity }) else {
            output("Blocked: login is already saved.")
            return 3
        }
    }
    state.snapshots[alias] = snapshot
    if state.activeAlias == nil { state.activeAlias = alias }
    try backend.saveState(state)
    output("Saved alias \(alias).")
    return 0
}

private func list(backend: any ClaudeLoginBackend, output: (String) -> Void) throws -> Int32 {
    let state = try backend.loadState()
    guard !state.snapshots.isEmpty else {
        output("No saved Claude logins.")
        return 0
    }
    for alias in state.snapshots.keys.sorted() {
        let usability = state.snapshots[alias]?.usability == .usable ? "usable" : "re-login needed"
        let activeHint = state.activeAlias == alias ? " (active hint)" : ""
        output("\(alias): \(usability)\(activeHint)")
    }
    return 0
}
