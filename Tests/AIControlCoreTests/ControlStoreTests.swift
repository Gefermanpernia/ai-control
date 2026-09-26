import Testing
@testable import AIControlCore

private actor ControlledRefreshDelay {
    private var delayContinuation: CheckedContinuation<Void, Never>?
    private var startContinuations: [CheckedContinuation<Void, Never>] = []
    private(set) var callCount = 0

    func wait() async {
        callCount += 1
        let continuations = startContinuations
        startContinuations.removeAll()
        continuations.forEach { $0.resume() }

        await withCheckedContinuation { continuation in
            delayContinuation = continuation
        }
    }

    func waitUntilStarted(callCount expectedCallCount: Int = 1) async {
        guard callCount < expectedCallCount else { return }
        await withCheckedContinuation { continuation in
            startContinuations.append(continuation)
        }
    }

    func complete() {
        delayContinuation?.resume()
        delayContinuation = nil
    }
}

private final class SavedLoginBackend: ClaudeLoginBackend {
    private var state: ClaudeLoginState
    private let loadFails: Bool
    private let selectionError: Error?
    private(set) var selectCalls = 0

    init(state: ClaudeLoginState? = nil, betaUsable: Bool = false, loadFails: Bool = false, selectionError: Error? = nil) throws {
        self.state = try state ?? .init(
            snapshots: ["beta": savedLogin("b", usable: betaUsable), "alpha": savedLogin("a")], activeAlias: "alpha"
        )
        self.loadFails = loadFails
        self.selectionError = selectionError
    }

    func loadState() throws -> ClaudeLoginState {
        if loadFails { throw ClaudeLoginEnvelopeError.invalid }
        return state
    }
    func currentSnapshot() throws -> ClaudeLoginSnapshot { throw ClaudeLoginSelectionError.unavailable }
    func saveState(_: ClaudeLoginState) throws {}
    func selectAlias(_ alias: String) throws {
        selectCalls += 1
        if let selectionError { throw selectionError }
        state.activeAlias = alias
    }
    func recoverPendingLogin() throws {}
}

private func savedLogin(_ account: String, usable: Bool = true) throws -> ClaudeLoginSnapshot {
    let token = usable ? "synthetic" : ""
    return try ClaudeLoginSnapshot.capture(
        secureRoot: #"{"claudeAiOauth":{"accessToken":"\#(token)","refreshToken":"\#(token)"}}"#,
        configurationRoot: #"{"oauthAccount":{"accountUuid":"\#(account)"}}"#
    )
}

private struct UnexpectedSwitchError: Error {}

enum ClaudeSwitchFailure: CaseIterable {
    case refused, unknownAlias, reLoginNeeded, recoveryRequired, cleanupUncertain, unavailable, unverified

    var error: Error {
        switch self {
        case .refused: return ClaudeLoginSelectionError.changedRoots
        case .unknownAlias: return ClaudeLoginSelectionError.unknownAlias
        case .reLoginNeeded: return ClaudeLoginSelectionError.reLoginNeeded
        case .recoveryRequired: return ClaudeLoginEnvelopeError.recoveryRequired
        case .cleanupUncertain: return ClaudeLoginSelectionError.cleanupUncertain
        case .unavailable: return ClaudeLoginSelectionError.unavailable
        case .unverified: return UnexpectedSwitchError()
        }
    }

    var expectedNotice: ClaudeLoginNotice {
        switch self {
        case .refused:
            return .init(text: "Not switched. Claude or its files changed; close Claude and try again.", offersRecovery: false)
        case .unknownAlias:
            return .init(text: "beta is no longer a saved login.", offersRecovery: false)
        case .reLoginNeeded:
            return .init(text: "beta needs a new login. Sign in with Claude, then save it again.", offersRecovery: false)
        case .recoveryRequired:
            return .init(text: "A previous switch did not finish. Run recovery before switching.", offersRecovery: true)
        case .cleanupUncertain:
            return .init(text: "beta may be applied, but cleanup was not confirmed. Run recovery to check.", offersRecovery: true)
        case .unavailable:
            return .init(text: "Claude login switching is not available in this build.", offersRecovery: false)
        case .unverified:
            return .init(text: "The switch could not be verified and credentials may have changed. Run recovery to check.", offersRecovery: true)
        }
    }
}

@MainActor
struct ControlStoreTests {

    // MARK: - Helpers

    /// Builds a store with the background refresh timer switched off through the
    /// store's own API, so assertions depend only on state transitions and never
    /// on wall-clock timing.
    private func makeStore(
        refreshDelay: @escaping @Sendable () async -> Void = {},
        claudeBackend: (any ClaudeLoginBackend)? = nil
    ) -> ControlStore {
        let adapter = claudeBackend.map { backend in ClaudeLoginAppAdapter(makeBackend: { backend }) }
        let store = ControlStore(refreshDelay: refreshDelay, claudeLogins: adapter ?? ClaudeLoginAppAdapter())
        store.automaticRefresh = false
        return store
    }

    private func account(
        _ id: String,
        for provider: CLIProvider,
        in store: ControlStore
    ) throws -> Account {
        try #require(store.accounts(for: provider).first { $0.id == id })
    }

    // MARK: - Selecting a Codex mock account

    @Test("Selecting another selectable Codex account makes it the active account")
    func selectingAnotherSelectableAccountMakesItActive() throws {
        let store = makeStore()
        let target = try account("codex-consulting", for: .codex, in: store)
        #expect(target.status.isSelectable)
        #expect(store.activeAccountIDs[.codex] == "codex-personal")

        store.select(target, for: .codex)

        #expect(store.activeAccountIDs[.codex] == "codex-consulting")
        #expect(store.isActive(target, for: .codex))
        #expect(store.lastSwitch?.provider == .codex)
        #expect(store.lastSwitch?.previousID == "codex-personal")
        #expect(store.switchMessage?.contains(target.name) == true)
    }

    @Test("Selecting an unavailable Codex account leaves the active account unchanged")
    func selectingUnavailableAccountIsANoOp() throws {
        let store = makeStore()
        let unavailable = try account("codex-playground", for: .codex, in: store)
        #expect(unavailable.status.isSelectable == false)

        store.select(unavailable, for: .codex)

        #expect(store.activeAccountIDs[.codex] == "codex-personal")
        #expect(store.isActive(unavailable, for: .codex) == false)
        #expect(store.lastSwitch == nil)
        #expect(store.switchMessage == nil)
    }

    @Test("Selecting the already active Codex account records no undoable switch")
    func selectingActiveAccountRecordsNoUndoableSwitch() throws {
        let store = makeStore()
        let active = try account("codex-personal", for: .codex, in: store)
        #expect(store.isActive(active, for: .codex))

        store.select(active, for: .codex)

        #expect(store.activeAccountIDs[.codex] == "codex-personal")
        #expect(store.lastSwitch == nil)
        #expect(store.switchMessage == nil)
    }

    @Test("Claude has no mock accounts, so a Codex account cannot be selected for Claude")
    func selectingCrossProviderAccountIsANoOp() throws {
        let store = makeStore()
        let codexAccount = try account("codex-consulting", for: .codex, in: store)
        #expect(store.accounts(for: .claude).isEmpty)

        store.select(codexAccount, for: .claude)

        #expect(store.activeAccountIDs[.claude] == nil)
        #expect(store.activeAccountIDs[.codex] == "codex-personal")
        #expect(store.lastSwitch == nil)
        #expect(store.switchMessage == nil)
    }

    // MARK: - Undo

    @Test("Undo restores the previously active Codex account after a switch")
    func undoRestoresPreviouslyActiveAccount() throws {
        let store = makeStore()
        let previous = try account("codex-personal", for: .codex, in: store)
        let target = try account("codex-consulting", for: .codex, in: store)
        store.select(target, for: .codex)
        #expect(store.activeAccountIDs[.codex] == "codex-consulting")

        store.undoLastSwitch()

        #expect(store.activeAccountIDs[.codex] == "codex-personal")
        #expect(store.isActive(previous, for: .codex))
        #expect(store.lastSwitch == nil)
        #expect(store.switchMessage?.contains(previous.name) == true)
    }

    @Test("Undo without a prior switch is a no-op")
    func undoWithoutPriorSwitchIsANoOp() {
        let store = makeStore()
        #expect(store.lastSwitch == nil)

        store.undoLastSwitch()

        #expect(store.activeAccountIDs[.codex] == "codex-personal")
        #expect(store.lastSwitch == nil)
        #expect(store.switchMessage == nil)
    }

    // MARK: - Claude saved logins

    @Test("The default build shows Claude as unavailable instead of mock accounts")
    func defaultBuildReportsClaudeUnavailable() async throws {
        let store = makeStore()
        #expect(store.claudeLogins == .loading)

        try await #require(store.reloadClaudeLogins()).value

        #expect(store.claudeLogins == .unavailable)
        #expect(store.claudeActivity == .idle)
        #expect(store.claudeNotice == nil)
    }

    @Test("Saved logins keep the last-selected hint distinct from a verified switch")
    func savedLoginsProjectHintWithoutClaimingApplication() async throws {
        let backend = try SavedLoginBackend()
        let store = makeStore(claudeBackend: backend)

        try await #require(store.reloadClaudeLogins()).value

        let alpha = ClaudeLoginAppState.Alias(name: "alpha", requiresReLogin: false)
        let beta = ClaudeLoginAppState.Alias(name: "beta", requiresReLogin: true)
        #expect(store.claudeLogins == .loaded(.init(aliases: [alpha, beta], lastSelectedHint: "alpha")))
        #expect(store.claudeNotice == nil)
        #expect(store.canSelectClaudeLogin(alpha))
        #expect(store.canSelectClaudeLogin(beta) == false)
        #expect(store.selectClaudeLogin("beta") == nil)
        #expect(backend.selectCalls == 0)
    }

    @Test("Empty and unreadable saved-login states are distinct")
    func emptyAndUnreadableStatesAreDistinct() async throws {
        let empty = makeStore(claudeBackend: try SavedLoginBackend(state: .init()))
        try await #require(empty.reloadClaudeLogins()).value
        #expect(empty.claudeLogins == .loaded(.init(aliases: [], lastSelectedHint: nil)))

        let unreadable = makeStore(claudeBackend: try SavedLoginBackend(loadFails: true))
        try await #require(unreadable.reloadClaudeLogins()).value
        #expect(unreadable.claudeLogins == .unreadable)
    }

    @Test("A verified switch is serialized, reported as applied, and refreshes the hint")
    func verifiedSwitchIsSerializedAndApplied() async throws {
        let backend = try SavedLoginBackend(betaUsable: true)
        let store = makeStore(claudeBackend: backend)
        try await #require(store.reloadClaudeLogins()).value

        let task = try #require(store.selectClaudeLogin("beta"))

        #expect(store.claudeActivity == .switching("beta"))
        #expect(store.selectClaudeLogin("alpha") == nil)
        #expect(store.reloadClaudeLogins() == nil)
        #expect(store.recoverClaudeLogins() == nil)
        await task.value
        #expect(store.claudeActivity == .idle)
        #expect(store.claudeNotice == .init(text: "Applied beta. Restart Claude before use.", offersRecovery: false))
        #expect(store.claudeLogins == .loaded(.init(aliases: [
            .init(name: "alpha", requiresReLogin: false), .init(name: "beta", requiresReLogin: false)
        ], lastSelectedHint: "beta")))
        #expect(backend.selectCalls == 1)
        #expect(store.lastSwitch == nil)
        #expect(store.activeAccountIDs[.codex] == "codex-personal")
    }

    @Test("Cancelling the store task still reports the switch's actual outcome")
    func cancelledSwitchReportsActualOutcome() async throws {
        let store = makeStore(claudeBackend: try SavedLoginBackend(betaUsable: true))
        try await #require(store.reloadClaudeLogins()).value

        let task = try #require(store.selectClaudeLogin("beta"))
        task.cancel()
        await task.value

        #expect(store.claudeActivity == .idle)
        #expect(store.claudeNotice?.text == "Applied beta. Restart Claude before use.")
    }

    @Test("Switch failures stay distinct and never claim unchanged credentials", arguments: ClaudeSwitchFailure.allCases)
    func switchFailuresStayDistinct(_ failure: ClaudeSwitchFailure) async throws {
        let store = makeStore(claudeBackend: try SavedLoginBackend(betaUsable: true, selectionError: failure.error))
        try await #require(store.reloadClaudeLogins()).value

        try await #require(store.selectClaudeLogin("beta")).value

        #expect(store.claudeActivity == .idle)
        #expect(store.claudeNotice == failure.expectedNotice)
        if case .loaded(let state) = store.claudeLogins { #expect(state.lastSelectedHint == "alpha") }
        else { Issue.record("Saved logins were not reloaded after a failed switch") }
    }

    @Test("Recovery reports a checked recovery, not an applied selection")
    func recoveryReportsCheckedNotApplied() async throws {
        let store = makeStore(claudeBackend: try SavedLoginBackend(
            betaUsable: true, selectionError: ClaudeLoginEnvelopeError.recoveryRequired
        ))
        try await #require(store.reloadClaudeLogins()).value
        try await #require(store.selectClaudeLogin("beta")).value
        #expect(store.claudeNotice?.offersRecovery == true)

        let task = try #require(store.recoverClaudeLogins())

        #expect(store.claudeActivity == .recovering)
        await task.value
        #expect(store.claudeActivity == .idle)
        #expect(store.claudeNotice == .init(
            text: "Recovery check finished. Choose a saved login to switch.", offersRecovery: false
        ))
    }

    // MARK: - Provider independence

    @Test("Switching a Codex account leaves Claude saved logins unchanged")
    func switchingCodexDoesNotAffectClaude() async throws {
        let store = makeStore(claudeBackend: try SavedLoginBackend())
        try await #require(store.reloadClaudeLogins()).value
        let claudeState = store.claudeLogins
        let target = try account("codex-consulting", for: .codex, in: store)

        store.select(target, for: .codex)

        #expect(store.activeAccountIDs[.codex] == "codex-consulting")
        #expect(store.claudeLogins == claudeState)
        #expect(store.claudeNotice == nil)
    }

    // MARK: - Refresh

    @Test("Refresh reports progress and completion without wall-clock waiting")
    func refreshReportsProgressAndCompletion() async throws {
        let delay = ControlledRefreshDelay()
        let store = makeStore(refreshDelay: { await delay.wait() })

        let refreshTask = try #require(store.refresh())

        #expect(store.isRefreshing)
        #expect(store.updatedText == "Refreshing usage…")

        await delay.waitUntilStarted()
        await delay.complete()
        await refreshTask.value

        #expect(store.isRefreshing == false)
        #expect(store.updatedText == "Updated just now")
    }

    @Test("Refresh suppresses a duplicate while one is in progress")
    func refreshSuppressesDuplicateWhileInProgress() async throws {
        let delay = ControlledRefreshDelay()
        let store = makeStore(refreshDelay: { await delay.wait() })
        let refreshTask = try #require(store.refresh())
        await delay.waitUntilStarted()

        let duplicateTask = store.refresh()

        #expect(duplicateTask == nil)
        #expect(store.isRefreshing)
        #expect(await delay.callCount == 1)

        await delay.complete()
        await refreshTask.value
    }

    @Test("Cancelling refresh restores prior state and permits another refresh")
    func cancellingRefreshRestoresPriorStateAndPermitsAnotherRefresh() async throws {
        let delay = ControlledRefreshDelay()
        let store = makeStore(refreshDelay: { await delay.wait() })
        let priorUpdatedText = store.updatedText
        let refreshTask = try #require(store.refresh())

        #expect(store.isRefreshing)
        #expect(store.updatedText == "Refreshing usage…")
        await delay.waitUntilStarted()

        refreshTask.cancel()
        await delay.complete()
        await refreshTask.value

        #expect(store.isRefreshing == false)
        #expect(store.updatedText == priorUpdatedText)

        let nextRefreshTask = try #require(store.refresh())
        await delay.waitUntilStarted(callCount: 2)
        #expect(store.isRefreshing)
        #expect(await delay.callCount == 2)

        await delay.complete()
        await nextRefreshTask.value
    }

    // MARK: - Menu warning

    @Test("Menu warning shows when limit warnings are on and a warning account exists")
    func menuWarningShowsWhenLimitWarningsEnabled() {
        let store = makeStore()
        #expect(store.limitWarnings)

        #expect(store.showsMenuWarning)
    }

    @Test("Menu warning is hidden when limit warnings are off")
    func menuWarningHiddenWhenLimitWarningsDisabled() {
        let store = makeStore()

        store.limitWarnings = false

        #expect(store.showsMenuWarning == false)
    }
}
