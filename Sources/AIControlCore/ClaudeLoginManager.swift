import Foundation

struct ClaudeLoginIdentity: Hashable, Sendable {
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
    var journal: ClaudeLoginJournal? = nil
}

enum ClaudeLoginJournalPhase: String, Equatable, Sendable { case pending, committed }

struct ClaudeLoginOwnedFields: Equatable, Sendable {
    let secure: [String: JSONPresence]
    let configuration: [String: JSONPresence]

    static func capture(_ roots: ClaudeLoginRoots) throws -> Self {
        let secure = try ScopedJSON(roots.secure)
        let configuration = try ScopedJSON(roots.configuration)
        return .init(
            secure: Dictionary(uniqueKeysWithValues: ["claudeAiOauth", "organizationUuid", "trustedDeviceToken"].map {
                ($0, secure.presence(of: $0))
            }),
            configuration: Dictionary(uniqueKeysWithValues: (["oauthAccount"] + ClaudeConfigurationPatch.accountCacheKeys).map {
                ($0, configuration.presence(of: $0))
            })
        )
    }

    static func target(_ snapshot: ClaudeLoginSnapshot) -> Self {
        .init(
            secure: [
                "claudeAiOauth": snapshot.claudeAiOauth, "organizationUuid": snapshot.organizationUUID,
                "trustedDeviceToken": snapshot.trustedDeviceToken
            ],
            configuration: Dictionary(uniqueKeysWithValues: [
                ("oauthAccount", snapshot.oauthAccount)
            ] + ClaudeConfigurationPatch.accountCacheKeys.map { ($0, JSONPresence.missing) })
        )
    }
}

struct ClaudeLoginJournal: Equatable, Sendable {
    let operationID: String
    let source: String
    let target: String
    let before: ClaudeLoginOwnedFields
    let after: ClaudeLoginOwnedFields
    var phase: ClaudeLoginJournalPhase
}

struct ClaudeLoginRoots: Equatable, Sendable { let secure: String; let configuration: String }

struct ClaudeLoginResourceIO {
    let readRoots: () throws -> ClaudeLoginRoots
    let replaceSecure: (String, String, () throws -> Void) throws -> Void
    let replaceConfiguration: (String, String, () throws -> Void) throws -> Void
}

enum ClaudeLoginSelectionError: Error { case unavailable, unknownAlias, reLoginNeeded, ambiguousOutgoing, changedRoots, cleanupUncertain }

protocol ClaudeLoginBackend {
    func loadState() throws -> ClaudeLoginState
    func currentSnapshot() throws -> ClaudeLoginSnapshot
    func saveState(_ state: ClaudeLoginState) throws
    func selectAlias(_ alias: String) throws
    func recoverPendingLogin() throws
    func perform(command: ClaudeLoginBackendCommand, operation: (any ClaudeLoginBackend) throws -> Int32) throws -> Int32
}

enum ClaudeLoginBackendCommand { case save, list, use, recover }

extension ClaudeLoginBackend {
    func selectAlias(_: String) throws { throw ClaudeLoginSelectionError.unavailable }
    func recoverPendingLogin() throws { throw ClaudeLoginSelectionError.unavailable }
    func perform(
        command: ClaudeLoginBackendCommand,
        operation: (any ClaudeLoginBackend) throws -> Int32
    ) throws -> Int32 {
        try operation(self)
    }
}

final class GuardedClaudeLoginBackend: ClaudeLoginBackend {
    private let custody: ClaudeLoginCustody
    private let processPreflight: ClaudeProcessPreflight
    private let capture: () throws -> ClaudeLoginSnapshot
    private let commandInitialState: ClaudeLoginState?
    private let commandInitiallyExisting: Bool?
    private let selectionResources: ClaudeLoginResourceIO?

    init(
        custody: ClaudeLoginCustody,
        processPreflight: ClaudeProcessPreflight,
        currentSnapshot: @escaping () throws -> ClaudeLoginSnapshot,
        commandInitialState: ClaudeLoginState? = nil,
        commandInitiallyExisting: Bool? = nil,
        selectionResources: ClaudeLoginResourceIO? = nil
    ) {
        self.custody = custody
        self.processPreflight = processPreflight
        self.capture = currentSnapshot
        self.commandInitialState = commandInitialState
        self.commandInitiallyExisting = commandInitiallyExisting
        self.selectionResources = selectionResources
    }

    func loadState() throws -> ClaudeLoginState { try commandInitialState ?? custody.load() }
    func currentSnapshot() throws -> ClaudeLoginSnapshot {
        try processPreflight.requireQuiescent()
        return try capture()
    }

    func saveState(_ state: ClaudeLoginState) throws {
        try persist(state, permitsJournal: false)
    }

    func selectAlias(_ alias: String) throws {
        guard let resources = selectionResources else { throw ClaudeLoginSelectionError.unavailable }
        var state = try loadState()
        guard let initialTarget = state.snapshots[alias] else { throw ClaudeLoginSelectionError.unknownAlias }
        guard initialTarget.usability == .usable else { throw ClaudeLoginSelectionError.reLoginNeeded }
        try processPreflight.requireQuiescent()
        let roots = try resources.readRoots()
        try validateSelectionRoots(roots)
        let before = try ClaudeLoginOwnedFields.capture(roots)
        // Open sessions may rewrite the configuration, so it alone cannot name the live login. The alias
        // applied last does; the live login is re-saved only when the configuration agrees with it.
        let current = try? ClaudeLoginSnapshot.capture(secureRoot: roots.secure, configurationRoot: roots.configuration)
        let matching = current.map { live in state.snapshots.filter { $0.value.identity == live.identity }.map(\.key) } ?? []
        let source: String
        if let lastApplied = state.activeAlias, let stored = state.snapshots[lastApplied] {
            source = lastApplied
            if let current, matching == [lastApplied] {
                state.snapshots[source] = current
            } else if matching.count != 1 {
                // An unknown or unreadable account suggests a fresh native login: save it first.
                throw ClaudeLoginSelectionError.ambiguousOutgoing
            } else {
                // Keep the alias's own profile; take only the live Keychain login, which Claude refreshes in place.
                let profile = try ScopedJSON("{}").replacing(["oauthAccount": stored.oauthAccount])
                guard let refreshed = try? ClaudeLoginSnapshot.capture(secureRoot: roots.secure, configurationRoot: profile),
                      refreshed.identity == stored.identity else { throw ClaudeLoginSelectionError.ambiguousOutgoing }
                state.snapshots[source] = refreshed
            }
            try saveState(state)
        } else {
            guard let current, matching.count == 1, let only = matching.first else {
                throw ClaudeLoginSelectionError.ambiguousOutgoing
            }
            source = only
            state.snapshots[source] = current
            try saveState(state)
        }
        guard let target = state.snapshots[alias], target.usability == .usable else {
            throw ClaudeLoginSelectionError.reLoginNeeded
        }
        state.journal = .init(
            operationID: UUID().uuidString, source: source, target: alias, before: before,
            after: .target(target), phase: .pending
        )
        var prepared = false
        var committed = false
        do {
            try persist(state, permitsJournal: true) { prepared = true }
            guard try resources.readRoots() == roots else { throw ClaudeLoginSelectionError.changedRoots }
            let secure = try ScopedJSON(roots.secure).replacing(state.journal!.after.secure)
            let configuration = try ScopedJSON(roots.configuration).replacing(state.journal!.after.configuration)
            try resources.replaceSecure(roots.secure, secure, processPreflight.requireQuiescent)
            let securePostimage = try ClaudeLoginOwnedFields.capture(resources.readRoots())
            guard securePostimage.secure == state.journal?.after.secure else {
                throw ClaudeLoginEnvelopeError.readbackMismatch
            }
            try resources.replaceConfiguration(roots.configuration, configuration, processPreflight.requireQuiescent)
            let verified = try ClaudeLoginOwnedFields.capture(resources.readRoots())
            guard verified == state.journal?.after else { throw ClaudeLoginEnvelopeError.readbackMismatch }
            try processPreflight.requireQuiescent()
            state.activeAlias = alias
            state.journal?.phase = .committed
            try persist(state, permitsJournal: true) { committed = true }
            state.journal = nil
            try persist(state, permitsJournal: true)
        } catch {
            if committed { throw ClaudeLoginSelectionError.cleanupUncertain }
            if prepared { throw ClaudeLoginEnvelopeError.recoveryRequired }
            throw error
        }
    }

    func recoverPendingLogin() throws {
        try processPreflight.requireQuiescent()
        var state = try loadState()
        guard let journal = state.journal else { return }
        guard let resources = selectionResources else { throw ClaudeLoginEnvelopeError.recoveryRequired }

        do {
            let roots = try resources.readRoots()
            try validateSelectionRoots(roots)
            let latest = try ClaudeLoginOwnedFields.capture(roots)
            if journal.phase == .committed {
                guard latest == journal.after else { throw ClaudeLoginEnvelopeError.readbackMismatch }
                state.journal = nil
                try persist(state, permitsJournal: true)
                return
            }
            let secureChanges = try recoveryChanges(
                latest.secure, before: journal.before.secure, after: journal.after.secure
            )
            let configurationChanges = try recoveryChanges(
                latest.configuration, before: journal.before.configuration, after: journal.after.configuration
            )

            if !secureChanges.isEmpty {
                let replacement = try ScopedJSON(roots.secure).replacing(secureChanges)
                try resources.replaceSecure(roots.secure, replacement, processPreflight.requireQuiescent)
                guard try ClaudeLoginOwnedFields.capture(resources.readRoots()).secure == journal.before.secure else {
                    throw ClaudeLoginEnvelopeError.readbackMismatch
                }
            }
            if !configurationChanges.isEmpty {
                let replacement = try ScopedJSON(roots.configuration).replacing(configurationChanges)
                try resources.replaceConfiguration(roots.configuration, replacement, processPreflight.requireQuiescent)
                guard try ClaudeLoginOwnedFields.capture(resources.readRoots()).configuration == journal.before.configuration else {
                    throw ClaudeLoginEnvelopeError.readbackMismatch
                }
            }
            guard try ClaudeLoginOwnedFields.capture(resources.readRoots()) == journal.before else {
                throw ClaudeLoginEnvelopeError.readbackMismatch
            }
            state.journal = nil
            try persist(state, permitsJournal: true)
        } catch {
            throw ClaudeLoginEnvelopeError.recoveryRequired
        }
    }

    private func validateSelectionRoots(_ roots: ClaudeLoginRoots) throws {
        for root in [try ScopedJSON(roots.secure), try ScopedJSON(roots.configuration)] {
            guard root.presence(of: "enterpriseGateway") == .missing,
                  root.presence(of: "designOauth") == .missing else {
                throw ClaudeLoginSelectionError.changedRoots
            }
        }
    }

    private func recoveryChanges(
        _ latest: [String: JSONPresence], before: [String: JSONPresence], after: [String: JSONPresence]
    ) throws -> [String: JSONPresence] {
        var changes: [String: JSONPresence] = [:]
        for key in before.keys {
            guard let current = latest[key], let expectedAfter = after[key] else {
                throw ClaudeLoginEnvelopeError.recoveryRequired
            }
            if current == before[key] { continue }
            guard current == expectedAfter else { throw ClaudeLoginEnvelopeError.recoveryRequired }
            changes[key] = before[key]
        }
        return changes
    }

    private func persist(
        _ state: ClaudeLoginState, permitsJournal: Bool, afterVerifiedSave: () -> Void = {}
    ) throws {
        if let commandInitiallyExisting {
            try custody.save(
                state, expectedExisting: commandInitiallyExisting,
                guardedBy: processPreflight.requireQuiescent, permitsJournal: permitsJournal
            )
            afterVerifiedSave()
            let loaded = permitsJournal ? try custody.loadRecoveryRecord() : try custody.load()
            guard loaded == state else { throw ClaudeLoginEnvelopeError.readbackMismatch }
            try processPreflight.requireQuiescent()
            return
        }
        try processPreflight.performGuarded(
            write: {
                try custody.save(state, permitsJournal: permitsJournal)
                afterVerifiedSave()
            },
            verify: {
                let loaded = permitsJournal ? try custody.loadRecoveryRecord() : try custody.load()
                guard loaded == state else { throw ClaudeLoginEnvelopeError.readbackMismatch }
            }
        )
    }
}

final class CommandScopedClaudeLoginBackend: ClaudeLoginBackend {
    struct InvalidScope: Error {}

    private let acquireLock: () throws -> ManagerFileLock
    private let routingEvidence: () throws -> ClaudeRoutingEvidence
    private let readCustody: () throws -> ClaudeLoginCustody
    private let writeCustody: (ClaudeStorageRoute, @escaping () throws -> Void) throws -> ClaudeLoginCustody
    private let processPreflight: ClaudeProcessPreflight
    private let capture: (ClaudeStorageRoute) throws -> ClaudeLoginSnapshot
    private let selectionResources: (ClaudeStorageRoute) throws -> ClaudeLoginResourceIO

    init(
        acquireLock: @escaping () throws -> ManagerFileLock,
        routingEvidence: @escaping () throws -> ClaudeRoutingEvidence,
        readCustody: @escaping () throws -> ClaudeLoginCustody,
        writeCustody: @escaping (ClaudeStorageRoute, @escaping () throws -> Void) throws -> ClaudeLoginCustody,
        processPreflight: ClaudeProcessPreflight,
        currentSnapshot: @escaping (ClaudeStorageRoute) throws -> ClaudeLoginSnapshot,
        selectionResources: @escaping (ClaudeStorageRoute) throws -> ClaudeLoginResourceIO = { _ in
            throw ClaudeLoginSelectionError.unavailable
        }
    ) {
        self.acquireLock = acquireLock
        self.routingEvidence = routingEvidence
        self.readCustody = readCustody
        self.writeCustody = writeCustody
        self.processPreflight = processPreflight
        self.capture = currentSnapshot
        self.selectionResources = selectionResources
    }

    func perform(
        command: ClaudeLoginBackendCommand,
        operation: (any ClaudeLoginBackend) throws -> Int32
    ) throws -> Int32 {
        switch command {
        case .list:
            let custody = try readCustody()
            return try operation(GuardedClaudeLoginBackend(
                custody: custody, processPreflight: processPreflight,
                currentSnapshot: { throw InvalidScope() }
            ))
        case .save, .use:
            let lock = try acquireLock()
            defer { lock.release() }
            let route = try ClaudeRoutingValidator.route(routingEvidence())
            let custody = try writeCustody(route, {})
            let initial = try custody.loadWithPresence()
            let resources: ClaudeLoginResourceIO?
            if case .use = command { resources = try selectionResources(route) } else { resources = nil }
            return try operation(GuardedClaudeLoginBackend(
                custody: custody, processPreflight: processPreflight,
                currentSnapshot: { try self.capture(route) }, commandInitialState: initial.state,
                commandInitiallyExisting: initial.exists,
                selectionResources: resources
            ))
        case .recover:
            let lock = try acquireLock()
            defer { lock.release() }
            let route = try ClaudeRoutingValidator.route(routingEvidence())
            try processPreflight.requireQuiescent()
            let custody = try writeCustody(route, {})
            let initial: (state: ClaudeLoginState, exists: Bool)
            do {
                initial = (try custody.loadRecoveryRecord(), true)
            } catch IsolatedKeychainError.missing {
                initial = (ClaudeLoginState(), false)
            }
            return try operation(GuardedClaudeLoginBackend(
                custody: custody, processPreflight: processPreflight,
                currentSnapshot: { throw InvalidScope() }, commandInitialState: initial.state,
                commandInitiallyExisting: initial.exists,
                selectionResources: initial.state.journal == nil ? nil : try selectionResources(route)
            ))
        }
    }

    func loadState() throws -> ClaudeLoginState { throw InvalidScope() }
    func currentSnapshot() throws -> ClaudeLoginSnapshot { throw InvalidScope() }
    func saveState(_ state: ClaudeLoginState) throws { throw InvalidScope() }
}

private struct UnavailableClaudeLoginBackend: ClaudeLoginBackend {
    struct Unavailable: Swift.Error {}

    func loadState() throws -> ClaudeLoginState { throw Unavailable() }
    func currentSnapshot() throws -> ClaudeLoginSnapshot { throw Unavailable() }
    func saveState(_ state: ClaudeLoginState) throws { throw Unavailable() }
}

struct ClaudeLoginAppState: Equatable, Sendable {
    struct Alias: Equatable, Sendable {
        let name: String
        let requiresReLogin: Bool
    }

    let aliases: [Alias]
    let lastSelectedHint: String?
}

enum ClaudeLoginAppResult: Equatable, Sendable {
    case listed(ClaudeLoginAppState)
    case verifiedApplied(String)
    case recoveryChecked
    case refused
    case claudeRunning
    case unknownAlias
    case reLoginNeeded(String)
    case recoveryRequired
    case backendUnavailable
    case postCommitCleanupUncertain
    case unverifiedFailure
}

actor ClaudeLoginAppAdapter {
    private let makeBackend: (() -> any ClaudeLoginBackend)?
    private var retainedBackend: (any ClaudeLoginBackend)?

    init() { makeBackend = nil }
    init(makeBackend: @escaping () -> any ClaudeLoginBackend) { self.makeBackend = makeBackend }

    /// Real switching only when `AI_CONTROL_CLAUDE_LIVE=1`; otherwise the app reports it as unavailable.
    static func configured(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> ClaudeLoginAppAdapter {
        guard let makeBackend = ClaudeLiveSystem.configuredBackend(environment: environment) else { return .init() }
        return .init(makeBackend: makeBackend)
    }

    func list() -> ClaudeLoginAppResult {
        guard let backend = backend() else { return .backendUnavailable }
        do {
            var result = ClaudeLoginAppResult.unverifiedFailure
            _ = try backend.perform(command: .list) {
                let state = try $0.loadState()
                let aliases = state.snapshots.map {
                    ClaudeLoginAppState.Alias(name: $0.key, requiresReLogin: $0.value.usability != .usable)
                }.sorted { $0.name < $1.name }
                result = .listed(.init(aliases: aliases, lastSelectedHint: state.activeAlias))
                return 0
            }
            return result
        } catch { return failure(error) }
    }

    func use(alias: String) -> ClaudeLoginAppResult {
        guard let backend = backend() else { return .backendUnavailable }
        do {
            _ = try backend.perform(command: .use) { try $0.selectAlias(alias); return 0 }
            return .verifiedApplied(alias)
        } catch { return failure(error, alias: alias) }
    }

    func recover() -> ClaudeLoginAppResult {
        guard let backend = backend() else { return .backendUnavailable }
        do {
            _ = try backend.perform(command: .recover) { try $0.recoverPendingLogin(); return 0 }
            return .recoveryChecked
        } catch { return failure(error) }
    }

    private func backend() -> (any ClaudeLoginBackend)? {
        if let retainedBackend { return retainedBackend }
        guard let makeBackend else { return nil }
        let backend = makeBackend()
        retainedBackend = backend
        return backend
    }

    private func failure(_ error: Error, alias: String? = nil) -> ClaudeLoginAppResult {
        switch error {
        case ClaudeLoginEnvelopeError.recoveryRequired: return .recoveryRequired
        case ClaudeLoginSelectionError.unknownAlias: return .unknownAlias
        case ClaudeLoginSelectionError.reLoginNeeded: return .reLoginNeeded(alias ?? "")
        case ClaudeLoginSelectionError.cleanupUncertain: return .postCommitCleanupUncertain
        case ClaudeLoginSelectionError.unavailable: return .backendUnavailable
        case ClaudeProcessPreflightError.active: return .claudeRunning
        case ClaudeLoginSelectionError.ambiguousOutgoing, ClaudeLoginSelectionError.changedRoots: return .refused
        default: return .unverifiedFailure
        }
    }
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
    let liveBackend = ClaudeLiveSystem.configuredBackend(environment: ProcessInfo.processInfo.environment)
    return runClaudeLogins(
        arguments: arguments,
        makeBackend: liveBackend ?? { UnavailableClaudeLoginBackend() },
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
    let backend = makeBackend()
    do {
        switch command {
        case .save(let alias):
            return try backend.perform(command: .save) { try save(alias: alias, backend: $0, output: output) }
        case .list:
            return try backend.perform(command: .list) { try list(backend: $0, output: output) }
        case .use(let alias):
            return try backend.perform(command: .use) { try use(alias: alias, backend: $0, output: output) }
        case .recover:
            return try backend.perform(command: .recover) {
                try $0.recoverPendingLogin()
                output("Recovered pending login switch.")
                return 0
            }
        }
    } catch ClaudeLoginEnvelopeError.recoveryRequired {
        if command.isUse {
            output("Recovery required before selecting another alias.")
        } else if command.isRecover {
            output("Recovery required; recovery did not complete.")
        } else {
            output("Recovery required before saving an alias.")
        }
        return 4
    } catch ClaudeLoginSelectionError.unknownAlias {
        output("Blocked: alias is not saved.")
        return 3
    } catch ClaudeLoginSelectionError.reLoginNeeded {
        if case .use(let alias) = command { output("Re-login needed before selecting alias \(alias).") }
        return 5
    } catch ClaudeLoginSelectionError.cleanupUncertain {
        output("Blocked: selection applied but cleanup is uncertain.")
        return 3
    } catch ClaudeProcessPreflightError.active {
        output("Blocked: Claude Code is running; quit every session and try again.")
        return 3
    } catch ClaudeRoutingError.unsupportedBuild {
        output("Blocked: this Claude Code build stores logins differently from reviewed builds.")
        return 3
    } catch {
        output("Blocked: credential backend unavailable.")
        // Error types carry only status codes and cases, never credential content.
        if ProcessInfo.processInfo.environment["AI_CONTROL_DEBUG"] == "1" { output("Debug: \(String(reflecting: error))") }
        return 3
    }
}

private extension ClaudeLoginCommand {
    var isUse: Bool { if case .use = self { return true }; return false }
    var isRecover: Bool { if case .recover = self { return true }; return false }
}

private func use(alias: String, backend: any ClaudeLoginBackend, output: (String) -> Void) throws -> Int32 {
    try backend.selectAlias(alias)
    output("Applied alias \(alias).")
    return 0
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
