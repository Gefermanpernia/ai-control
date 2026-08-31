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

    func waitUntilStarted() async {
        guard callCount == 0 else { return }
        await withCheckedContinuation { continuation in
            startContinuations.append(continuation)
        }
    }

    func complete() {
        delayContinuation?.resume()
        delayContinuation = nil
    }
}

@MainActor
struct ControlStoreTests {

    // MARK: - Helpers

    /// Builds a store with the background refresh timer switched off through the
    /// store's own API, so assertions depend only on state transitions and never
    /// on wall-clock timing.
    private func makeStore(
        refreshDelay: @escaping @Sendable () async -> Void = {}
    ) -> ControlStore {
        let store = ControlStore(refreshDelay: refreshDelay)
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

    // MARK: - Selecting an account

    @Test("Selecting another selectable account makes it the active account")
    func selectingAnotherSelectableAccountMakesItActive() throws {
        let store = makeStore()
        let target = try account("claude-personal", for: .claude, in: store)
        #expect(target.status.isSelectable)
        #expect(store.activeAccountIDs[.claude] == "claude-work")

        store.select(target, for: .claude)

        #expect(store.activeAccountIDs[.claude] == "claude-personal")
        #expect(store.isActive(target, for: .claude))
        #expect(store.lastSwitch?.provider == .claude)
        #expect(store.lastSwitch?.previousID == "claude-work")
        #expect(store.switchMessage?.contains(target.name) == true)
    }

    @Test("Selecting an unavailable account leaves the active account unchanged")
    func selectingUnavailableAccountIsANoOp() throws {
        let store = makeStore()
        let unavailable = try account("claude-lab", for: .claude, in: store)
        #expect(unavailable.status.isSelectable == false)

        store.select(unavailable, for: .claude)

        #expect(store.activeAccountIDs[.claude] == "claude-work")
        #expect(store.isActive(unavailable, for: .claude) == false)
        #expect(store.lastSwitch == nil)
        #expect(store.switchMessage == nil)
    }

    @Test("Selecting the already active account records no undoable switch")
    func selectingActiveAccountRecordsNoUndoableSwitch() throws {
        let store = makeStore()
        let active = try account("claude-work", for: .claude, in: store)
        #expect(store.isActive(active, for: .claude))

        store.select(active, for: .claude)

        #expect(store.activeAccountIDs[.claude] == "claude-work")
        #expect(store.lastSwitch == nil)
        #expect(store.switchMessage == nil)
    }

    @Test("Selecting an account from another provider preserves switch and undo state")
    func selectingCrossProviderAccountIsANoOp() throws {
        let store = makeStore()
        let claudeAccount = try account("claude-personal", for: .claude, in: store)
        let codexAccount = try account("codex-consulting", for: .codex, in: store)
        store.select(claudeAccount, for: .claude)
        let switchMessage = store.switchMessage

        store.select(codexAccount, for: .claude)

        #expect(store.activeAccountIDs[.claude] == "claude-personal")
        #expect(store.activeAccountIDs[.codex] == "codex-personal")
        #expect(store.lastSwitch?.provider == .claude)
        #expect(store.lastSwitch?.previousID == "claude-work")
        #expect(store.switchMessage == switchMessage)

        store.undoLastSwitch()
        #expect(store.activeAccountIDs[.claude] == "claude-work")
    }

    // MARK: - Undo

    @Test("Undo restores the previously active account after a switch")
    func undoRestoresPreviouslyActiveAccount() throws {
        let store = makeStore()
        let previous = try account("claude-work", for: .claude, in: store)
        let target = try account("claude-personal", for: .claude, in: store)
        store.select(target, for: .claude)
        #expect(store.activeAccountIDs[.claude] == "claude-personal")

        store.undoLastSwitch()

        #expect(store.activeAccountIDs[.claude] == "claude-work")
        #expect(store.isActive(previous, for: .claude))
        #expect(store.lastSwitch == nil)
        #expect(store.switchMessage?.contains(previous.name) == true)
    }

    @Test("Undo without a prior switch is a no-op")
    func undoWithoutPriorSwitchIsANoOp() {
        let store = makeStore()
        #expect(store.lastSwitch == nil)

        store.undoLastSwitch()

        #expect(store.activeAccountIDs[.claude] == "claude-work")
        #expect(store.activeAccountIDs[.codex] == "codex-personal")
        #expect(store.lastSwitch == nil)
        #expect(store.switchMessage == nil)
    }

    // MARK: - Provider independence

    @Test("Switching a Claude account leaves the active Codex account unchanged")
    func switchingClaudeDoesNotAffectCodex() throws {
        let store = makeStore()
        let target = try account("claude-personal", for: .claude, in: store)

        store.select(target, for: .claude)

        #expect(store.activeAccountIDs[.claude] == "claude-personal")
        #expect(store.activeAccountIDs[.codex] == "codex-personal")
    }

    @Test("Switching a Codex account leaves the active Claude account unchanged")
    func switchingCodexDoesNotAffectClaude() throws {
        let store = makeStore()
        let target = try account("codex-consulting", for: .codex, in: store)

        store.select(target, for: .codex)

        #expect(store.activeAccountIDs[.codex] == "codex-consulting")
        #expect(store.activeAccountIDs[.claude] == "claude-work")
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
