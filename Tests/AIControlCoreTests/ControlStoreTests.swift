#if os(macOS)
import AppKit
import Foundation
import Testing
@testable import AIControlCore

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
    func saveState(_ state: ClaudeLoginState) throws { self.state = state }
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
    case refused, claudeRunning, unknownAlias, reLoginNeeded, recoveryRequired, cleanupUncertain, unavailable, unverified

    var error: Error {
        switch self {
        case .refused: return ClaudeLoginSelectionError.changedRoots
        case .claudeRunning: return ClaudeProcessPreflightError.active
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
        case .claudeRunning:
            return .init(text: "Not switched. Quit every Claude Code session, then try again.", offersRecovery: false)
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

    private func makeStore(
        claudeBackend: (any ClaudeLoginBackend)? = nil, codex: CodexStoreFixture? = nil,
        monitors: UsageMonitors = .init(environment: [:], readFile: { _ in throw CancellationError() },
                                       fetch: { _ in throw CancellationError() }, now: Date.init)
    ) -> ControlStore {
        let claude = claudeBackend.map { backend in ClaudeLoginAppAdapter(makeBackend: { backend }) }
        let codexAdapter = codex.map { fixture in CodexLoginAppAdapter(makeSystem: { fixture.system }) }
        return ControlStore(claudeLogins: claude ?? ClaudeLoginAppAdapter(), codexLogins: codexAdapter ?? CodexLoginAppAdapter(),
                            monitors: monitors)
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
        #expect(store.claudeNotice == .init(text: "Switched Claude to beta.", offersRecovery: false))
        #expect(store.claudeLogins == .loaded(.init(aliases: [
            .init(name: "alpha", requiresReLogin: false), .init(name: "beta", requiresReLogin: false)
        ], lastSelectedHint: "beta")))
        #expect(backend.selectCalls == 1)
    }

    @Test("Cancelling the store task still reports the switch's actual outcome")
    func cancelledSwitchReportsActualOutcome() async throws {
        let store = makeStore(claudeBackend: try SavedLoginBackend(betaUsable: true))
        try await #require(store.reloadClaudeLogins()).value

        let task = try #require(store.selectClaudeLogin("beta"))
        task.cancel()
        await task.value

        #expect(store.claudeActivity == .idle)
        #expect(store.claudeNotice?.text == "Switched Claude to beta.")
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

    // MARK: - Codex saved logins

    @Test("The default build shows Codex as unavailable instead of mock accounts")
    func defaultBuildReportsCodexUnavailable() async throws {
        let store = makeStore()
        try await #require(store.reloadCodexLogins()).value
        #expect(store.codexLogins == .unavailable)
    }

    @Test("Codex lists saved logins with their email and marks the one in auth.json as in use")
    func codexListsSavedLogins() async throws {
        let codex = try CodexStoreFixture()
        defer { codex.cleanup() }
        let store = makeStore(codex: codex)

        try await #require(store.reloadCodexLogins()).value

        #expect(store.codexLogins == .loaded(.init(logins: [
            .init(name: "home", email: "b@example.com"), .init(name: "spare", email: "s@example.com"),
            .init(name: "work", email: "a@example.com")
        ], inUse: "home")))
        #expect(store.canSelectCodexLogin(.init(name: "home", email: "b@example.com")) == false)
        #expect(store.canSelectCodexLogin(.init(name: "work", email: "a@example.com")))
    }

    @Test("A Codex switch is serialized, swaps auth.json, and reports the switch")
    func codexSwitchIsSerialized() async throws {
        let codex = try CodexStoreFixture()
        defer { codex.cleanup() }
        let store = makeStore(codex: codex)
        try await #require(store.reloadCodexLogins()).value

        let task = try #require(store.selectCodexLogin("work"))
        #expect(store.codexActivity == .switching("work"))
        #expect(store.selectCodexLogin("spare") == nil)
        #expect(store.reloadCodexLogins() == nil)
        await task.value

        #expect(store.codexActivity == .idle)
        #expect(store.codexNotice?.text == "Switched Codex to work.")
        if case .loaded(let listing) = store.codexLogins { #expect(listing.inUse == "work") }
        else { Issue.record("Codex logins were not reloaded") }
        #expect(codex.live == codex.work)
    }

    @Test("A refused Codex switch explains why and leaves auth.json alone")
    func codexRefusalIsExplained() async throws {
        let codex = try CodexStoreFixture()
        defer { codex.cleanup() }
        let store = makeStore(codex: codex)
        try await #require(store.reloadCodexLogins()).value
        let stranger = try codexStoreAuth(account: "acct-c", email: "c@example.com")
        codex.live = stranger

        try await #require(store.selectCodexLogin("work")).value

        #expect(store.codexNotice?.text == "Blocked: the current Codex login (c@example.com) is not saved; save it first.")
        #expect(codex.live == stranger)
    }

    @Test("Switching Codex leaves Claude saved logins unchanged")
    func switchingCodexDoesNotAffectClaude() async throws {
        let codex = try CodexStoreFixture()
        defer { codex.cleanup() }
        let store = makeStore(claudeBackend: try SavedLoginBackend(), codex: codex)
        try await #require(store.reloadClaudeLogins()).value
        try await #require(store.reloadCodexLogins()).value
        let claudeState = store.claudeLogins

        try await #require(store.selectCodexLogin("work")).value

        #expect(store.claudeLogins == claudeState)
        #expect(store.claudeNotice == nil)
    }

    // MARK: - Usage, rename and add

    @Test("Opening loads monitors in source order, throttles for 30 seconds, and rejects concurrent refreshes")
    func monitorRefreshIsThrottledAndSerialized() async throws {
        let gate = MonitorFetchGate()
        let source = UsageMonitors(
            environment: ["OPENCODE_AUTH_CONTENT": #"{"opencode-go":{"type":"api","key":"synthetic"}}"#,
                          "NAN_API_KEY": "synthetic"],
            readFile: { _ in Issue.record("Unexpected login file access"); return Data() },
            fetch: { request in await gate.fetch(request) }, now: Date.init
        )
        let store = makeStore(monitors: source)
        let opened = Date()
        store.windowOpened(now: opened)
        await gate.waitForFirstRequest()
        #expect(store.isLoadingMonitors)
        #expect(store.refreshMonitors() == nil)
        store.windowOpened(now: opened.addingTimeInterval(10))
        await gate.releaseFirstRequest()
        while store.isLoadingMonitors { await Task.yield() }
        #expect(await gate.count == 2)
        #expect(store.monitors.map(\.id) == ["opencode-go", "nan"])
        #expect(store.monitors[0].usage?.windows.first?.label == "5h")
        #expect(store.monitors[1].models?.first?.model == "deepseek-v4-flash")
        store.windowOpened(now: opened.addingTimeInterval(31))
        while store.isLoadingMonitors { await Task.yield() }
        #expect(await gate.count == 4)
    }

    @Test("The screenshot demo never fetches monitors, even on manual refresh")
    func demoDoesNotFetchMonitors() async {
        let gate = MonitorFetchGate()
        let source = UsageMonitors(environment: ["NAN_API_KEY": "synthetic"],
                                   readFile: { _ in Issue.record("Unexpected login file access"); return Data() },
                                   fetch: { request in await gate.fetch(request) }, now: Date.init)
        let store = ControlStore.demo(monitors: source)
        store.windowOpened()
        #expect(store.refreshMonitors() == nil)
        #expect(store.monitors.isEmpty && !store.isLoadingMonitors)
        #expect(await gate.count == 0)
    }

    @Test("Token totals use compact units without unnecessary decimal places")
    func compactTokenTotals() {
        #expect(TokenCountFormatter.compact(950_000) == "950K")
        #expect(TokenCountFormatter.compact(1_200_000_000) == "1.2B")
        #expect(TokenCountFormatter.compact(3_000_000_000) == "3B")
        #expect(TokenCountFormatter.compact(999) == "999")
        // Rounding decides the unit: values just under a boundary move up instead of showing "1000K" or "10.0B".
        #expect(TokenCountFormatter.compact(999_950) == "1M")
        #expect(TokenCountFormatter.compact(9_950_000_000) == "10B")
        #expect(TokenCountFormatter.compact(1_000) == "1K")
        #expect(TokenCountFormatter.compact(12_345) == "12K")
    }

    @Test("Usage loads after the list, per saved login")
    func usageLoadsPerLogin() async throws {
        let backend = try SavedLoginBackend(betaUsable: true)
        let body = Data(#"{"five_hour":{"utilization":12.0,"resets_at":null}}"#.utf8)
        let store = ControlStore(claudeLogins: ClaudeLoginAppAdapter(makeBackend: { backend }, services: .init(
            liveSnapshot: { throw CancellationError() }, renew: { $0 }, fetch: { _ in body }, signIn: { _ in }
        )), codexLogins: CodexLoginAppAdapter())

        try await #require(store.reloadClaudeLogins()).value
        try await #require(store.refreshClaudeUsage()).value

        guard case .usage(let alpha) = store.claudeUsage["alpha"] else { Issue.record("no usage for alpha"); return }
        #expect(alpha.windows.first?.usedPercent == 12)
    }

    @Test("Usage is fetched only when the window opens, at most every 30 seconds, and never after a switch")
    func usageFetchesOnlyOnOpen() async throws {
        let backend = try SavedLoginBackend(betaUsable: true)
        let counter = FetchCounter()
        let body = Data(#"{"five_hour":{"utilization":1.0,"resets_at":null}}"#.utf8)
        let store = ControlStore(claudeLogins: ClaudeLoginAppAdapter(makeBackend: { backend }, services: .init(
            liveSnapshot: { throw CancellationError() }, renew: { $0 }, fetch: { _ in counter.count += 1; return body }, signIn: { _ in }
        )), codexLogins: CodexLoginAppAdapter())
        let opened = Date()

        store.windowOpened(now: opened)
        while store.isLoadingClaudeUsage || store.claudeActivity != .idle { await Task.yield() }
        let afterOpen = counter.count
        store.windowOpened(now: opened.addingTimeInterval(10))
        while store.claudeActivity != .idle { await Task.yield() }
        try await #require(store.selectClaudeLogin("beta")).value
        #expect(!store.isLoadingClaudeUsage)
        #expect(counter.count == afterOpen)
        #expect(afterOpen == 2)

        store.windowOpened(now: opened.addingTimeInterval(31))
        while store.isLoadingClaudeUsage || store.claudeActivity != .idle { await Task.yield() }
        #expect(counter.count == afterOpen + 2)
    }

    @Test("With refresh on, an open window reloads usage every interval; closed or off, it never does")
    func periodicRefreshWhileOpen() async throws {
        let backend = try SavedLoginBackend(betaUsable: true)
        let counter = FetchCounter()
        let body = Data(#"{"five_hour":{"utilization":1.0,"resets_at":null}}"#.utf8)
        var settings = AIControlSettings()
        settings.refresh.enabled = true
        settings.refresh.intervalSeconds = 600
        let store = ControlStore(claudeLogins: ClaudeLoginAppAdapter(makeBackend: { backend }, services: .init(
            liveSnapshot: { throw CancellationError() }, renew: { $0 }, fetch: { _ in counter.count += 1; return body }, signIn: { _ in }
        )), codexLogins: CodexLoginAppAdapter(), settings: { settings })
        let opened = Date()

        store.windowOpened(now: opened)
        while store.isLoadingClaudeUsage || store.claudeActivity != .idle { await Task.yield() }
        let afterOpen = counter.count
        #expect(!store.refreshDue(now: opened.addingTimeInterval(599)))
        #expect(store.tick(now: opened.addingTimeInterval(599)) == false)
        #expect(store.refreshDue(now: opened.addingTimeInterval(600)))
        #expect(store.tick(now: opened.addingTimeInterval(600)))
        #expect(!store.refreshDue(now: opened.addingTimeInterval(601)), "a load is in progress")
        while store.isLoadingClaudeUsage { await Task.yield() }
        #expect(counter.count == afterOpen * 2)

        store.windowClosed()
        #expect(!store.refreshDue(now: opened.addingTimeInterval(5000)))
        settings.refresh.enabled = false
        store.windowOpened(now: opened.addingTimeInterval(5000))
        while store.isLoadingClaudeUsage || store.claudeActivity != .idle { await Task.yield() }
        #expect(!store.refreshDue(now: opened.addingTimeInterval(9000)))
    }

    @Test("Periodic refresh waits while a switch runs and never goes below 300 seconds")
    func periodicRefreshWaitsForActions() async throws {
        let backend = try SavedLoginBackend(betaUsable: true)
        var settings = AIControlSettings()
        settings.refresh.enabled = true
        let store = ControlStore(claudeLogins: ClaudeLoginAppAdapter(makeBackend: { backend }, services: .init(
            liveSnapshot: { throw CancellationError() }, renew: { $0 }, fetch: { _ in throw CancellationError() }, signIn: { _ in }
        )), codexLogins: CodexLoginAppAdapter(), settings: { settings })
        let opened = Date()
        store.windowOpened(now: opened)
        while store.isLoadingClaudeUsage || store.claudeActivity != .idle { await Task.yield() }
        #expect(!store.refreshDue(now: opened.addingTimeInterval(299)))
        let switching = try #require(store.selectClaudeLogin("beta"))
        #expect(!store.refreshDue(now: opened.addingTimeInterval(1000)), "a switch is running")
        await switching.value
        #expect(store.refreshDue(now: opened.addingTimeInterval(1000)))
    }

    @Test("A timer refresh that falls during an in-flight monitor load is deferred, not lost")
    func timerWaitsForInFlightMonitors() async {
        let gate = MonitorFetchGate()
        let source = UsageMonitors(environment: ["OPENCODE_AUTH_CONTENT": #"{"opencode-go":{"type":"api","key":"synthetic"}}"#,
                                                 "NAN_API_KEY": "synthetic"],
                                   readFile: { _ in Issue.record("Unexpected login file access"); return Data() },
                                   fetch: { request in await gate.fetch(request) }, now: Date.init)
        var settings = AIControlSettings()
        settings.refresh.enabled = true
        let store = ControlStore(claudeLogins: ClaudeLoginAppAdapter(), codexLogins: CodexLoginAppAdapter(),
                                 monitors: source, settings: { settings })
        let opened = Date()
        store.windowOpened(now: opened)
        await gate.waitForFirstRequest()
        #expect(store.isLoadingMonitors)
        #expect(!store.tick(now: opened.addingTimeInterval(400)), "the first load is still in flight")
        await gate.releaseFirstRequest()
        while store.isLoadingMonitors { await Task.yield() }
        let beforeTimer = await gate.count
        #expect(store.tick(now: opened.addingTimeInterval(415)), "the next tick runs the deferred refresh")
        while store.isLoadingMonitors { await Task.yield() }
        #expect(await gate.count > beforeTimer)
    }

    @Test("The screenshot demo never refreshes on a timer")
    func demoNeverTicks() {
        let store = ControlStore.demo()
        store.windowOpened()
        #expect(!store.refreshDue(now: Date().addingTimeInterval(100_000)))
    }

    @Test("Renaming and adding report their outcome and reload the list")
    func renameAndAddReportOutcome() async throws {
        let backend = try SavedLoginBackend(betaUsable: true)
        var signIns: [String?] = []
        let store = ControlStore(claudeLogins: ClaudeLoginAppAdapter(makeBackend: { backend }, services: .init(
            liveSnapshot: { throw CancellationError() }, renew: { $0 }, fetch: { _ in Data() },
            signIn: { signIns.append($0); throw CancellationError() }
        )), codexLogins: CodexLoginAppAdapter())
        try await #require(store.reloadClaudeLogins()).value

        let add = try #require(store.addClaudeLogin(name: "gamma", email: "g@example.com"))
        #expect(store.claudeActivity == .signingIn)
        #expect(store.renameClaudeLogin("alpha", to: "omega") == nil)
        await add.value
        #expect(signIns == ["g@example.com"])
        #expect(store.claudeNotice?.text == "Sign-in did not finish; nothing was saved.")

        try await #require(store.renameClaudeLogin("alpha", to: "omega")).value
        #expect(store.claudeNotice?.text == "Renamed alias alpha to omega.")
        if case .loaded(let state) = store.claudeLogins { #expect(state.aliases.map(\.name) == ["beta", "omega"]) }
        else { Issue.record("list not reloaded") }
    }

    @Test("Provider icons come from installed apps, fall back to monograms, and never appear in the demo")
    func providerIconsComeFromInstalledApps() {
        let store = ControlStore(
            claudeLogins: ClaudeLoginAppAdapter(), codexLogins: CodexLoginAppAdapter(),
            appIcon: { $0 == .claude ? NSImage(size: NSSize(width: 8, height: 8)) : nil }
        )
        #expect(store.providerIcons[.claude] != nil)
        #expect(store.providerIcons[.codex] == nil)
        #expect(ControlStore.demo().providerIcons.isEmpty)
        #expect(CLIProvider.claude.appBundleIdentifiers == ["com.anthropic.claudefordesktop"])
        #expect(CLIProvider.codex.appBundleIdentifiers == ["com.openai.codex", "com.openai.chat"])
    }

    @Test("The screenshot demo shows only example accounts and never loads real logins")
    func demoStoreIsExampleOnly() async {
        let store = ControlStore.demo()
        store.windowOpened()
        #expect(store.claudeActivity == .idle && store.codexActivity == .idle)
        #expect(!store.isLoadingClaudeUsage && !store.isLoadingCodexUsage)
        guard case .loaded(let codex) = store.codexLogins else { Issue.record("demo has no Codex logins"); return }
        #expect(codex.logins.allSatisfy { $0.email?.hasSuffix("@example.com") == true })
    }

    @Test("The menu-bar warning appears only when Claude needs recovery, never for mock Codex data")
    func menuWarningTracksClaudeRecovery() async throws {
        let store = makeStore(claudeBackend: try SavedLoginBackend(
            betaUsable: true, selectionError: ClaudeLoginEnvelopeError.recoveryRequired
        ))
        try await #require(store.reloadClaudeLogins()).value
        #expect(store.showsMenuWarning == false)

        try await #require(store.selectClaudeLogin("beta")).value
        #expect(store.showsMenuWarning)

        try await #require(store.recoverClaudeLogins()).value
        #expect(store.showsMenuWarning == false)
    }
}

private actor MonitorFetchGate {
    private(set) var count = 0
    private var firstRequest: CheckedContinuation<Void, Never>?
    private var firstResponse: CheckedContinuation<Void, Never>?

    func waitForFirstRequest() async {
        if count > 0 { return }
        await withCheckedContinuation { firstRequest = $0 }
    }

    func releaseFirstRequest() {
        firstResponse?.resume()
        firstResponse = nil
    }

    func fetch(_ request: URLRequest) async -> (Int, Data) {
        count += 1
        if count == 1 {
            firstRequest?.resume()
            firstRequest = nil
            await withCheckedContinuation { firstResponse = $0 }
        }
        if request.url?.host == "opencode.ai" {
            return (200, Data(#"{"usage":{"rolling":{"percent":42}}}"#.utf8))
        }
        return (200, Data(#"{"totals":{"by_model":[{"model":"deepseek-v4-flash","total_tokens":1200000000}]}}"#.utf8))
    }
}

private func codexStoreAuth(account: String, email: String) throws -> Data {
    let payload = try JSONSerialization.data(withJSONObject: ["email": email]).base64EncodedString()
        .replacingOccurrences(of: "=", with: "").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
    return try JSONSerialization.data(withJSONObject: [
        "auth_mode": "chatgpt",
        "tokens": ["id_token": "h.\(payload).s", "access_token": "a", "refresh_token": "r", "account_id": account]
    ], options: [.sortedKeys])
}

/// Saved Codex logins `work`, `home`, and `spare`, with `home` in auth.json.
final class CodexStoreFixture: @unchecked Sendable {
    let directory: URL
    let work: Data
    let home: Data
    private let store = CodexStoreMemory()

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("codex-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        work = try codexStoreAuth(account: "acct-a", email: "a@example.com")
        home = try codexStoreAuth(account: "acct-b", email: "b@example.com")
        let spare = try codexStoreAuth(account: "acct-s", email: "s@example.com")
        store.data = try JSONEncoder().encode(CodexLoginState(logins: ["work": work, "home": home, "spare": spare]))
        live = home
    }

    var system: CodexLoginSystem {
        .init(
            authPath: directory.appendingPathComponent("auth.json").path, store: store,
            acquireLock: { [directory] in try ManagerFileLock.acquire(directory: directory.appendingPathComponent("lock").path) },
            keyringHoldsLogin: { false }
        )
    }

    var live: Data? {
        get { FileManager.default.contents(atPath: directory.appendingPathComponent("auth.json").path) }
        set { try? newValue?.write(to: directory.appendingPathComponent("auth.json")) }
    }

    func cleanup() { try? FileManager.default.removeItem(at: directory) }
}

private final class CodexStoreMemory: ClaudeLoginDataStore {
    var data: Data?
    func read() throws -> Data {
        guard let data else { throw IsolatedKeychainError.missing }
        return data
    }
    func create(data: Data) throws { self.data = data }
    func update(data: Data) throws { self.data = data }
}

private final class FetchCounter: @unchecked Sendable {
    var count = 0
}
#endif
