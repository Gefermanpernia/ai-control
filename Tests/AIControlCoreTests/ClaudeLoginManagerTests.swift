import Foundation
import Security
import Testing
@testable import AIControlCore

private final class RecordingClaudeLoginBackend: ClaudeLoginBackend {
    var state: ClaudeLoginState
    var current: ClaudeLoginSnapshot
    private(set) var loadCount = 0
    private(set) var currentCount = 0
    private(set) var savedStates: [ClaudeLoginState] = []

    init(state: ClaudeLoginState = .init(), current: ClaudeLoginSnapshot) {
        self.state = state
        self.current = current
    }

    func loadState() throws -> ClaudeLoginState {
        loadCount += 1
        return state
    }

    func currentSnapshot() throws -> ClaudeLoginSnapshot {
        currentCount += 1
        return current
    }

    func saveState(_ state: ClaudeLoginState) throws {
        self.state = state
        savedStates.append(state)
    }
}

struct ClaudeLoginManagerTests {
    private func snapshot(
        account: String,
        accessToken: String = "ACCESS",
        refreshToken: String = "REFRESH"
    ) throws -> ClaudeLoginSnapshot {
        try ClaudeLoginSnapshot.capture(
            secureRoot: #"{"claudeAiOauth":{"accessToken":"\#(accessToken)","refreshToken":"\#(refreshToken)"}}"#,
            configurationRoot: #"{"oauthAccount":{"accountUuid":"\#(account)"}}"#
        )
    }

    @Test("Scoped JSON rejects duplicate keys at any depth")
    func rejectsDuplicateKeys() {
        #expect(throws: ScopedJSON.Error.self) {
            try ScopedJSON(#"{"owned":{"token":"one","token":"two"}}"#)
        }
    }

    @Test("Scoped JSON rejects malformed input")
    func rejectsMalformedJSON() {
        #expect(throws: ScopedJSON.Error.self) {
            try ScopedJSON(#"{"owned":[1,]}"#)
        }
    }

    @Test("Replacing an owned field preserves unrelated bytes and large integers")
    func preservesUnownedRawJSON() throws {
        let original = #"{"sentinel":{"future":true},"huge":900719925474099312345,"owned":{"old":1}}"#
        let document = try ScopedJSON(original)

        let edited = try document.replacing(["owned": .value(#"{"new":2}"#)])

        #expect(edited == #"{"sentinel":{"future":true},"huge":900719925474099312345,"owned":{"new":2}}"#)
    }

    @Test("Scoped JSON distinguishes missing, null, and present fields")
    func distinguishesPresence() throws {
        let document = try ScopedJSON(#"{"nullField":null,"valueField":{"x":1}}"#)

        #expect(document.presence(of: "missingField") == .missing)
        #expect(document.presence(of: "nullField") == .null)
        #expect(document.presence(of: "valueField") == .value(#"{"x":1}"#))
    }

    @Test("Removing and adding owned fields leaves sentinels unchanged")
    func appliesOwnedPresenceWithoutTouchingSentinels() throws {
        let document = try ScopedJSON(#"{"sentinel":"keep","remove":7}"#)

        let edited = try document.replacing(["remove": .missing, "added": .null])

        #expect(edited == #"{"sentinel":"keep","added":null}"#)
    }

    @Test("Snapshot preserves opaque account and credential subtrees")
    func preservesOpaqueSnapshotSubtrees() throws {
        let snapshot = try ClaudeLoginSnapshot.capture(
            secureRoot: #"{"claudeAiOauth":{"accessToken":"SYNTHETIC","refreshToken":"ROTATED","future":900719925474099312345}}"#,
            configurationRoot: #"{"oauthAccount":{"accountUuid":"account-a","organizationUuid":"org-a","future":{"keep":true}}}"#
        )

        #expect(snapshot.claudeAiOauth == .value(#"{"accessToken":"SYNTHETIC","refreshToken":"ROTATED","future":900719925474099312345}"#))
        #expect(snapshot.oauthAccount == .value(#"{"accountUuid":"account-a","organizationUuid":"org-a","future":{"keep":true}}"#))
        #expect(snapshot.identity == ClaudeLoginIdentity(accountUUID: "account-a", organizationUUID: "org-a"))
        #expect(snapshot.usability == .usable)
    }

    @Test("Snapshot retains optional secure-field presence")
    func retainsOptionalSecureFieldPresence() throws {
        let snapshot = try ClaudeLoginSnapshot.capture(
            secureRoot: #"{"claudeAiOauth":{"accessToken":"A","refreshToken":"R"},"organizationUuid":null}"#,
            configurationRoot: #"{"oauthAccount":{"accountUuid":"account-a"}}"#
        )

        #expect(snapshot.organizationUUID == .null)
        #expect(snapshot.trustedDeviceToken == .missing)
    }

    @Test("Snapshot rejects disagreeing secure and account identities")
    func rejectsIdentityDisagreement() {
        #expect(throws: ClaudeLoginSnapshot.Error.self) {
            try ClaudeLoginSnapshot.capture(
                secureRoot: #"{"claudeAiOauth":{"accessToken":"A","refreshToken":"R"},"organizationUuid":"org-b"}"#,
                configurationRoot: #"{"oauthAccount":{"accountUuid":"account-a","organizationUuid":"org-a"}}"#
            )
        }
    }

    @Test("Dead credential markers require re-login without reviving tokens")
    func recognizesDeadCredentialMarkers() throws {
        let snapshot = try ClaudeLoginSnapshot.capture(
            secureRoot: #"{"claudeAiOauth":{"accessToken":"","refreshToken":"","expiresAt":0}}"#,
            configurationRoot: #"{"oauthAccount":{"accountUuid":"account-a"}}"#
        )

        #expect(snapshot.usability == .reLoginNeeded)
        #expect(snapshot.claudeAiOauth == .value(#"{"accessToken":"","refreshToken":"","expiresAt":0}"#))
    }

    @Test("Incomplete credential objects require re-login")
    func incompleteCredentialsRequireRelogin() throws {
        let snapshot = try ClaudeLoginSnapshot.capture(
            secureRoot: #"{"claudeAiOauth":{}}"#,
            configurationRoot: #"{"oauthAccount":{"accountUuid":"account-a"}}"#
        )

        #expect(snapshot.usability == .reLoginNeeded)
    }

    @Test("Equivalent numeric zero expiry forms require re-login", arguments: ["0.0", "-0", "0e0"])
    func equivalentZeroExpiryRequiresRelogin(_ zero: String) throws {
        let snapshot = try ClaudeLoginSnapshot.capture(
            secureRoot: #"{"claudeAiOauth":{"accessToken":"A","refreshToken":"R","expiresAt":\#(zero)}}"#,
            configurationRoot: #"{"oauthAccount":{"accountUuid":"account-a"}}"#
        )

        #expect(snapshot.usability == .reLoginNeeded)
    }

    @Test("No arguments selects GUI without constructing a backend")
    func noArgumentsSelectsGUIWithZeroBackendIO() {
        var backendCreations = 0
        var guiRuns = 0

        let exit = runClaudeLogins(arguments: [], makeBackend: {
            backendCreations += 1
            fatalError("Backend must not be constructed")
        }, output: { _ in }, runGUI: { guiRuns += 1 })

        #expect(exit == 0)
        #expect(backendCreations == 0)
        #expect(guiRuns == 1)
    }

    @Test("Malformed commands report usage with zero backend IO")
    func malformedCommandsPerformZeroBackendIO() {
        var backendCreations = 0
        var messages: [String] = []

        let exit = runClaudeLogins(arguments: ["claude-login", "save"], makeBackend: {
            backendCreations += 1
            fatalError("Backend must not be constructed")
        }, output: { messages.append($0) }, runGUI: {})

        #expect(exit == 2)
        #expect(backendCreations == 0)
        #expect(messages == ["Usage: AIControl claude-login save <alias> | list | use <alias> | rename <alias> <new-alias> | recover"])
    }

    @Test("Aliases with a trailing newline are rejected by commands and the envelope")
    func aliasesRejectTrailingNewline() throws {
        for command in ["save", "use"] {
            let exit = runClaudeLogins(arguments: ["claude-login", command, "alpha\n"], makeBackend: {
                fatalError("Backend must not be constructed")
            }, output: { _ in }, runGUI: {})
            #expect(exit == 2)
        }
        let state = ClaudeLoginState(snapshots: ["alpha\n": try snapshot(account: "a")])
        #expect(throws: ClaudeLoginEnvelopeError.invalid) { try ClaudeLoginEnvelopeCodec().encode(state) }
    }

    @Test("Rename moves a saved login and its last-selected mark without touching credentials")
    func renameMovesSavedLogin() throws {
        let alpha = try snapshot(account: "account-a")
        let backend = RecordingClaudeLoginBackend(
            state: .init(snapshots: ["alpha": alpha, "beta": try snapshot(account: "account-b")], activeAlias: "alpha"),
            current: try snapshot(account: "unused")
        )
        var messages: [String] = []
        func run(_ arguments: String...) -> Int32 {
            runClaudeLogins(arguments: ["claude-login"] + arguments, makeBackend: { backend }, output: { messages.append($0) }, runGUI: {})
        }

        #expect(run("rename", "alpha", "gamma") == 0)
        #expect(backend.state.snapshots["gamma"] == alpha && backend.state.snapshots["alpha"] == nil)
        #expect(backend.state.activeAlias == "gamma")
        #expect(backend.currentCount == 0)
        #expect(run("rename", "gamma", "beta") == 3)
        #expect(run("rename", "missing", "delta") == 3)
        #expect(run("rename", "gamma", "Bad") == 2)
        #expect(backend.savedStates.count == 1)
        #expect(messages == [
            "Renamed alias alpha to gamma.", "Blocked: alias beta is already saved.", "Blocked: alias is not saved.",
            "Usage: AIControl claude-login save <alias> | list | use <alias> | rename <alias> <new-alias> | recover"
        ])
    }

    @Test("Checkpoint re-saves the live login under its own alias and never saves an unknown one")
    func checkpointReSavesLiveLogin() throws {
        let saved = try snapshot(account: "account-b", accessToken: "B1")
        let renewed = try snapshot(account: "account-b", accessToken: "B2")
        let backend = RecordingClaudeLoginBackend(
            state: .init(snapshots: ["alpha": try snapshot(account: "account-a"), "beta": saved], activeAlias: "alpha"),
            current: renewed
        )
        var messages: [String] = []
        func run() -> Int32 {
            runClaudeLogins(arguments: ["claude-login", "checkpoint"], makeBackend: { backend }, output: { messages.append($0) }, runGUI: {})
        }

        #expect(run() == 0)
        #expect(backend.state.snapshots["beta"] == renewed)
        #expect(backend.state.activeAlias == "alpha")
        backend.current = try snapshot(account: "account-c")
        #expect(run() == 0)
        #expect(backend.savedStates.count == 1)
        #expect(messages == ["Re-saved beta.", "The current Claude login is not saved; nothing to re-save."])
    }

    @Test("Manual second login enrollment ignores a stale active marker")
    func enrollsDistinctSecondLoginWithoutOverwritingFirst() throws {
        let first = try snapshot(account: "account-a", accessToken: "A")
        let second = try snapshot(account: "account-b", accessToken: "B")
        let backend = RecordingClaudeLoginBackend(current: first)
        var messages: [String] = []
        #expect(runClaudeLogins(arguments: ["claude-login", "save", "alpha"], makeBackend: { backend }, output: { messages.append($0) }, runGUI: {}) == 0)
        backend.current = second

        let exit = runClaudeLogins(arguments: ["claude-login", "save", "beta"], makeBackend: { backend }, output: { messages.append($0) }, runGUI: {})

        #expect(exit == 0)
        #expect(backend.state.snapshots["alpha"]?.identity == first.identity)
        #expect(backend.state.snapshots["beta"]?.identity == second.identity)
        #expect(backend.state.activeAlias == "alpha")
        #expect(messages.joined().contains("account-") == false)
        #expect(messages.joined().contains("ACCESS") == false)
    }

    @Test("Alias collision with another identity performs no write")
    func aliasCollisionPerformsNoWrite() throws {
        let first = try snapshot(account: "account-a")
        let second = try snapshot(account: "account-b")
        let backend = RecordingClaudeLoginBackend(
            state: .init(snapshots: ["alpha": first], activeAlias: "alpha"),
            current: second
        )

        let exit = runClaudeLogins(arguments: ["claude-login", "save", "alpha"], makeBackend: { backend }, output: { _ in }, runGUI: {})

        #expect(exit == 3)
        #expect(backend.savedStates.isEmpty)
    }

    @Test("A third alias is saved, and an alias beyond the limit is refused without persistence")
    func aliasLimitIsTen() throws {
        let backend = RecordingClaudeLoginBackend(
            state: .init(snapshots: ["alpha": try snapshot(account: "account-a"), "beta": try snapshot(account: "account-b")]),
            current: try snapshot(account: "account-c")
        )
        func save(_ alias: String) -> Int32 {
            runClaudeLogins(arguments: ["claude-login", "save", alias], makeBackend: { backend }, output: { _ in }, runGUI: {})
        }

        #expect(save("gamma") == 0)
        #expect(backend.state.snapshots.count == 3)
        for index in 4...10 {
            backend.current = try snapshot(account: "account-\(index)")
            #expect(save("alias\(index)") == 0)
        }
        backend.current = try snapshot(account: "account-11")
        #expect(save("alias11") == 3)
        #expect(backend.state.snapshots.count == 10)
        #expect(backend.savedStates.count == 8)
    }

    @Test("Unusable credentials are not enrolled")
    func unusableCredentialsAreNotEnrolled() throws {
        let dead = try snapshot(account: "account-a", accessToken: "")
        let backend = RecordingClaudeLoginBackend(current: dead)

        let exit = runClaudeLogins(arguments: ["claude-login", "save", "alpha"], makeBackend: { backend }, output: { _ in }, runGUI: {})

        #expect(exit == 5)
        #expect(backend.loadCount == 0)
        #expect(backend.savedStates.isEmpty)
    }

    @Test("Invalid aliases perform zero backend IO")
    func invalidAliasPerformsZeroBackendIO() {
        var backendCreations = 0

        let exit = runClaudeLogins(arguments: ["claude-login", "save", "INVALID"], makeBackend: {
            backendCreations += 1
            fatalError("Backend must not be constructed")
        }, output: { _ in }, runGUI: {})

        #expect(exit == 2)
        #expect(backendCreations == 0)
    }

    @Test("List emits aliases and states without reading current credentials")
    func listEmitsOnlySafeState() throws {
        let saved = try snapshot(account: "private-account", accessToken: "SECRET")
        let backend = RecordingClaudeLoginBackend(
            state: .init(snapshots: ["alpha": saved], activeAlias: "alpha"),
            current: saved
        )
        var messages: [String] = []

        let exit = runClaudeLogins(arguments: ["claude-login", "list"], makeBackend: { backend }, output: { messages.append($0) }, runGUI: {})

        #expect(exit == 0)
        #expect(backend.loadCount == 1)
        #expect(backend.currentCount == 0)
        #expect(messages == ["alpha: usable (active hint)"])
        #expect(messages.joined().contains("private-account") == false)
        #expect(messages.joined().contains("SECRET") == false)
    }

    @Test("Public use remains unavailable while recover enters the backend")
    func transactionCommandsRemainSafelyUnavailableByDefault() {
        var backendCreations = 0
        var messages: [String] = []

        let useExit = runClaudeLogins(arguments: ["claude-login", "use", "alpha"], makeBackend: {
            backendCreations += 1
            return RecordingClaudeLoginBackend(current: try! snapshot(account: "unused"))
        }, output: { messages.append($0) }, runGUI: {})
        let recoverExit = runClaudeLogins(arguments: ["claude-login", "recover"], makeBackend: {
            backendCreations += 1
            return RecordingClaudeLoginBackend(current: try! snapshot(account: "unused"))
        }, output: { messages.append($0) }, runGUI: {})

        #expect(useExit == 3)
        #expect(recoverExit == 3)
        #expect(backendCreations == 2)
        #expect(messages == ["Blocked: credential backend unavailable.", "Blocked: credential backend unavailable."])
    }

    @Test("Recovery restores pending owned fields from latest roots")
    func recoveryRestoresPendingOwnedFields() throws {
        let fixture = try SelectionFixture()
        defer { fixture.cleanup() }
        var expectedState = try fixture.preparePendingRecovery()
        let expectedOwnedFields = try #require(expectedState.journal?.before)
        expectedState.journal = nil

        #expect(fixture.runRecovery() == 0)
        #expect(fixture.resources.secureRoot == fixture.alpha2Secure)
        #expect(try ClaudeLoginOwnedFields.capture(.init(
            secure: fixture.resources.secureRoot, configuration: fixture.resources.configurationRoot
        )) == expectedOwnedFields)
        #expect(fixture.resources.configurationRoot.contains(#""sentinel":"keep","huge":900719925474099312345"#))
        #expect(try fixture.custody.load() == expectedState)
        #expect(fixture.messages == ["Recovered pending login switch."])
    }

    @Test("Recovery refuses third owned values without resource writes")
    func recoveryRefusesThirdOwnedValuesWithoutResourceWrites() throws {
        let fixture = try SelectionFixture()
        defer { fixture.cleanup() }
        _ = try fixture.preparePendingRecovery()
        fixture.resources.secureRoot = try ScopedJSON(fixture.resources.secureRoot).replacing([
            "trustedDeviceToken": .value(#""external""#)
        ])

        #expect(fixture.runRecovery() == 4)
        #expect(fixture.resources.events.isEmpty)
        #expect(try fixture.custody.loadRecoveryRecord().journal?.phase == .pending)
        #expect(fixture.messages == ["Recovery required; recovery did not complete."])
    }

    @Test("Recovery with no journal has no resource writes")
    func recoveryWithoutJournalIsSafe() throws {
        let fixture = try SelectionFixture()
        defer { fixture.cleanup() }
        let expectedState = try fixture.custody.load()

        #expect(fixture.runRecovery() == 0)
        #expect(try fixture.custody.load() == expectedState)
        #expect(fixture.resources.events.isEmpty)
        #expect(fixture.messages == ["Recovered pending login switch."])
    }

    @Test("Recovery clears a committed journal only after verifying owned after-images")
    func recoveryClearsVerifiedCommittedJournalWithoutResourceWrites() throws {
        let fixture = try SelectionFixture()
        defer { fixture.cleanup() }
        var expectedState = try fixture.preparePendingRecovery()
        expectedState.activeAlias = "beta"
        expectedState.journal?.phase = .committed
        try fixture.custody.save(expectedState, permitsJournal: true)
        let managerWrites = fixture.store.updateCount
        let expectedRoots = ClaudeLoginRoots(
            secure: fixture.resources.secureRoot,
            configuration: fixture.resources.configurationRoot
        )
        expectedState.journal = nil

        #expect(fixture.runRecovery() == 0)
        #expect(fixture.store.updateCount == managerWrites + 1)
        #expect(fixture.resources.secureRoot == expectedRoots.secure)
        #expect(fixture.resources.configurationRoot == expectedRoots.configuration)
        #expect(fixture.resources.events.isEmpty)
        #expect(try fixture.custody.load() == expectedState)
        #expect(fixture.messages == ["Recovered pending login switch."])
    }

    @Test("Committed recovery mismatch retains the journal without resource writes")
    func recoveryRetainsMismatchedCommittedJournalWithoutRollback() throws {
        let fixture = try SelectionFixture()
        defer { fixture.cleanup() }
        var committed = try fixture.preparePendingRecovery()
        committed.activeAlias = "beta"
        committed.journal?.phase = .committed
        try fixture.custody.save(committed, permitsJournal: true)
        fixture.resources.secureRoot = try ScopedJSON(fixture.resources.secureRoot).replacing([
            "trustedDeviceToken": .value(#""external""#)
        ])
        let managerWrites = fixture.store.updateCount
        let securePreimage = fixture.resources.secureRoot
        let configurationPreimage = fixture.resources.configurationRoot

        #expect(fixture.runRecovery() == 4)
        #expect(fixture.store.updateCount == managerWrites)
        #expect(fixture.resources.secureRoot == securePreimage)
        #expect(fixture.resources.configurationRoot == configurationPreimage)
        #expect(fixture.resources.events.isEmpty)
        #expect(try fixture.custody.loadRecoveryRecord() == committed)
        #expect(fixture.messages == ["Recovery required; recovery did not complete."])
    }

    @Test("Recovery refuses a root race without overwriting the external change")
    func recoveryRefusesRootRace() throws {
        let fixture = try SelectionFixture()
        defer { fixture.cleanup() }
        let pending = try fixture.preparePendingRecovery()
        let preimage = fixture.resources.secureRoot
        fixture.resources.changeBeforeSecureWrite = true

        #expect(fixture.runRecovery() == 4)
        #expect(fixture.resources.secureRoot == preimage + " ")
        #expect(fixture.resources.events.isEmpty)
        #expect(try fixture.custody.loadRecoveryRecord() == pending)
    }

    @Test("Recovery checks process safety immediately before every mutation", arguments: [3, 4, 5])
    func recoveryGuardsEveryMutation(failedCheck: Int) throws {
        let fixture = try SelectionFixture(failedProcessCheck: failedCheck)
        defer { fixture.cleanup() }
        let pending = try fixture.preparePendingRecovery()

        #expect(fixture.runRecovery() == 4)
        #expect(fixture.resources.events.count == (failedCheck - 3) * 2)
        #expect(try fixture.custody.loadRecoveryRecord() == pending)
        #expect(fixture.messages == ["Recovery required; recovery did not complete."])
    }

    @Test("Recovery holds its lock through real callbacks then releases and cleans only its owned directory")
    func recoveryOwnsLockAndCleanupBoundary() throws {
        let fixture = try SelectionFixture(verifyLockContention: true)
        let directory = fixture.directory
        _ = try fixture.preparePendingRecovery()
        let eventOffset = fixture.boundaryEvents.count

        #expect(fixture.runRecovery() == 0)
        #expect(Array(fixture.boundaryEvents.dropFirst(eventOffset)) == [
            "process-1", "manager-read", "process-2", "capture-roots", "replace-secure",
            "process-3", "read-roots", "replace-configuration", "process-4", "read-roots",
            "read-roots", "manager-read", "process-5", "manager-update", "manager-read",
            "manager-read", "process-6"
        ])
        fixture.cleanup()
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test("Recovery retains or truthfully reports journal state across readback and clear uncertainty", arguments: RecoveryCertaintyFailure.allCases)
    func recoveryFailureMatrix(testCase: RecoveryCertaintyFailure) throws {
        let fixture = try SelectionFixture(failure: testCase.selectionFailure)
        defer { fixture.cleanup() }
        _ = try fixture.preparePendingRecovery()
        testCase.arrange(fixture)

        #expect(fixture.runRecovery() == 4)
        let durable = testCase.retainsJournal
            ? try fixture.custody.loadRecoveryRecord()
            : try ClaudeLoginEnvelopeCodec().decode(fixture.store.data)
        #expect((durable.journal != nil) == testCase.retainsJournal)
        #expect(fixture.messages == ["Recovery required; recovery did not complete."])
    }

    @Test("Recovery distinguishes a missing manager item from existing journal-free state without creating either")
    func recoveryWithoutManagerItemDoesNotCreate() throws {
        for data in [nil, try ClaudeLoginEnvelopeCodec().encode(ClaudeLoginState())] as [Data?] {
            let directory = try disposableDirectory("recovery-empty")
            let store = MemoryClaudeLoginDataStore(data: data)
            let backend = commandBackend(directory: directory, store: store)

            #expect(runClaudeLogins(arguments: ["claude-login", "recover"], makeBackend: { backend }, output: { _ in }, runGUI: {}) == 0)
            #expect(store.createCount == 0)
            #expect(store.updateCount == 0)
            try FileManager.default.removeItem(at: directory)
        }
    }

    @Test("Recovery preserves unrelated bytes, presence, and large integers changed after preparation")
    func recoveryPreservesPostPreparationUnrelatedChanges() throws {
        let fixture = try SelectionFixture()
        defer { fixture.cleanup() }
        _ = try fixture.preparePendingRecovery()
        let external = #""sentinel" : "external","huge":999999999999999999999,"future":null"#
        fixture.resources.secureRoot = fixture.resources.secureRoot.replacingOccurrences(
            of: #""sentinel":"secure","huge":900719925474099312345"#, with: external
        )
        fixture.resources.configurationRoot = fixture.resources.configurationRoot.replacingOccurrences(
            of: #""sentinel":"keep","huge":900719925474099312345"#, with: external
        )

        #expect(fixture.runRecovery() == 0)
        #expect(fixture.resources.secureRoot.contains(external))
        #expect(fixture.resources.configurationRoot.contains(external))
    }

    @Test("A retained committed journal blocks subsequent selection")
    func retainedCommittedJournalBlocksSelection() throws {
        let fixture = try SelectionFixture()
        defer { fixture.cleanup() }
        var committed = try fixture.preparePendingRecovery()
        committed.activeAlias = "beta"
        committed.journal?.phase = .committed
        try fixture.custody.save(committed, permitsJournal: true)
        let managerWrites = fixture.store.updateCount
        let resourceReads = fixture.resources.readCount

        #expect(fixture.run(alias: "alpha") == 4)
        #expect(fixture.store.updateCount == managerWrites)
        #expect(fixture.resources.readCount == resourceReads)
        #expect(fixture.resources.events.isEmpty)
        #expect(try fixture.custody.loadRecoveryRecord() == committed)
        #expect(fixture.messages == ["Recovery required before selecting another alias."])
    }

    @Test("Confirmed journal absence allows a later guarded selection")
    func absentJournalAfterCleanupUncertaintyAllowsGuardedSelection() throws {
        let fixture = try SelectionFixture(failure: .clearReadback)
        defer { fixture.cleanup() }

        #expect(fixture.run(alias: "beta") == 3)
        #expect(try fixture.custody.load().journal == nil)
        #expect(fixture.messages == ["Blocked: selection applied but cleanup is uncertain."])
        let managerWrites = fixture.store.updateCount
        let resourceWrites = fixture.resources.events.count
        fixture.messages.removeAll()

        #expect(fixture.run(alias: "alpha") == 0)
        #expect(fixture.store.updateCount == managerWrites + 4)
        #expect(fixture.resources.events.count == resourceWrites + 4)
        #expect(try fixture.custody.load().activeAlias == "alpha")
        #expect(fixture.messages == ["Applied alias alpha."])
    }

    @Test("Use checkpoints the actual outgoing login before selecting the target")
    func useCheckpointsActualOutgoingLogin() throws {
        let fixture = try SelectionFixture()
        defer { fixture.cleanup() }
        var messages: [String] = []

        let exit = runClaudeLogins(
            arguments: ["claude-login", "use", "beta"], makeBackend: { fixture.backend },
            output: { messages.append($0) }, runGUI: {}
        )

        #expect(exit == 0)
        #expect(try fixture.custody.load().snapshots["alpha"] == fixture.alpha2)
        #expect(try fixture.custody.load().activeAlias == "beta")
        #expect(fixture.resources.secureRoot == fixture.betaSecure)
        #expect(fixture.resources.configurationRoot == fixture.betaConfiguration)
        #expect(messages == ["Applied alias beta."])
    }

    @Test("A2 to B to A restores exact presence and preserves unrelated JSON")
    func useRestoresLatestCheckpointAndPreservesUnownedFields() throws {
        let fixture = try SelectionFixture()
        defer { fixture.cleanup() }
        #expect(runClaudeLogins(
            arguments: ["claude-login", "use", "beta"], makeBackend: { fixture.backend },
            output: { _ in }, runGUI: {}
        ) == 0)

        #expect(runClaudeLogins(
            arguments: ["claude-login", "use", "alpha"], makeBackend: { fixture.backend },
            output: { _ in }, runGUI: {}
        ) == 0)

        #expect(fixture.resources.secureRoot == fixture.alpha2Secure)
        #expect(fixture.resources.configurationRoot == fixture.alpha2ConfigurationWithoutCaches)
        #expect(try fixture.custody.load().activeAlias == "alpha")
        #expect(fixture.resources.events == ["secure-write", "secure-readback", "configuration-write", "configuration-readback", "secure-write", "secure-readback", "configuration-write", "configuration-readback"])
    }

    @Test("Selection interruptions retain a readable pending journal", arguments: SelectionFailure.journalCases)
    func selectionFailureRetainsJournal(_ failure: SelectionFailure) throws {
        let fixture = try SelectionFixture(failure: failure)
        defer { fixture.cleanup() }
        var messages: [String] = []

        let exit = runClaudeLogins(
            arguments: ["claude-login", "use", "beta"], makeBackend: { fixture.backend },
            output: { messages.append($0) }, runGUI: {}
        )

        #expect(exit == 4)
        #expect(try fixture.custody.loadRecoveryRecord().journal?.phase == .pending)
        #expect(try fixture.custody.loadRecoveryRecord().activeAlias == "alpha")
        #expect(messages == ["Recovery required before selecting another alias."])
    }

    @Test("Unknown and dead targets refuse before resource writes")
    func selectionRefusesUnknownAndDeadTargets() throws {
        let fixture = try SelectionFixture(deadTarget: true)
        defer { fixture.cleanup() }
        var messages: [String] = []

        #expect(runClaudeLogins(
            arguments: ["claude-login", "use", "missing"], makeBackend: { fixture.backend },
            output: { messages.append($0) }, runGUI: {}
        ) == 3)
        #expect(runClaudeLogins(
            arguments: ["claude-login", "use", "beta"], makeBackend: { fixture.backend },
            output: { messages.append($0) }, runGUI: {}
        ) == 5)
        #expect(fixture.resources.events.isEmpty)
        #expect(messages == ["Blocked: alias is not saved.", "Re-login needed before selecting alias beta."])
    }

    @Test("Same-alias selection uses the checkpointed snapshot")
    func sameAliasSelectionUsesCheckpoint() throws {
        let fixture = try SelectionFixture()
        defer { fixture.cleanup() }
        var expectedState = try fixture.custody.load()
        expectedState.snapshots["alpha"] = fixture.alpha2

        #expect(fixture.run(alias: "alpha") == 0)
        #expect(fixture.resources.secureRoot == fixture.alpha2Secure)
        #expect(fixture.resources.configurationRoot == fixture.alpha2ConfigurationWithoutCaches)
        #expect(try fixture.custody.load() == expectedState)
        #expect(fixture.messages == ["Applied alias alpha."])
    }

    @Test("Selecting a dead outgoing alias checkpoints its exact presence without credential writes", arguments: DeadOutgoingCredentials.allCases)
    func deadOutgoingCheckpointRefusesSelection(_ credentials: DeadOutgoingCredentials) throws {
        let fixture = try SelectionFixture(deadOutgoing: credentials)
        defer { fixture.cleanup() }
        var expectedState = try fixture.custody.load()
        expectedState.snapshots["alpha"] = fixture.alpha2
        let securePreimage = fixture.resources.secureRoot
        let configurationPreimage = fixture.resources.configurationRoot
        let eventStart = fixture.boundaryEvents.count

        let result = fixture.run(alias: "alpha")
        let commandEvents = Array(fixture.boundaryEvents.dropFirst(eventStart))

        #expect(result == 5)
        #expect(try fixture.custody.load() == expectedState)
        #expect(fixture.store.updateCount == 1)
        #expect(fixture.resources.secureRoot == securePreimage)
        #expect(fixture.resources.configurationRoot == configurationPreimage)
        #expect(fixture.resources.events.isEmpty)
        #expect(fixture.messages == ["Re-login needed before selecting alias alpha."])
        #expect(commandEvents == [
            "manager-read", "process-1", "capture-roots", "manager-read", "process-2",
            "manager-update", "manager-read", "manager-read", "process-3"
        ])
    }

    @Test("A dead outgoing checkpoint permits selecting a distinct usable alias", arguments: DeadOutgoingCredentials.allCases)
    func deadOutgoingCheckpointPermitsDistinctTarget(_ credentials: DeadOutgoingCredentials) throws {
        let fixture = try SelectionFixture(deadOutgoing: credentials)
        defer { fixture.cleanup() }
        var expectedState = try fixture.custody.load()
        expectedState.snapshots["alpha"] = fixture.alpha2
        expectedState.activeAlias = "beta"

        #expect(fixture.run(alias: "beta") == 0)
        #expect(try fixture.custody.load() == expectedState)
        #expect(fixture.store.updateCount == 4)
        #expect(fixture.resources.secureRoot == credentials.expectedBetaSecure)
        #expect(fixture.resources.configurationRoot == fixture.betaConfiguration)
        #expect(fixture.resources.events == ["secure-write", "secure-readback", "configuration-write", "configuration-readback"])
        #expect(fixture.messages == ["Applied alias beta."])
    }

    @Test("Selection admission refuses malformed, ambiguous, unmatched, and duplicate controls without writes", arguments: SelectionAdmissionRefusal.allCases)
    func selectionAdmissionRefusesBeforeWrites(_ refusal: SelectionAdmissionRefusal) throws {
        let fixture = try SelectionFixture()
        defer { fixture.cleanup() }
        try refusal.arrange(fixture)
        let managerPreimage = fixture.store.data
        let securePreimage = fixture.resources.secureRoot
        let configurationPreimage = fixture.resources.configurationRoot

        #expect(fixture.run(alias: "beta") == 3)
        #expect(fixture.store.data == managerPreimage)
        #expect(fixture.store.updateCount == 0)
        #expect(fixture.resources.secureRoot == securePreimage)
        #expect(fixture.resources.configurationRoot == configurationPreimage)
        #expect(fixture.resources.events.isEmpty)
        #expect(fixture.messages == ["Blocked: credential backend unavailable."])
        #expect(fixture.boundaryEvents == refusal.expectedBoundaryEvents)
    }

    @Test("A valid outgoing refresh is the exact checkpoint before preparation refusal")
    func selectionPersistsExactCheckpointBeforePreparation() throws {
        let fixture = try SelectionFixture(failure: .prepareWrite)
        defer { fixture.cleanup() }
        var expectedState = try fixture.custody.load()
        expectedState.snapshots["alpha"] = fixture.alpha2
        let securePreimage = fixture.resources.secureRoot
        let configurationPreimage = fixture.resources.configurationRoot

        #expect(fixture.run(alias: "beta") == 3)
        #expect(try fixture.custody.load() == expectedState)
        #expect(fixture.store.updateCount == 2)
        #expect(fixture.resources.secureRoot == securePreimage)
        #expect(fixture.resources.configurationRoot == configurationPreimage)
        #expect(fixture.resources.events.isEmpty)
        #expect(fixture.messages == ["Blocked: credential backend unavailable."])
    }

    @Test("Unsupported account-bound roots refuse before checkpoint or credential writes", arguments: UnsupportedSelectionRoot.allCases)
    func unsupportedSelectionRootsRefuse(_ unsupported: UnsupportedSelectionRoot) throws {
        let fixture = try SelectionFixture(unsupportedRoot: unsupported)
        defer { fixture.cleanup() }

        #expect(fixture.run(alias: "beta") == 3)
        #expect(fixture.store.updateCount == 0)
        #expect(fixture.resources.events.isEmpty)
    }

    @Test("Recovery refuses unsupported account-bound roots without restoring", arguments: UnsupportedSelectionRoot.allCases)
    func recoveryRefusesUnsupportedRoots(_ unsupported: UnsupportedSelectionRoot) throws {
        let fixture = try SelectionFixture(unsupportedRoot: unsupported)
        defer { fixture.cleanup() }
        let pending = try fixture.preparePendingRecovery()
        let secure = fixture.resources.secureRoot
        let configuration = fixture.resources.configurationRoot

        #expect(fixture.runRecovery() == 4)
        #expect(fixture.resources.secureRoot == secure)
        #expect(fixture.resources.configurationRoot == configuration)
        #expect(try fixture.custody.loadRecoveryRecord() == pending)
    }

    @Test("Selection failures preserve exact phase images and stop later writes", arguments: SelectionFailure.allCases)
    func selectionFailureMatrix(_ failure: SelectionFailure) throws {
        let fixture = try SelectionFixture(failure: failure, verifyLockContention: true)
        defer { fixture.cleanup() }
        let eventStart = fixture.boundaryEvents.count

        let exit = fixture.run(alias: "beta")
        let commandEvents = Array(fixture.boundaryEvents.dropFirst(eventStart))
        let attemptedStates = try fixture.store.updatePayloads.map {
            try ClaudeLoginEnvelopeCodec().decodeRecoveryRecord($0)
        }
        let operationID = attemptedStates.dropFirst().first?.journal?.operationID
        let expectedStates = try fixture.expectedManagerStates(operationID: operationID)
        let durableState = try fixture.custody.loadRecoveryRecord()
        let expectedRoots = fixture.expectedResourceRoots(after: failure)

        #expect(exit == failure.expectedExit)
        #expect(fixture.store.updateCount == failure.expectedManagerWrites)
        #expect(attemptedStates == Array(expectedStates.dropFirst().prefix(failure.expectedManagerWrites)))
        #expect(durableState == expectedStates[failure.expectedDurableStateIndex])
        if let operationID {
            #expect(UUID(uuidString: operationID)?.uuidString == operationID)
            #expect(Set(attemptedStates.compactMap { $0.journal?.operationID }) == [operationID])
        }
        #expect(fixture.resources.secureRoot == expectedRoots.secure)
        #expect(fixture.resources.configurationRoot == expectedRoots.configuration)
        #expect(fixture.resources.events == failure.expectedResourceEvents)
        #expect(commandEvents == Array(fixture.expectedBoundaryEvents.prefix(failure.expectedBoundaryEventCount)))
        #expect(fixture.messages == [failure.expectedMessage])
    }

    @Test("Secure owned postimage is verified before configuration replacement", arguments: SelectionFailure.securePostimageCases)
    func securePostimagePrecedesConfiguration(_ failure: SelectionFailure) throws {
        let fixture = try SelectionFixture(failure: failure)
        defer { fixture.cleanup() }
        let configurationPreimage = fixture.resources.configurationRoot
        let eventStart = fixture.boundaryEvents.count

        let exit = fixture.run(alias: "beta")
        let commandEvents = Array(fixture.boundaryEvents.dropFirst(eventStart))

        #expect(exit == 4)
        #expect(fixture.resources.readCount == 3)
        #expect(fixture.resources.configurationRoot == configurationPreimage)
        #expect(fixture.resources.events == ["secure-write", "secure-readback"])
        #expect(!commandEvents.contains("replace-configuration"))
        #expect(commandEvents.suffix(3) == ["replace-secure", "process-6", "read-roots"])
        #expect(try fixture.custody.loadRecoveryRecord().journal?.phase == .pending)
        #expect(fixture.messages == ["Recovery required before selecting another alias."])
    }

    @Test("Command persistence records verified custody before an extra read fails", arguments: SelectionFailure.certaintyReadCases)
    func commandPersistenceCertaintyPrecedesExtraRead(_ failure: SelectionFailure) throws {
        let fixture = try SelectionFixture(failure: failure)
        defer { fixture.cleanup() }
        let eventStart = fixture.boundaryEvents.count

        let exit = fixture.run(alias: "beta")
        let commandEvents = Array(fixture.boundaryEvents.dropFirst(eventStart))

        #expect(exit == failure.expectedExit)
        #expect(fixture.store.readCount == failure.failedRead)
        #expect(fixture.store.updateCount == failure.expectedManagerWrites)
        #expect(commandEvents.last == "manager-read")
        #expect(try fixture.custody.loadRecoveryRecord().journal?.phase == failure.expectedPhase)
        #expect(fixture.messages == [failure.expectedMessage])
    }

    @Test("Direct persistence records verified custody before its postguard fails", arguments: DirectPersistenceCertaintyFailure.allCases)
    func directPersistenceCertaintyPrecedesPostguard(_ failure: DirectPersistenceCertaintyFailure) throws {
        let fixture = try SelectionFixture(failedProcessCheck: failure.failedCheck)
        defer { fixture.cleanup() }
        let eventStart = fixture.boundaryEvents.count

        let exit = fixture.runDirect(alias: "beta")
        let commandEvents = Array(fixture.boundaryEvents.dropFirst(eventStart))

        #expect(exit == failure.expectedExit)
        #expect(fixture.store.updateCount == failure.expectedManagerWrites)
        #expect(commandEvents.last == "process-\(failure.failedCheck)")
        #expect(try fixture.custody.loadRecoveryRecord().journal?.phase == failure.expectedPhase)
        #expect(fixture.messages == [failure.expectedMessage])
    }

    @Test("Selection fixture cleans owned lock directories on normal, throwing, and initialization-failure paths")
    func selectionFixtureLifecycle() throws {
        var normalDirectory: URL?
        do {
            let fixture = try SelectionFixture()
            normalDirectory = fixture.directory
            #expect(fixture.run(alias: "missing") == 3)
            fixture.cleanup()
        }
        #expect(normalDirectory.map { !FileManager.default.fileExists(atPath: $0.path) } == true)

        var throwingDirectory: URL?
        #expect(throws: FixtureError.self) {
            let fixture = try SelectionFixture()
            throwingDirectory = fixture.directory
            defer { fixture.cleanup() }
            #expect(fixture.run(alias: "missing") == 3)
            throw FixtureError()
        }
        #expect(throwingDirectory.map { !FileManager.default.fileExists(atPath: $0.path) } == true)

        var initializationDirectory: URL?
        #expect(throws: FixtureError.self) {
            _ = try SelectionFixture(
                failInitialization: true,
                onDirectoryOwned: { initializationDirectory = $0 }
            )
        }
        #expect(initializationDirectory.map { !FileManager.default.fileExists(atPath: $0.path) } == true)
    }

    @Test("Actual use command holds its lock across selection callbacks and releases it for every outcome")
    func useCommandHoldsAndReleasesSelectionLock() throws {
        let success = try SelectionFixture(verifyLockContention: true)
        defer { success.cleanup() }
        #expect(success.run(alias: "beta") == 0)
        #expect(success.boundaryEvents.contains("capture-roots"))
        #expect(success.boundaryEvents.contains("manager-update"))
        #expect(success.boundaryEvents.contains("read-roots"))
        #expect(success.boundaryEvents.contains("replace-secure"))
        #expect(success.boundaryEvents.contains("replace-configuration"))
        #expect(success.boundaryEvents.contains("process-12"))
        success.cleanup()

        let refusal = try SelectionFixture(verifyLockContention: true)
        defer { refusal.cleanup() }
        #expect(refusal.run(alias: "missing") == 3)
        #expect(refusal.boundaryEvents == ["manager-read"])
        refusal.cleanup()

        let throwing = try SelectionFixture(failure: .secureWrite, verifyLockContention: true)
        defer { throwing.cleanup() }
        #expect(throwing.run(alias: "beta") == 4)
        #expect(throwing.boundaryEvents.contains("replace-secure"))
        #expect(!throwing.boundaryEvents.contains("replace-configuration"))
        #expect(!throwing.boundaryEvents.contains("process-8"))
        throwing.cleanup()
    }

    @Test("Selection process faults bound writes and forbid later command callbacks", arguments: SelectionGuardFailure.allCases)
    func selectionGuardFaultsBoundWrites(_ failure: SelectionGuardFailure) throws {
        let fixture = try SelectionFixture(guardFailure: failure)
        defer { fixture.cleanup() }
        let managerPreimage = fixture.store.data
        let securePreimage = fixture.resources.secureRoot
        let configurationPreimage = fixture.resources.configurationRoot

        #expect(fixture.run(alias: "beta") == failure.expectedExit)
        let operationEvents = fixture.boundaryEvents
        #expect(fixture.store.updateCount == failure.expectedManagerWrites)
        #expect(fixture.resources.events == failure.expectedResourceEvents)
        #expect((fixture.store.data == managerPreimage) == failure.preservesManagerPreimage)
        #expect((fixture.resources.secureRoot == securePreimage) == failure.preservesSecurePreimage)
        #expect((fixture.resources.configurationRoot == configurationPreimage) == failure.preservesConfigurationPreimage)
        #expect(operationEvents == failure.expectedBoundaryEvents)
        #expect(try fixture.custody.loadRecoveryRecord().journal?.phase == failure.expectedPhase)
        fixture.cleanup()
    }

    @Test("Envelope v1 round trips two opaque presence-aware snapshots")
    func envelopeRoundTripsOpaqueSnapshots() throws {
        let alpha = try ClaudeLoginSnapshot.capture(
            secureRoot: #"{"claudeAiOauth":{"accessToken":"A","refreshToken":"R","future":900719925474099312345,"escaped":"quote:\" path:\\end"},"organizationUuid":null}"#,
            configurationRoot: #"{"oauthAccount":{"accountUuid":"account-a","future":{"keep":true}}}"#
        )
        let state = ClaudeLoginState(
            snapshots: ["alpha": alpha, "beta": try snapshot(account: "account-b", accessToken: "B")],
            activeAlias: "alpha"
        )
        let codec = ClaudeLoginEnvelopeCodec(maxBytes: 4_096)

        let decoded = try codec.decode(codec.encode(state))

        #expect(decoded == state)
        #expect(decoded.snapshots["alpha"]?.organizationUUID == .null)
        #expect(decoded.snapshots["alpha"]?.trustedDeviceToken == .missing)
        #expect(decoded.snapshots["alpha"]?.claudeAiOauth == alpha.claudeAiOauth)
    }

    @Test("Serialized envelope accepts absent and null journals without changing state")
    func envelopeAcceptsNoPendingJournal() throws {
        let codec = ClaudeLoginEnvelopeCodec()
        let absent = try serializedEnvelope()
        let null = try serializedEnvelope(journal: "null")

        #expect(try codec.decode(absent) == codec.decode(null))
        #expect(try codec.decode(null).activeAlias == "alpha")
    }

    @Test("Value-tagged raw null is invalid while explicit null remains valid")
    func envelopePreservesNullPresenceSemantics() throws {
        let codec = ClaudeLoginEnvelopeCodec()
        let disguisedNull = try serializedEnvelope(entries: [("alpha", try serializedSnapshot(
            usability: "reLoginNeeded", credentialPresence: #"{"kind":"value","value":"null"}"#
        ))])
        #expect(throws: ClaudeLoginEnvelopeError.invalid) { try codec.decode(disguisedNull) }

        let explicitNull = try serializedEnvelope(entries: [("alpha", try serializedSnapshot(
            usability: "reLoginNeeded", credentialPresence: #"{"kind":"null","value":null}"#
        ))])
        #expect(try codec.decode(explicitNull).snapshots["alpha"]?.claudeAiOauth == .null)
    }

    @Test("Encoding enforces the configured outer envelope depth")
    func envelopeEncodeEnforcesOuterDepth() throws {
        let state = ClaudeLoginState(
            snapshots: ["alpha": try snapshot(account: "account-a")], activeAlias: "alpha"
        )

        #expect(throws: ClaudeLoginEnvelopeError.invalid) {
            try ClaudeLoginEnvelopeCodec(maxDepth: 3).encode(state)
        }
        let codec = ClaudeLoginEnvelopeCodec(maxDepth: 4)
        #expect(try codec.decode(codec.encode(state)) == state)
    }

    @Test("Serialized journal round trips exact images with a stale pending marker")
    func journalRoundTripsExactImages() throws {
        let roots = ClaudeLoginRoots(
            secure: #"{"claudeAiOauth":{"accessToken":"A","refreshToken":"R"},"organizationUuid":null,"sentinel":900719925474099312345}"#,
            configuration: #"{"oauthAccount":{"accountUuid":"account-a"},"modelAccessCache":{"opaque":900719925474099312345},"sentinel":"keep"}"#
        )
        let alpha = try ClaudeLoginSnapshot.capture(
            secureRoot: roots.secure, configurationRoot: roots.configuration
        )
        let beta = try ClaudeLoginSnapshot.capture(
            secureRoot: #"{"claudeAiOauth":{"accessToken":"B","refreshToken":"RB"},"organizationUuid":"org-b"}"#,
            configurationRoot: #"{"oauthAccount":{"accountUuid":"account-b","organizationUuid":"org-b"}}"#
        )
        let journal = ClaudeLoginJournal(
            operationID: "4C944252-7F44-4F2A-8866-0F45B26A39AE", source: "alpha", target: "beta",
            before: try ClaudeLoginOwnedFields.capture(roots), after: .target(beta), phase: .pending
        )
        let state = ClaudeLoginState(
            snapshots: ["alpha": alpha, "beta": beta], activeAlias: "beta", journal: journal
        )
        let codec = ClaudeLoginEnvelopeCodec()

        let encoded = try codec.encode(state)

        #expect(try codec.decodeRecoveryRecord(encoded) == state)
        #expect(String(decoding: encoded, as: UTF8.self).contains("900719925474099312345"))
        #expect(throws: ClaudeLoginEnvelopeError.tooLarge) {
            try ClaudeLoginEnvelopeCodec(maxBytes: encoded.count - 1).decodeRecoveryRecord(encoded)
        }
        #expect(throws: ClaudeLoginEnvelopeError.tooLarge) {
            try ClaudeLoginEnvelopeCodec(maxBytes: encoded.count - 1).decode(encoded)
        }
        #expect(throws: ClaudeLoginEnvelopeError.invalid) {
            try ClaudeLoginEnvelopeCodec(maxDepth: 3).decodeRecoveryRecord(encoded)
        }
        #expect(throws: ClaudeLoginEnvelopeError.invalid) {
            try ClaudeLoginEnvelopeCodec(maxDepth: 3).decode(encoded)
        }
    }

    @Test("Journal encode validates cache raw values consistently with recovery decode")
    func journalEncodeValidatesCacheRawValues() throws {
        let alpha = try snapshot(account: "account-a", accessToken: "A", refreshToken: "R")
        let beta = try snapshot(account: "account-b", accessToken: "B", refreshToken: "RB")
        let captured = try ClaudeLoginOwnedFields.capture(.init(
            secure: #"{"claudeAiOauth":{"accessToken":"A","refreshToken":"R"}}"#,
            configuration: #"{"oauthAccount":{"accountUuid":"account-a"}}"#
        ))
        let codec = ClaudeLoginEnvelopeCodec(maxDepth: 8)
        let state: (JSONPresence) -> ClaudeLoginState = { presence in
            var configuration = captured.configuration
            configuration["modelAccessCache"] = presence
            return .init(snapshots: ["alpha": alpha, "beta": beta], activeAlias: "alpha", journal: .init(
                operationID: "4C944252-7F44-4F2A-8866-0F45B26A39AE", source: "alpha", target: "beta",
                before: .init(secure: captured.secure, configuration: configuration),
                after: .target(beta), phase: .pending
            ))
        }

        #expect(throws: ClaudeLoginEnvelopeError.invalid) { try codec.encode(state(.value("{"))) }
        #expect(throws: ClaudeLoginEnvelopeError.invalid) { try codec.encode(state(.value("null"))) }
        let tooDeep = String(repeating: #"{"level":"#, count: 9) + "0" + String(repeating: "}", count: 9)
        #expect(throws: ClaudeLoginEnvelopeError.invalid) {
            try codec.encode(state(.value(tooDeep)))
        }
        let explicitNull = state(.null)
        #expect(try codec.decodeRecoveryRecord(codec.encode(explicitNull)) == explicitNull)
    }

    @Test("Serialized journal rejects inconsistent operation, images, and committed marker")
    func journalRejectsInconsistentState() throws {
        let alpha = try snapshot(account: "account-a", accessToken: "A", refreshToken: "R")
        let beta = try snapshot(account: "account-b")
        let before = try ClaudeLoginOwnedFields.capture(.init(
            secure: #"{"claudeAiOauth":{"accessToken":"A","refreshToken":"R"}}"#,
            configuration: #"{"oauthAccount":{"accountUuid":"account-a"}}"#
        ))
        let valid = ClaudeLoginJournal(
            operationID: "4C944252-7F44-4F2A-8866-0F45B26A39AE", source: "alpha", target: "beta",
            before: before, after: .target(beta), phase: .pending
        )
        let codec = ClaudeLoginEnvelopeCodec()
        let state: (ClaudeLoginJournal, String?) -> ClaudeLoginState = { journal, marker in
            .init(snapshots: ["alpha": alpha, "beta": beta], activeAlias: marker, journal: journal)
        }

        #expect(throws: ClaudeLoginEnvelopeError.invalid) {
            try codec.encode(state(.init(
                operationID: "not-a-uuid", source: valid.source, target: valid.target,
                before: valid.before, after: valid.after, phase: valid.phase
            ), "alpha"))
        }
        #expect(throws: ClaudeLoginEnvelopeError.invalid) {
            try codec.encode(state(.init(
                operationID: valid.operationID, source: valid.source, target: valid.target,
                before: .target(beta), after: valid.after, phase: valid.phase
            ), "alpha"))
        }
        #expect(throws: ClaudeLoginEnvelopeError.invalid) {
            try codec.encode(state(.init(
                operationID: valid.operationID, source: valid.source, target: valid.target,
                before: valid.before, after: .target(alpha), phase: valid.phase
            ), "alpha"))
        }
        #expect(throws: ClaudeLoginEnvelopeError.invalid) {
            try codec.encode(state(.init(
                operationID: valid.operationID, source: valid.source, target: valid.target,
                before: valid.before, after: valid.after, phase: .committed
            ), "alpha"))
        }
    }

    @Test("Committed journal round trips cache preimages and cleared target caches")
    func committedJournalRoundTripsExactImages() throws {
        let (state, bytes) = try journalControl(phase: .committed, activeAlias: "beta")

        #expect(try ClaudeLoginEnvelopeCodec().decodeRecoveryRecord(bytes) == state)
        #expect(state.journal?.before.configuration["modelAccessCache"] == .value(#"{"large":900719925474099312345}"#))
        #expect(state.journal?.before.configuration["additionalModelOptionsCache"] == .null)
        #expect(state.journal?.after.configuration["modelAccessCache"] == .missing)
        #expect(state.journal?.after.configuration["additionalModelOptionsCache"] == .missing)
    }

    @Test("Hostile serialized journals fail closed from an admitted control", arguments: JournalSerializedAttack.allCases)
    func hostileSerializedJournalsFailClosed(_ attack: JournalSerializedAttack) throws {
        let (control, bytes) = try journalControl(phase: .pending, activeAlias: "alpha")
        let codec = ClaudeLoginEnvelopeCodec()

        #expect(try codec.decodeRecoveryRecord(bytes) == control)
        let hostileBytes = try attack.mutating(bytes)
        #expect(throws: ClaudeLoginEnvelopeError.invalid) {
            try codec.decodeRecoveryRecord(hostileBytes)
        }
    }

    private func journalControl(
        phase: ClaudeLoginJournalPhase, activeAlias: String
    ) throws -> (ClaudeLoginState, Data) {
        let roots = ClaudeLoginRoots(
            secure: #"{"claudeAiOauth":{"accessToken":"A","refreshToken":"R"},"organizationUuid":null}"#,
            configuration: #"{"oauthAccount":{"accountUuid":"account-a"},"additionalModelOptionsCache":null,"modelAccessCache":{"large":900719925474099312345}}"#
        )
        let alpha = try ClaudeLoginSnapshot.capture(secureRoot: roots.secure, configurationRoot: roots.configuration)
        let beta = try snapshot(account: "account-b", accessToken: "B", refreshToken: "RB")
        let state = ClaudeLoginState(
            snapshots: ["alpha": alpha, "beta": beta], activeAlias: activeAlias,
            journal: .init(
                operationID: "4C944252-7F44-4F2A-8866-0F45B26A39AE", source: "alpha", target: "beta",
                before: try .capture(roots), after: .target(beta), phase: phase
            )
        )
        return (state, try ClaudeLoginEnvelopeCodec().encode(state))
    }

    @Test("Serialized envelope rejects invalid state", arguments: UnsafeEnvelopeCase.allCases)
    func envelopeRejectsInvalidSerializedState(_ fixture: UnsafeEnvelopeCase) {
        #expect(throws: fixture.expectedError) {
            try ClaudeLoginEnvelopeCodec().decode(try fixture.data())
        }
    }

    @Test("Envelope rejects excessive outer nesting before recursive decoding")
    func envelopeRejectsExcessiveOuterDepth() throws {
        let deepValue = String(repeating: #"{"level":"#, count: 65) + "0" + String(repeating: "}", count: 65)

        #expect(throws: ClaudeLoginEnvelopeError.invalid) {
            try ClaudeLoginEnvelopeCodec().decode(try serializedEnvelope(extraMember: #""future":\#(deepValue)"#))
        }
    }

    @Test("Envelope rejects excessive nesting in embedded raw JSON")
    func envelopeRejectsExcessiveEmbeddedDepth() throws {
        let deepValue = String(repeating: #"{"level":"#, count: 65) + "0" + String(repeating: "}", count: 65)
        let credentials = #"{"accessToken":"A","refreshToken":"R","future":\#(deepValue)}"#

        #expect(throws: ClaudeLoginEnvelopeError.invalid) {
            try ClaudeLoginEnvelopeCodec().decode(try serializedEnvelope(credentials: credentials))
        }
    }

    @Test("Envelope v1 rejects malformed, oversized, future, and pending data")
    func envelopeRejectsUnsafeSerializedState() {
        #expect(throws: ClaudeLoginEnvelopeError.invalid) {
            try ClaudeLoginEnvelopeCodec().decode(Data(#"{"version":1,"version":1}"#.utf8))
        }
        #expect(throws: ClaudeLoginEnvelopeError.tooLarge) {
            try ClaudeLoginEnvelopeCodec(maxBytes: 64).decode(Data(repeating: 0x20, count: 65))
        }
        #expect(throws: ClaudeLoginEnvelopeError.unsupportedVersion) {
            try ClaudeLoginEnvelopeCodec().decode(Data(#"{"version":2,"snapshots":{},"activeAlias":null,"journal":null}"#.utf8))
        }
        #expect(throws: ClaudeLoginEnvelopeError.recoveryRequired) {
            try ClaudeLoginEnvelopeCodec().decode(Data(#"{"version":1,"snapshots":{},"activeAlias":null,"journal":{"operationID":"synthetic"}}"#.utf8))
        }
    }

    @Test("Manager custody creates once, updates data only, and verifies readback")
    func managerCustodyCreatesUpdatesAndReadsBack() throws {
        let store = MemoryClaudeLoginDataStore()
        let custody = ClaudeLoginCustody(store: store)
        let first = ClaudeLoginState(snapshots: ["alpha": try snapshot(account: "account-a")], activeAlias: "alpha")
        let second = ClaudeLoginState(snapshots: [
            "alpha": try snapshot(account: "account-a"),
            "beta": try snapshot(account: "account-b", accessToken: "B")
        ], activeAlias: "alpha")

        #expect(try custody.load() == ClaudeLoginState())
        try custody.save(first)
        try custody.save(second)

        #expect(store.createCount == 1)
        #expect(store.updateCount == 1)
        #expect(try custody.load() == second)
    }

    @Test("Manager custody refuses failed and mismatched readback")
    func managerCustodyRefusesUnsafeReadback() throws {
        let denied = MemoryClaudeLoginDataStore(readError: IsolatedKeychainError.denied)
        let corrupt = MemoryClaudeLoginDataStore(corruptAfterWrite: true)
        let state = ClaudeLoginState(snapshots: ["alpha": try snapshot(account: "account-a")], activeAlias: "alpha")

        #expect(throws: IsolatedKeychainError.denied) { try ClaudeLoginCustody(store: denied).load() }
        #expect(throws: ClaudeLoginEnvelopeError.readbackMismatch) { try ClaudeLoginCustody(store: corrupt).save(state) }
    }

    @Test("Manager custody validates existing state before updating")
    func managerCustodyValidatesExistingState() throws {
        let invalid = MemoryClaudeLoginDataStore(data: Data(#"{"version":1}"#.utf8))
        let pending = MemoryClaudeLoginDataStore(data: try serializedEnvelope(journal: #"{"phase":"pending"}"#))
        let state = ClaudeLoginState(snapshots: ["alpha": try snapshot(account: "account-a")], activeAlias: "alpha")

        #expect(throws: ClaudeLoginEnvelopeError.invalid) { try ClaudeLoginCustody(store: invalid).save(state) }
        #expect(invalid.createCount == 0)
        #expect(invalid.updateCount == 0)
        #expect(invalid.data == Data(#"{"version":1}"#.utf8))
        #expect(throws: ClaudeLoginEnvelopeError.recoveryRequired) { try ClaudeLoginCustody(store: pending).save(state) }
        #expect(pending.createCount == 0)
        #expect(pending.updateCount == 0)
    }

    @Test("Manager custody refuses unsafe initial reads", arguments: [
        IsolatedKeychainError.denied, .cancelled, .locked, .ambiguous, .corrupt
    ])
    func managerCustodyRefusesUnsafeInitialRead(error: IsolatedKeychainError) throws {
        let store = MemoryClaudeLoginDataStore(data: Data("preimage".utf8), readError: error)
        let state = ClaudeLoginState(snapshots: ["alpha": try snapshot(account: "account-a")], activeAlias: "alpha")

        #expect(throws: error) { try ClaudeLoginCustody(store: store).save(state) }
        #expect(store.createCount == 0)
        #expect(store.updateCount == 0)
        #expect(store.data == Data("preimage".utf8))
    }

    @Test("Manager custody never creates after an observed item disappears")
    func managerCustodyRefusesUpdateTimeMissing() throws {
        let initial = try serializedEnvelope()
        let store = MemoryClaudeLoginDataStore(data: initial, updateError: IsolatedKeychainError.missing)
        let state = ClaudeLoginState(snapshots: ["alpha": try snapshot(account: "account-a", accessToken: "new")], activeAlias: "alpha")

        #expect(throws: IsolatedKeychainError.missing) { try ClaudeLoginCustody(store: store).save(state) }
        #expect(store.readCount == 1)
        #expect(store.updateCount == 1)
        #expect(store.createCount == 0)
        #expect(store.data == initial)
    }

    @Test("Manager custody refuses update and readback failures without retrying")
    func managerCustodyRefusesWriteAndReadbackFailures() throws {
        let initial = try serializedEnvelope()
        let state = ClaudeLoginState(snapshots: ["alpha": try snapshot(account: "account-a", accessToken: "new")], activeAlias: "alpha")
        let updateFailure = MemoryClaudeLoginDataStore(
            data: initial, updateError: IsolatedKeychainError.denied, mutateBeforeUpdateError: true
        )
        let readbackFailure = MemoryClaudeLoginDataStore(data: initial, readbackError: IsolatedKeychainError.missing)
        let readbackMismatch = MemoryClaudeLoginDataStore(data: initial, corruptAfterWrite: true)

        #expect(throws: IsolatedKeychainError.denied) { try ClaudeLoginCustody(store: updateFailure).save(state) }
        #expect(updateFailure.createCount == 0)
        #expect(updateFailure.updateCount == 1)
        #expect(updateFailure.data != initial)
        #expect(throws: ClaudeLoginEnvelopeError.readbackMismatch) { try ClaudeLoginCustody(store: readbackFailure).save(state) }
        #expect(readbackFailure.readCount == 2)
        #expect(readbackFailure.createCount == 0)
        #expect(readbackFailure.updateCount == 1)
        #expect(throws: ClaudeLoginEnvelopeError.readbackMismatch) { try ClaudeLoginCustody(store: readbackMismatch).save(state) }
        #expect(readbackMismatch.readCount == 2)
        #expect(readbackMismatch.createCount == 0)
        #expect(readbackMismatch.updateCount == 1)
    }

    @Test("Guarded backend enrolls two identities and persists safe list state")
    func guardedBackendEnrollsAndReadsBack() throws {
        let store = MemoryClaudeLoginDataStore()
        var current = try snapshot(account: "account-a", accessToken: "A")
        let backend = GuardedClaudeLoginBackend(
            custody: ClaudeLoginCustody(store: store), processPreflight: safeProcessPreflight(),
            currentSnapshot: { current }
        )
        var messages: [String] = []

        #expect(runClaudeLogins(arguments: ["claude-login", "save", "alpha"], makeBackend: { backend }, output: { messages.append($0) }, runGUI: {}) == 0)
        current = try snapshot(account: "account-b", accessToken: "B")
        #expect(runClaudeLogins(arguments: ["claude-login", "save", "beta"], makeBackend: { backend }, output: { messages.append($0) }, runGUI: {}) == 0)
        #expect(runClaudeLogins(arguments: ["claude-login", "list"], makeBackend: { backend }, output: { messages.append($0) }, runGUI: {}) == 0)

        #expect(store.createCount == 1)
        #expect(store.updateCount == 1)
        #expect(messages.suffix(2) == ["alpha: usable (active hint)", "beta: usable"])
        #expect(messages.joined().contains("account-") == false)
    }

    @Test("Guarded backend refuses unsafe preflight before custody writes", arguments: [
        ([ClaudeProcessRecord(pid: 40, parentPID: 1, uid: 501, executablePath: "/synthetic/terminal", role: .terminal)], ClaudeProcessPreflightError.active),
        ([ClaudeProcessRecord(pid: 40, parentPID: 1, uid: nil, executablePath: nil, role: nil)], ClaudeProcessPreflightError.uncertain)
    ])
    func guardedBackendRefusesUnsafePreflightWithoutWrites(
        records: [ClaudeProcessRecord], expectedError: ClaudeProcessPreflightError
    ) throws {
        let store = MemoryClaudeLoginDataStore()
        let backend = GuardedClaudeLoginBackend(
            custody: ClaudeLoginCustody(store: store),
            processPreflight: .init(
                expectedUID: 501, trustedExecutablePath: "/synthetic/claude",
                probe: .init(snapshot: { records })
            ),
            currentSnapshot: { try self.snapshot(account: "account-a") }
        )
        let state = ClaudeLoginState(snapshots: ["alpha": try snapshot(account: "account-a")], activeAlias: "alpha")

        #expect(throws: expectedError) { try backend.saveState(state) }
        #expect(store.createCount == 0)
        #expect(store.updateCount == 0)
    }

    @Test("Command-scoped save holds one lock and orders routing, state, capture, mutation, and verification")
    func commandScopedSaveOrdersEveryGuard() throws {
        let directory = try disposableDirectory("command-save")
        defer { try? FileManager.default.removeItem(at: directory) }
        var events: [String] = []
        let store = MemoryClaudeLoginDataStore(event: {
            #expect(throws: ManagerFileLockError.contended) { try ManagerFileLock.acquire(directory: directory.path) }
            events.append($0)
        })
        let process = ClaudeProcessPreflight(
            expectedUID: geteuid(), trustedExecutablePath: "/synthetic/claude",
            probe: .init(snapshot: { store.event("process"); return [] })
        )
        let backend = CommandScopedClaudeLoginBackend(
            acquireLock: { events.append("lock"); return try ManagerFileLock.acquire(directory: directory.path) },
            routingEvidence: { events.append("route"); return .testing() },
            readCustody: { events.append("read-factory"); return ClaudeLoginCustody(store: store) },
            writeCustody: { route, guardMutation in
                events.append("write-factory:\(route.configurationPath)")
                return ClaudeLoginCustody(store: MutationGuardedDataStore(store, guardMutation))
            },
            processPreflight: process,
            currentSnapshot: { route in store.event("capture:\(route.service)"); return try self.snapshot(account: "account-a") }
        )
        var messages: [String] = []

        #expect(runClaudeLogins(arguments: ["claude-login", "save", "alpha"], makeBackend: { backend }, output: { messages.append($0) }, runGUI: {}) == 0)

        #expect(events == ["lock", "route", "write-factory:/synthetic/home/.claude.json", "manager-read", "process", "capture:Claude Code-credentials", "manager-read", "process", "manager-create", "manager-read", "manager-read", "process"])
        #expect(messages == ["Saved alias alpha."])
        let reacquired = try ManagerFileLock.acquire(directory: directory.path)
        reacquired.release()
    }

    @Test("Routing conflict refuses before manager or Claude IO and releases the lock")
    func commandScopedRoutingRefusesBeforeIO() throws {
        let directory = try disposableDirectory("command-route")
        var events: [String] = []
        let store = MemoryClaudeLoginDataStore(event: { events.append($0) })
        let backend = CommandScopedClaudeLoginBackend(
            acquireLock: { events.append("lock"); return try ManagerFileLock.acquire(directory: directory.path) },
            routingEvidence: { events.append("route"); return .testing(conflicts: [.customOAuth]) },
            readCustody: { events.append("read-factory"); return ClaudeLoginCustody(store: store) },
            writeCustody: { _, _ in events.append("write-factory"); return ClaudeLoginCustody(store: store) },
            processPreflight: safeProcessPreflight(),
            currentSnapshot: { _ in events.append("capture"); return try self.snapshot(account: "private-identity") }
        )
        var messages: [String] = []

        #expect(runClaudeLogins(arguments: ["claude-login", "save", "alpha"], makeBackend: { backend }, output: { messages.append($0) }, runGUI: {}) == 3)
        #expect(events == ["lock", "route"])
        #expect(messages == ["Blocked: credential backend unavailable."])
        let reacquired = try ManagerFileLock.acquire(directory: directory.path)
        reacquired.release()
        try FileManager.default.removeItem(at: directory)
        #expect(FileManager.default.fileExists(atPath: directory.path) == false)
    }

    @Test("Pending manager journal refuses before capture")
    func commandScopedJournalRefusesBeforeCapture() throws {
        let directory = try disposableDirectory("command-journal")
        var events: [String] = []
        let store = MemoryClaudeLoginDataStore(
            data: try serializedEnvelope(journal: #"{"phase":"pending"}"#), event: { events.append($0) }
        )
        let backend = commandBackend(directory: directory, store: store, event: { events.append($0) })

        var messages: [String] = []
        #expect(runClaudeLogins(arguments: ["claude-login", "save", "alpha"], makeBackend: { backend }, output: { messages.append($0) }, runGUI: {}) == 4)
        #expect(events == ["lock", "route", "write-factory", "manager-read"])
        #expect(messages == ["Recovery required before saving an alias."])
        let reacquired = try ManagerFileLock.acquire(directory: directory.path)
        reacquired.release()
        try FileManager.default.removeItem(at: directory)
        #expect(FileManager.default.fileExists(atPath: directory.path) == false)
    }

    @Test("Absent list reads manager state only without write-oriented setup")
    func commandScopedListReadsOnlyManagerState() throws {
        let directory = try disposableDirectory("command-list")
        defer { try? FileManager.default.removeItem(at: directory) }
        var events: [String] = []
        let store = MemoryClaudeLoginDataStore(event: { events.append($0) })
        let backend = commandBackend(directory: directory, store: store, event: { events.append($0) })
        var messages: [String] = []

        #expect(runClaudeLogins(arguments: ["claude-login", "list"], makeBackend: { backend }, output: { messages.append($0) }, runGUI: {}) == 0)
        #expect(events == ["read-factory", "manager-read"])
        #expect(messages == ["No saved Claude logins."])
        #expect(FileManager.default.fileExists(atPath: directory.path) == false)
    }

    @Test("Source-owned guard refuses manager creation through a plain store")
    func sourceOwnedGuardRefusesPlainStoreCreate() throws {
        let directory = try disposableDirectory("plain-create-refusal")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MemoryClaudeLoginDataStore()
        var checks = 0
        let backend = plainCommandBackend(directory: directory, store: store, processCheck: {
            checks += 1
            return checks == 2
        })
        var messages: [String] = []

        #expect(runClaudeLogins(arguments: ["claude-login", "save", "alpha"], makeBackend: { backend }, output: { messages.append($0) }, runGUI: {}) == 3)
        #expect(checks == 2)
        #expect(store.createCount == 0)
        #expect(store.updateCount == 0)
        #expect(store.data == nil)
        #expect(messages == ["Blocked: Claude Code is running; quit every session and try again."])
    }

    @Test("Source-owned guard refuses manager update through a plain store")
    func sourceOwnedGuardRefusesPlainStoreUpdate() throws {
        let directory = try disposableDirectory("plain-update-refusal")
        defer { try? FileManager.default.removeItem(at: directory) }
        let before = try serializedEnvelope()
        let store = MemoryClaudeLoginDataStore(data: before)
        var checks = 0
        let backend = plainCommandBackend(directory: directory, store: store, processCheck: {
            checks += 1
            return checks == 2
        })
        var messages: [String] = []

        #expect(runClaudeLogins(arguments: ["claude-login", "save", "alpha"], makeBackend: { backend }, output: { messages.append($0) }, runGUI: {}) == 3)
        #expect(checks == 2)
        #expect(store.createCount == 0)
        #expect(store.updateCount == 0)
        #expect(store.data == before)
        #expect(messages == ["Blocked: Claude Code is running; quit every session and try again."])
    }

    @Test("Source-owned guards allow exactly one manager creation")
    func sourceOwnedGuardsAllowOnePlainStoreCreate() throws {
        let directory = try disposableDirectory("plain-create-success")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MemoryClaudeLoginDataStore()
        var checks = 0
        let backend = plainCommandBackend(directory: directory, store: store, processCheck: {
            checks += 1
            return false
        })

        #expect(runClaudeLogins(arguments: ["claude-login", "save", "alpha"], makeBackend: { backend }, output: { _ in }, runGUI: {}) == 0)
        #expect(checks == 3)
        #expect(store.createCount == 1)
        #expect(store.updateCount == 0)
        #expect(Set(try ClaudeLoginEnvelopeCodec().decode(#require(store.data)).snapshots.keys) == Set(["alpha"]))
    }

    @Test("Source-owned guards allow exactly one manager update")
    func sourceOwnedGuardsAllowOnePlainStoreUpdate() throws {
        let directory = try disposableDirectory("plain-update-success")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MemoryClaudeLoginDataStore(data: try serializedEnvelope())
        var checks = 0
        let backend = plainCommandBackend(directory: directory, store: store, processCheck: {
            checks += 1
            return false
        })

        #expect(runClaudeLogins(arguments: ["claude-login", "save", "alpha"], makeBackend: { backend }, output: { _ in }, runGUI: {}) == 0)
        #expect(checks == 3)
        #expect(store.createCount == 0)
        #expect(store.updateCount == 1)
        #expect(Set(try ClaudeLoginEnvelopeCodec().decode(#require(store.data)).snapshots.keys) == Set(["alpha"]))
    }

    @Test("An initially existing empty envelope cannot become a create")
    func commandInitialExistingEmptyThenMissingRefusesCreate() throws {
        let directory = try disposableDirectory("initial-empty-disappears")
        defer { try? FileManager.default.removeItem(at: directory) }
        let before = try serializedEnvelope(entries: [], activeAlias: nil)
        let store = MemoryClaudeLoginDataStore(data: before, readbackError: IsolatedKeychainError.missing)
        let backend = plainCommandBackend(directory: directory, store: store, processCheck: { false })
        var messages: [String] = []

        #expect(runClaudeLogins(arguments: ["claude-login", "save", "alpha"], makeBackend: { backend }, output: { messages.append($0) }, runGUI: {}) == 3)
        #expect(store.readCount == 2)
        #expect(store.createCount == 0)
        #expect(store.updateCount == 0)
        #expect(store.data == before)
        #expect(messages == ["Blocked: credential backend unavailable."])
    }

    @Test("Native manager mutations guard after lookup and immediately before OS writes")
    func nativeManagerMutationsGuardAtOSBoundary() throws {
        let reference = Data([0xA1])
        var events: [String] = []
        let adapter = IsolatedKeychainAdapter(
            keychain: NSObject(), service: "manager", account: "501",
            beforeMutation: { events.append("guard") },
            calls: .init(
                copy: { _, result in events.append("lookup"); result?.pointee = [reference] as CFArray; return errSecSuccess },
                add: { _ in events.append("add"); return errSecSuccess },
                update: { _, _ in events.append("update"); return errSecSuccess },
                delete: { _ in Issue.record("unexpected delete"); return errSecSuccess }
            )
        )

        try adapter.create(data: Data([0x01]))
        try adapter.update(data: Data([0x02]))

        #expect(events == ["guard", "add", "lookup", "guard", "update"])
    }

    @Test("Secure resource replacement refuses changed data after reference lookup")
    func secureResourceReplacementRecomparesAfterLookup() throws {
        let reference = Data([0xA1])
        let expected = Data(#"{"sentinel":900719925474099312345,"claudeAiOauth":{"accessToken":"A"}}"#.utf8)
        let raced = Data(#"{"sentinel":900719925474099312345,"claudeAiOauth":{"accessToken":"raced"}}"#.utf8)
        var stored = raced
        var copyCount = 0
        var updates = 0
        var guards = 0
        let adapter = IsolatedKeychainAdapter(
            keychain: NSObject(), service: "Claude Code-credentials", account: "fixture",
            calls: .init(
                copy: { _, result in
                    copyCount += 1
                    result?.pointee = copyCount == 1 ? [reference] as CFArray : stored as CFData
                    return errSecSuccess
                },
                add: { _ in Issue.record("unexpected add"); return errSecSuccess },
                update: { _, attributes in
                    updates += 1
                    if let replacement = (attributes as NSDictionary)[kSecValueData] as? Data {
                        stored = replacement
                    } else { Issue.record("missing replacement data") }
                    return errSecSuccess
                },
                delete: { _ in Issue.record("unexpected delete"); return errSecSuccess }
            )
        )

        #expect(throws: IsolatedKeychainError.corrupt) {
            try adapter.replace(expectedData: expected, with: Data("replacement".utf8), guardedBy: { guards += 1 })
        }
        #expect(copyCount == 2)
        #expect(guards == 0)
        #expect(updates == 0)
        #expect(stored == raced)
    }

    @Test("Secure resource replacement guards immediately before one exact data-only update")
    func secureResourceReplacementUsesExactGuardedUpdate() throws {
        let keychain = NSObject()
        let reference = Data([0xA1, 0xB2])
        let expectedSource = #"{"mcp":{"token":"PLACEHOLDER-MCP"},"sentinel":900719925474099312345,"organizationUuid":null,"trustedDeviceToken":null,"claudeAiOauth":{"accessToken":"PLACEHOLDER-A","opaque":[1,{"flag":true}]}}"#
        let intendedSource = try ScopedJSON(expectedSource).replacing([
            "organizationUuid": .missing,
            "trustedDeviceToken": .value(#""PLACEHOLDER-DEVICE""#),
            "claudeAiOauth": .value(#"{"accessToken":"PLACEHOLDER-B","opaque":[1,{"flag":true}]}"#)
        ])
        let expected = Data(expectedSource.utf8)
        let intended = Data(intendedSource.utf8)
        var stored = expected
        var copiedQueries: [[CFString: Any]] = []
        var updatedQuery: [CFString: Any] = [:]
        var updatedAttributes: [CFString: Any] = [:]
        var events: [String] = []
        var adds = 0
        var deletes = 0
        let adapter = IsolatedKeychainAdapter(
            keychain: keychain, service: "Claude Code-credentials", account: "synthetic.invalid",
            calls: .init(
                copy: { query, result in
                    let values = query as! [CFString: Any]
                    copiedQueries.append(values)
                    if values[kSecReturnPersistentRef] as? Bool == true {
                        events.append("identity lookup")
                        result?.pointee = [reference] as CFArray
                    } else {
                        events.append("selected-reference read")
                        result?.pointee = stored as CFData
                    }
                    return errSecSuccess
                },
                add: { _ in adds += 1; return errSecSuccess },
                update: { query, attributes in
                    events.append("update")
                    updatedQuery = query as! [CFString: Any]
                    updatedAttributes = attributes as! [CFString: Any]
                    stored = updatedAttributes[kSecValueData] as! Data
                    return errSecSuccess
                },
                delete: { _ in deletes += 1; return errSecSuccess }
            )
        )

        try adapter.replace(expectedData: expected, with: intended, guardedBy: {
            #expect(events == ["identity lookup", "selected-reference read"])
            #expect(stored == expected)
            events.append("guard")
        })

        #expect(intendedSource == #"{"mcp":{"token":"PLACEHOLDER-MCP"},"sentinel":900719925474099312345,"trustedDeviceToken":"PLACEHOLDER-DEVICE","claudeAiOauth":{"accessToken":"PLACEHOLDER-B","opaque":[1,{"flag":true}]}}"#)
        #expect(events == ["identity lookup", "selected-reference read", "guard", "update"])
        #expect(copiedQueries.count == 2)
        #expect(copiedQueries[0].count == 6)
        #expect(copiedQueries[0][kSecClass] as! CFString == kSecClassGenericPassword)
        #expect(copiedQueries[0][kSecAttrService] as? String == "Claude Code-credentials")
        #expect(copiedQueries[0][kSecAttrAccount] as? String == "synthetic.invalid")
        #expect((copiedQueries[0][kSecMatchSearchList] as? [AnyObject])?.count == 1)
        #expect((copiedQueries[0][kSecMatchSearchList] as? [AnyObject])?.first === keychain)
        #expect(copiedQueries[0][kSecReturnPersistentRef] as? Bool == true)
        #expect(copiedQueries[0][kSecMatchLimit] as! CFString == kSecMatchLimitAll)
        #expect(copiedQueries[1].count == 4)
        #expect(copiedQueries[1][kSecValuePersistentRef] as? Data == reference)
        #expect((copiedQueries[1][kSecMatchSearchList] as? [AnyObject])?.count == 1)
        #expect((copiedQueries[1][kSecMatchSearchList] as? [AnyObject])?.first === keychain)
        #expect(copiedQueries[1][kSecReturnData] as? Bool == true)
        #expect(copiedQueries[1][kSecMatchLimit] as! CFString == kSecMatchLimitOne)
        #expect(updatedQuery.count == 2)
        #expect(updatedQuery[kSecValuePersistentRef] as? Data == reference)
        #expect((updatedQuery[kSecMatchSearchList] as? [AnyObject])?.count == 1)
        #expect((updatedQuery[kSecMatchSearchList] as? [AnyObject])?.first === keychain)
        #expect(updatedAttributes.count == 1)
        #expect(updatedAttributes[kSecValueData] as? Data == intended)
        #expect(stored == intended)
        #expect(adds == 0)
        #expect(deletes == 0)
    }

    @Test("A throwing secure replacement guard preserves the exact stored preimage")
    func secureResourceReplacementThrowingGuardDoesNotMutate() {
        let reference = Data([0xC3])
        let expected = Data(#"{"sentinel":900719925474099312345,"claudeAiOauth":{"accessToken":"PLACEHOLDER-A"}}"#.utf8)
        let stored = expected
        var guards = 0
        var updates = 0
        var adds = 0
        var deletes = 0
        let adapter = IsolatedKeychainAdapter(
            keychain: NSObject(), service: "Claude Code-credentials", account: "synthetic.invalid",
            calls: .init(
                copy: { query, result in
                    let values = query as! [CFString: Any]
                    result?.pointee = values[kSecReturnPersistentRef] as? Bool == true
                        ? [reference] as CFArray
                        : stored as CFData
                    return errSecSuccess
                },
                add: { _ in adds += 1; return errSecSuccess },
                update: { _, _ in updates += 1; return errSecSuccess },
                delete: { _ in deletes += 1; return errSecSuccess }
            )
        )

        #expect(throws: FixtureError.self) {
            try adapter.replace(expectedData: expected, with: Data("PLACEHOLDER-B".utf8), guardedBy: {
                guards += 1
                throw FixtureError()
            })
        }
        #expect(guards == 1)
        #expect(updates == 0)
        #expect(adds == 0)
        #expect(deletes == 0)
        #expect(stored == expected)
    }

    @Test(
        "Secure replacement maps lookup, selected-read, and native-update failures without mutation",
        arguments: [
            ("lookup", errSecAuthFailed, IsolatedKeychainError.denied, 0),
            ("read", errSecInteractionNotAllowed, IsolatedKeychainError.locked, 0),
            ("update", errSecUserCanceled, IsolatedKeychainError.cancelled, 1)
        ]
    )
    func secureResourceReplacementMapsNativeFailures(
        stage: String, status: OSStatus, expectedError: IsolatedKeychainError, expectedGuards: Int
    ) {
        let reference = Data([0xD4])
        let expected = Data("PLACEHOLDER-A".utf8)
        let stored = expected
        var copies = 0
        var guards = 0
        var updates = 0
        var adds = 0
        var deletes = 0
        let adapter = IsolatedKeychainAdapter(
            keychain: NSObject(), service: "Claude Code-credentials", account: "synthetic.invalid",
            calls: .init(
                copy: { _, result in
                    copies += 1
                    if stage == "lookup" { return status }
                    if copies == 1 { result?.pointee = [reference] as CFArray; return errSecSuccess }
                    if stage == "read" { return status }
                    result?.pointee = stored as CFData
                    return errSecSuccess
                },
                add: { _ in adds += 1; return errSecSuccess },
                update: { _, _ in updates += 1; return stage == "update" ? status : errSecSuccess },
                delete: { _ in deletes += 1; return errSecSuccess }
            )
        )

        #expect(throws: expectedError) {
            try adapter.replace(expectedData: expected, with: Data("PLACEHOLDER-B".utf8), guardedBy: { guards += 1 })
        }
        #expect(guards == expectedGuards)
        #expect(updates == (stage == "update" ? 1 : 0))
        #expect(adds == 0)
        #expect(deletes == 0)
        #expect(stored == expected)
    }

    @Test("Configuration resource replacement refuses a stale expected root")
    func configurationResourceReplacementRecomparesExpectedRoot() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("opencode", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let source = #"{"oauthAccount":{"accountUuid":"account-a"},"sentinel":900719925474099312345,"modelAccessCache":{"keep":true}}"#
        let fixture = try ConfigurationFixture(source)
        defer { fixture.cleanup() }
        let inode = try fileInode(fixture.file)
        var guards = 0

        #expect(throws: ProtectedConfigurationError.changedBeforeCommit) {
            try ProtectedConfigurationFile(path: fixture.file.path).replace(
                expectedSource: #"{"oauthAccount":{"accountUuid":"other"}}"#,
                with: .init(oauthAccount: .null, invalidateAccountCaches: true),
                guardedBy: { guards += 1 }
            )
        }
        #expect(guards == 0)
        #expect(try String(contentsOf: fixture.file, encoding: .utf8) == source)
        #expect(try fileInode(fixture.file) == inode)
        #expect(try fixture.temporaryFiles().isEmpty)
        fixture.cleanup()
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.path))
    }

    @Test("Guarded configuration replacement preserves scoped data and protections", arguments: ConfigurationPresence.allCases)
    func guardedConfigurationReplacementSucceeds(_ presence: ConfigurationPresence) throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("opencode", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let source = #"{"sentinel":900719925474099312345,"oauthAccount":{"old":true},"additionalModelOptionsCache":1,"additionalModelCostsCache":2,"modelAccessCache":3,"orgModelDefaultCache":4,"lastSeenOrgDefaultUpdatedAt":5,"clientDataCache":6,"clientDataCacheSlots":7,"autoCompactWindowsCache":8,"cachedUsageUtilization":9,"unknown":{"keep":true}}"#
        let fixture = try ConfigurationFixture(source)
        defer { fixture.cleanup() }
        let originalInode = try fileInode(fixture.file)
        var guards = 0

        try ProtectedConfigurationFile(path: fixture.file.path).replace(
            expectedSource: source,
            with: .init(oauthAccount: presence.value, invalidateAccountCaches: true),
            guardedBy: {
                guards += 1
                let destinationInode = try fileInode(fixture.file)
                let stagedFiles = try fixture.temporaryFiles()
                #expect(destinationInode == originalInode)
                #expect(stagedFiles.count == 1)
            }
        )

        #expect(guards == 1)
        #expect(try String(contentsOf: fixture.file, encoding: .utf8) == presence.expectedDocument)
        #expect(try fileInode(fixture.file) != originalInode)
        let metadata = try fixture.metadata()
        #expect(metadata.owner == geteuid())
        #expect(metadata.mode == 0o600)
        #expect(try fixture.temporaryFiles().isEmpty)
        fixture.cleanup()
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.path))
    }

    @Test("Throwing configuration guard preserves destination identity and removes staging")
    func guardedConfigurationReplacementRefusesThrowingGuard() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("opencode", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let source = #"{"oauthAccount":{"old":true},"sentinel":900719925474099312345}"#
        let fixture = try ConfigurationFixture(source)
        defer { fixture.cleanup() }
        let original = try Data(contentsOf: fixture.file)
        let originalInode = try fileInode(fixture.file)
        let originalMetadata = try fixture.metadata()
        var guards = 0

        #expect(throws: FixtureError.self) {
            try ProtectedConfigurationFile(path: fixture.file.path).replace(
                expectedSource: source,
                with: .init(oauthAccount: .null, invalidateAccountCaches: true),
                guardedBy: {
                    guards += 1
                    let destinationInode = try fileInode(fixture.file)
                    let stagedFiles = try fixture.temporaryFiles()
                    #expect(destinationInode == originalInode)
                    #expect(stagedFiles.count == 1)
                    throw FixtureError()
                }
            )
        }

        #expect(guards == 1)
        #expect(try Data(contentsOf: fixture.file) == original)
        #expect(try fileInode(fixture.file) == originalInode)
        #expect(try fixture.metadata().owner == originalMetadata.owner)
        #expect(try fixture.metadata().mode == originalMetadata.mode)
        #expect(try fixture.temporaryFiles().isEmpty)
        fixture.cleanup()
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.path))
    }

    @Test("Process refusal immediately before mutation or after verification has precise write semantics", arguments: MutationGuardCase.cases)
    func commandScopedProcessRefusalStopsWrites(testCase: MutationGuardCase) throws {
        let directory = try disposableDirectory("command-process")
        var checks = 0
        let store = MemoryClaudeLoginDataStore(data: testCase.existing ? try serializedEnvelope() : nil)
        let process = ClaudeProcessPreflight(
            expectedUID: 501, trustedExecutablePath: "/synthetic/claude",
            probe: .init(snapshot: {
                checks += 1
                return checks == testCase.checkToFail
                    ? [.init(pid: 40, parentPID: 1, uid: 501, executablePath: "/synthetic/terminal", role: .terminal)]
                    : []
            })
        )
        let backend = CommandScopedClaudeLoginBackend(
            acquireLock: { try ManagerFileLock.acquire(directory: directory.path) },
            routingEvidence: { .testing() },
            readCustody: { ClaudeLoginCustody(store: store) },
            writeCustody: { _, guardMutation in ClaudeLoginCustody(store: MutationGuardedDataStore(store, guardMutation)) },
            processPreflight: process,
            currentSnapshot: { _ in
                if testCase.checkToFail == 1 { Issue.record("capture invoked after initial process refusal") }
                return try self.snapshot(account: "account-a")
            }
        )
        var messages: [String] = []

        #expect(runClaudeLogins(arguments: ["claude-login", "save", "alpha"], makeBackend: { backend }, output: { messages.append($0) }, runGUI: {}) == 3)
        #expect(store.createCount == (!testCase.existing && testCase.checkToFail == 3 ? 1 : 0))
        #expect(store.updateCount == (testCase.existing && testCase.checkToFail == 3 ? 1 : 0))
        #expect(messages == ["Blocked: Claude Code is running; quit every session and try again."])
        let reacquired = try ManagerFileLock.acquire(directory: directory.path)
        reacquired.release()
        try FileManager.default.removeItem(at: directory)
        #expect(FileManager.default.fileExists(atPath: directory.path) == false)
    }

    @Test("Command enrollment preserves exact cached identities and refuses unsafe variants")
    func commandEnrollmentMatrixUsesCachedState() throws {
        let directory = try disposableDirectory("command-enrollment")
        let store = MemoryClaudeLoginDataStore()
        var current = try snapshot(account: "account-a", accessToken: "A1")
        let backend = commandBackend(directory: directory, store: store, currentSnapshot: { current })
        var messages: [String] = []
        func run(_ alias: String) -> Int32 {
            runClaudeLogins(arguments: ["claude-login", "save", alias], makeBackend: { backend }, output: { messages.append($0) }, runGUI: {})
        }

        #expect(run("alpha") == 0)
        #expect(run("beta") == 3)
        current = try snapshot(account: "account-b", accessToken: "B1")
        #expect(run("beta") == 0)
        #expect(try ClaudeLoginEnvelopeCodec().decode(#require(store.data)) == ClaudeLoginState(
            snapshots: ["alpha": try snapshot(account: "account-a", accessToken: "A1"), "beta": current], activeAlias: "alpha"
        ))
        current = try snapshot(account: "account-a", accessToken: "A2")
        #expect(run("alpha") == 0)
        let expected = ClaudeLoginState(
            snapshots: ["alpha": current, "beta": try snapshot(account: "account-b", accessToken: "B1")],
            activeAlias: "alpha"
        )
        #expect(try ClaudeLoginEnvelopeCodec().decode(#require(store.data)) == expected)
        current = try snapshot(account: "account-c")
        #expect(run("alpha") == 3)
        current = try ClaudeLoginSnapshot.capture(
            secureRoot: #"{"claudeAiOauth":null}"#,
            configurationRoot: #"{"oauthAccount":{"accountUuid":"account-b"}}"#
        )
        #expect(run("beta") == 5)
        #expect(try ClaudeLoginEnvelopeCodec().decode(#require(store.data)) == expected)
        #expect(store.createCount == 1)
        #expect(store.updateCount == 2)
        #expect(messages == ["Saved alias alpha.", "Blocked: login is already saved.", "Saved alias beta.", "Saved alias alpha.", "Blocked: alias belongs to another login.", "Re-login needed before saving this alias."])
        try FileManager.default.removeItem(at: directory)
        #expect(FileManager.default.fileExists(atPath: directory.path) == false)
    }

    @Test("Command failures release lock and preserve precise mutation state", arguments: CommandFailureCase.allCases)
    func commandFailuresAreSafe(testCase: CommandFailureCase) throws {
        let directory = try disposableDirectory("command-failure")
        let before = testCase.existing ? try serializedEnvelope() : nil
        let store = MemoryClaudeLoginDataStore(
            data: before,
            createError: testCase == .create ? FixtureError() : nil,
            updateError: testCase == .update ? FixtureError() : nil,
            postMutationReadError: testCase == .readback ? FixtureError() : nil
        )
        let backend = CommandScopedClaudeLoginBackend(
            acquireLock: { try ManagerFileLock.acquire(directory: directory.path) },
            routingEvidence: { .testing() },
            readCustody: { ClaudeLoginCustody(store: store) },
            writeCustody: { _, _ in
                if testCase == .factory { throw FixtureError() }
                return ClaudeLoginCustody(store: store)
            },
            processPreflight: safeProcessPreflight(),
            currentSnapshot: { _ in
                if testCase == .capture { throw FixtureError() }
                return try self.snapshot(account: "account-a", accessToken: "changed")
            }
        )
        var messages: [String] = []

        #expect(runClaudeLogins(arguments: ["claude-login", "save", "alpha"], makeBackend: { backend }, output: { messages.append($0) }, runGUI: {}) == 3)
        #expect(store.createCount + store.updateCount == testCase.attemptedWrites)
        #expect(testCase == .readback ? store.data != before : store.data == before)
        #expect(messages == ["Blocked: credential backend unavailable."])
        let reacquired = try ManagerFileLock.acquire(directory: directory.path)
        reacquired.release()
        try FileManager.default.removeItem(at: directory)
        #expect(FileManager.default.fileExists(atPath: directory.path) == false)
    }

    @Test("Command lock contention is a safe refusal before routing or state IO")
    func commandScopedLockContentionRefusesBeforeIO() throws {
        let directory = try disposableDirectory("command-contention")
        defer { try? FileManager.default.removeItem(at: directory) }
        let holder = try ManagerFileLock.acquire(directory: directory.path)
        defer { holder.release() }
        var events: [String] = []
        let store = MemoryClaudeLoginDataStore(event: { events.append($0) })
        let backend = commandBackend(directory: directory, store: store, event: { events.append($0) })
        var messages: [String] = []

        #expect(runClaudeLogins(arguments: ["claude-login", "save", "alpha"], makeBackend: { backend }, output: { messages.append($0) }, runGUI: {}) == 3)
        #expect(events == ["lock"])
        #expect(messages == ["Blocked: credential backend unavailable."])
        #expect(store.createCount == 0)
        #expect(store.updateCount == 0)
    }

    @Test("Malformed list state is a safe manager-only refusal")
    func commandScopedListRefusesMalformedState() throws {
        let directory = try disposableDirectory("command-list-refusal")
        defer { try? FileManager.default.removeItem(at: directory) }
        var events: [String] = []
        let store = MemoryClaudeLoginDataStore(data: Data("invalid".utf8), event: { events.append($0) })
        let backend = commandBackend(directory: directory, store: store, event: { events.append($0) })
        var messages: [String] = []

        #expect(runClaudeLogins(arguments: ["claude-login", "list"], makeBackend: { backend }, output: { messages.append($0) }, runGUI: {}) == 3)
        #expect(events == ["read-factory", "manager-read"])
        #expect(messages == ["Blocked: credential backend unavailable."])
        #expect(FileManager.default.fileExists(atPath: directory.path) == false)
    }

    @Test("Denied list state uses only the manager read boundary")
    func commandScopedListRefusesDeniedState() {
        var events: [String] = []
        let store = MemoryClaudeLoginDataStore(readError: IsolatedKeychainError.denied, event: { events.append($0) })
        let backend = commandBackend(directory: URL(fileURLWithPath: "/unused"), store: store, event: { events.append($0) })
        var messages: [String] = []

        #expect(runClaudeLogins(arguments: ["claude-login", "list"], makeBackend: { backend }, output: { messages.append($0) }, runGUI: {}) == 3)
        #expect(events == ["read-factory", "manager-read"])
        #expect(store.createCount == 0)
        #expect(store.updateCount == 0)
        #expect(messages == ["Blocked: credential backend unavailable."])
    }

    @Test("Manager Keychain policy is local, UID-bound, nonsynchronizing, and ACL-bound")
    func managerKeychainPolicyBuildsExactAttributes() {
        let approvedAccess = NSObject()
        let attributes = ManagerKeychainPolicy.creationAttributes(uid: 501, approvedAccess: approvedAccess)

        #expect(attributes[kSecAttrService] as? String == "AIControl-claude-logins.v1")
        #expect(attributes[kSecAttrAccount] as? String == "501")
        #expect(attributes[kSecAttrSynchronizable] as? Bool == false)
        #expect(attributes[kSecAttrAccess] as AnyObject === approvedAccess)
    }

    @Test("Manager Keychain creation binds approved binary policy before adding")
    func managerKeychainCreationBindsApprovedPolicy() throws {
        let keychain = NSObject()
        let application = NSObject()
        let access = NSObject()
        let reference = Data([0xA1])
        var events: [String] = []
        var addedQuery: [CFString: Any] = [:]
        var updateQuery: [CFString: Any] = [:]
        var updateAttributes: [CFString: Any] = [:]
        var deleteCount = 0
        let policyCalls = ManagerKeychainNativeCalls(
            createTrustedApplication: { path in
                events.append("application:\(path)")
                return (errSecSuccess, application)
            },
            createAccess: { description, applications in
                events.append("access:\(description)")
                #expect((applications as [AnyObject]).first === application)
                return (errSecSuccess, access)
            }
        )
        let keychainCalls = KeychainNativeCalls(
            copy: { _, result in
                events.append("copy")
                result?.pointee = [reference] as CFArray
                return errSecSuccess
            },
            add: { query in
                events.append("add")
                addedQuery = query as! [CFString: Any]
                return errSecSuccess
            },
            update: { query, attributes in
                events.append("update")
                updateQuery = query as! [CFString: Any]
                updateAttributes = attributes as! [CFString: Any]
                return errSecSuccess
            },
            delete: { _ in deleteCount += 1; return errSecSuccess }
        )

        let adapter = try IsolatedKeychainAdapter(
            keychain: keychain,
            approvedBinaryPath: "/synthetic/AIControl",
            uid: 501,
            policyCalls: policyCalls,
            calls: keychainCalls
        )
        try adapter.create(data: Data("initial".utf8))
        try adapter.update(data: Data("replacement".utf8))

        #expect(events == ["application:/synthetic/AIControl", "access:AIControl Claude login manager", "add", "copy", "update"])
        #expect(addedQuery[kSecUseKeychain] as AnyObject === keychain)
        #expect(addedQuery[kSecAttrService] as? String == "AIControl-claude-logins.v1")
        #expect(addedQuery[kSecAttrAccount] as? String == "501")
        #expect(addedQuery[kSecAttrSynchronizable] as? Bool == false)
        #expect(addedQuery[kSecAttrAccess] as AnyObject === access)
        #expect(updateQuery[kSecValuePersistentRef] as? Data == reference)
        #expect(updateAttributes.count == 1)
        #expect(updateAttributes[kSecValueData] as? Data == Data("replacement".utf8))
        #expect(deleteCount == 0)
    }

    @Test("Manager Keychain creation refuses trusted-application failures before adding")
    func managerKeychainCreationRefusesTrustedApplicationFailures() {
        var accessCount = 0
        var addCount = 0
        let keychainCalls = KeychainNativeCalls(
            copy: { _, _ in errSecSuccess },
            add: { _ in addCount += 1; return errSecSuccess },
            update: { _, _ in errSecSuccess },
            delete: { _ in errSecSuccess }
        )
        let failedCalls = ManagerKeychainNativeCalls(
            createTrustedApplication: { _ in (OSStatus(-4), NSObject()) },
            createAccess: { _, _ in accessCount += 1; return (errSecSuccess, NSObject()) }
        )
        let nilCalls = ManagerKeychainNativeCalls(
            createTrustedApplication: { _ in (errSecSuccess, nil) },
            createAccess: { _, _ in accessCount += 1; return (errSecSuccess, NSObject()) }
        )

        #expect(throws: ManagerKeychainPolicy.Error.unapprovedBinary(-4)) {
            let adapter = try IsolatedKeychainAdapter(
                keychain: NSObject(), approvedBinaryPath: "/synthetic/failed", policyCalls: failedCalls, calls: keychainCalls
            )
            try adapter.create(data: Data())
        }
        #expect(throws: ManagerKeychainPolicy.Error.unapprovedBinary(errSecSuccess)) {
            let adapter = try IsolatedKeychainAdapter(
                keychain: NSObject(), approvedBinaryPath: "/synthetic/nil", policyCalls: nilCalls, calls: keychainCalls
            )
            try adapter.create(data: Data())
        }
        #expect(accessCount == 0)
        #expect(addCount == 0)
    }

    @Test("Manager Keychain creation refuses access failures before adding")
    func managerKeychainCreationRefusesAccessFailures() {
        let application = NSObject()
        var addCount = 0
        let keychainCalls = KeychainNativeCalls(
            copy: { _, _ in errSecSuccess },
            add: { _ in addCount += 1; return errSecSuccess },
            update: { _, _ in errSecSuccess },
            delete: { _ in errSecSuccess }
        )
        let failedCalls = ManagerKeychainNativeCalls(
            createTrustedApplication: { _ in (errSecSuccess, application) },
            createAccess: { _, _ in (OSStatus(-4), NSObject()) }
        )
        let nilCalls = ManagerKeychainNativeCalls(
            createTrustedApplication: { _ in (errSecSuccess, application) },
            createAccess: { _, _ in (errSecSuccess, nil) }
        )

        #expect(throws: ManagerKeychainPolicy.Error.accessCreation(-4)) {
            let adapter = try IsolatedKeychainAdapter(
                keychain: NSObject(), approvedBinaryPath: "/synthetic/failed", policyCalls: failedCalls, calls: keychainCalls
            )
            try adapter.create(data: Data())
        }
        #expect(throws: ManagerKeychainPolicy.Error.accessCreation(errSecSuccess)) {
            let adapter = try IsolatedKeychainAdapter(
                keychain: NSObject(), approvedBinaryPath: "/synthetic/nil", policyCalls: nilCalls, calls: keychainCalls
            )
            try adapter.create(data: Data())
        }
        #expect(addCount == 0)
    }

    @Test("Isolated Keychain CRUD uses exact explicit-Keychain queries")
    func isolatedKeychainCRUDUsesExactQueries() throws {
        let keychain = NSObject()
        let persistentReference = Data([0xCA, 0xFE])
        var copiedQueries: [[CFString: Any]] = []
        var addedQuery: [CFString: Any] = [:]
        var updatedQuery: [CFString: Any] = [:]
        var updatedAttributes: [CFString: Any] = [:]
        var deletedQuery: [CFString: Any] = [:]
        let calls = KeychainNativeCalls(
            copy: { query, result in
                let values = query as! [CFString: Any]
                copiedQueries.append(values)
                if values[kSecReturnPersistentRef] as? Bool == true {
                    result?.pointee = [persistentReference] as CFArray
                } else {
                    result?.pointee = Data("updated".utf8) as CFData
                }
                return errSecSuccess
            },
            add: { query in addedQuery = query as! [CFString: Any]; return errSecSuccess },
            update: { query, attributes in
                updatedQuery = query as! [CFString: Any]
                updatedAttributes = attributes as! [CFString: Any]
                return errSecSuccess
            },
            delete: { query in deletedQuery = query as! [CFString: Any]; return errSecSuccess }
        )
        let adapter = IsolatedKeychainAdapter(
            keychain: keychain,
            service: "AIControl-claude-logins.v1.test-unit",
            account: "synthetic-account",
            creationAttributes: ManagerKeychainPolicy.creationAttributes(uid: 501, approvedAccess: keychain),
            calls: calls
        )

        try adapter.create(data: Data("initial".utf8))
        #expect(try adapter.read() == Data("updated".utf8))
        try adapter.update(data: Data("replacement".utf8))
        try adapter.delete()

        #expect(addedQuery[kSecUseKeychain] as AnyObject === keychain)
        #expect(addedQuery[kSecMatchSearchList] == nil)
        #expect(addedQuery[kSecAttrService] as? String == "AIControl-claude-logins.v1.test-unit")
        #expect(addedQuery[kSecAttrAccount] as? String == "synthetic-account")
        #expect(addedQuery[kSecAttrSynchronizable] as? Bool == false)
        #expect(addedQuery[kSecAttrAccess] as AnyObject === keychain)
        #expect(copiedQueries.count == 4)
        #expect((copiedQueries[0][kSecMatchSearchList] as? [AnyObject])?.first === keychain)
        #expect(copiedQueries[0][kSecReturnPersistentRef] as? Bool == true)
        #expect(updatedQuery[kSecValuePersistentRef] as? Data == persistentReference)
        #expect(updatedAttributes.count == 1)
        #expect(updatedAttributes[kSecValueData] as? Data == Data("replacement".utf8))
        #expect(deletedQuery[kSecValuePersistentRef] as? Data == persistentReference)
    }

    @Test("Isolated Keychain adapter distinguishes missing and duplicate items")
    func isolatedKeychainDistinguishesMissingAndDuplicate() {
        let missing = IsolatedKeychainAdapter.testing(status: errSecItemNotFound)
        let duplicate = IsolatedKeychainAdapter.testing(status: errSecDuplicateItem)

        #expect(throws: IsolatedKeychainError.missing) { try missing.read() }
        #expect(throws: IsolatedKeychainError.duplicate) { try duplicate.create(data: Data()) }
    }

    @Test(
        "Isolated Keychain adapter maps security failures deterministically",
        arguments: [
            (errSecAuthFailed, IsolatedKeychainError.denied),
            (errSecUserCanceled, IsolatedKeychainError.cancelled),
            (errSecInteractionNotAllowed, IsolatedKeychainError.locked),
            (OSStatus(-4), IsolatedKeychainError.operatingSystem(-4))
        ]
    )
    func isolatedKeychainMapsSecurityFailures(status: OSStatus, expected: IsolatedKeychainError) {
        let adapter = IsolatedKeychainAdapter.testing(status: status)

        #expect(throws: expected) { try adapter.read() }
    }

    @Test("Isolated Keychain adapter rejects ambiguous and corrupt native results")
    func isolatedKeychainRejectsAmbiguousAndCorruptResults() {
        let ambiguous = IsolatedKeychainAdapter.testing(result: [Data([1]), Data([2])] as CFArray)
        let corrupt = IsolatedKeychainAdapter.testing(result: "not-a-reference" as CFString)

        #expect(throws: IsolatedKeychainError.ambiguous) { try ambiguous.read() }
        #expect(throws: IsolatedKeychainError.corrupt) { try corrupt.read() }
    }

    @Test(
        "Opt-in isolated native Keychain CRUD preserves attributes and cleans up",
        .enabled(if: ProcessInfo.processInfo.environment["AI_CONTROL_KEYCHAIN_TEST_ROOT"] != nil)
    )
    func optInIsolatedNativeKeychainCRUD() throws {
        let root = try #require(ProcessInfo.processInfo.environment["AI_CONTROL_KEYCHAIN_TEST_ROOT"])
        let directory = URL(fileURLWithPath: root, isDirectory: true)
            .appendingPathComponent("ai-control-keychain-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        let path = directory.appendingPathComponent("isolated.keychain-db").path
        let password = UUID().uuidString
        var keychain: SecKeychain?
        var originalSearchList: CFArray?
        #expect(SecKeychainCopySearchList(&originalSearchList) == errSecSuccess)
        let originalKeychains = try #require(originalSearchList as? [SecKeychain])
        defer {
            if let isolated = keychain {
                #expect(IsolatedKeychainAdapter.removeFromSearchList(isolated))
                #expect(SecKeychainDelete(isolated) == errSecSuccess)
            }
            try? FileManager.default.removeItem(at: directory)
            #expect(FileManager.default.fileExists(atPath: path) == false)
        }
        let createStatus = password.withCString {
            SecKeychainCreate(path, UInt32(strlen($0)), $0, false, nil, &keychain)
        }
        #expect(createStatus == errSecSuccess)
        let isolated = try #require(keychain)
        #expect(IsolatedKeychainAdapter.removeFromSearchList(isolated))
        var detachedSearchList: CFArray?
        #expect(SecKeychainCopySearchList(&detachedSearchList) == errSecSuccess)
        let detachedKeychains = try #require(detachedSearchList as? [SecKeychain])
        #expect(sameKeychainList(originalKeychains, detachedKeychains))
        let service = "AIControl-claude-logins.v1.test-\(UUID().uuidString)"
        let account = "synthetic-account"
        let adapter = IsolatedKeychainAdapter(keychain: isolated, service: service, account: account)

        try adapter.create(data: Data("SYNTHETIC-INITIAL".utf8))
        #expect(try adapter.read() == Data("SYNTHETIC-INITIAL".utf8))
        let exactQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword, kSecAttrService: service,
            kSecAttrAccount: account, kSecMatchSearchList: [isolated]
        ]
        #expect(SecItemUpdate(
            exactQuery as CFDictionary,
            [kSecAttrLabel: "preserve-sentinel"] as CFDictionary
        ) == errSecSuccess)
        try adapter.update(data: Data("SYNTHETIC-UPDATED".utf8))
        #expect(try adapter.read() == Data("SYNTHETIC-UPDATED".utf8))
        var attributeResult: CFTypeRef?
        var attributeQuery = exactQuery
        attributeQuery[kSecReturnAttributes] = true
        #expect(SecItemCopyMatching(attributeQuery as CFDictionary, &attributeResult) == errSecSuccess)
        #expect((attributeResult as? [CFString: Any])?[kSecAttrLabel] as? String == "preserve-sentinel")
        try adapter.delete()
        #expect(throws: IsolatedKeychainError.missing) { try adapter.read() }
    }

    @Test("Protected configuration update preserves raw sentinels and file protections")
    func protectedConfigurationPreservesRawDataAndProtections() throws {
        let fixture = try ConfigurationFixture(
            #"{"sentinel":900719925474099312345,"oauthAccount":{"old":true},"modelAccessCache":{"remove":true}}"#
        )
        defer { fixture.cleanup() }

        try ProtectedConfigurationFile(path: fixture.file.path).update(
            .init(oauthAccount: .value(#"{"new":true}"#), invalidateAccountCaches: true)
        )

        #expect(try String(contentsOf: fixture.file, encoding: .utf8) ==
            #"{"sentinel":900719925474099312345,"oauthAccount":{"new":true}}"#)
        let metadata = try fixture.metadata()
        #expect(metadata.owner == geteuid())
        #expect(metadata.mode == 0o600)
        #expect(try fixture.temporaryFiles().isEmpty)
    }

    @Test("Protected configuration rejects oversized, deeply nested, and duplicate-key input")
    func protectedConfigurationRejectsInvalidAdmission() throws {
        let oversized = try ConfigurationFixture(#"{"padding":"xxxxxxxxxxxxxxxx"}"#)
        defer { oversized.cleanup() }
        let deep = try ConfigurationFixture(#"{"a":{"b":{"c":1}}}"#)
        defer { deep.cleanup() }
        let duplicate = try ConfigurationFixture(#"{"a":1,"a":2}"#)
        defer { duplicate.cleanup() }
        let invalidUTF8 = try ConfigurationFixture("{}")
        defer { invalidUTF8.cleanup() }
        try Data([0xFF]).write(to: invalidUTF8.file)
        let shallow = try ConfigurationFixture("{}")
        defer { shallow.cleanup() }

        #expect(throws: ProtectedConfigurationError.tooLarge) {
            try ProtectedConfigurationFile(path: oversized.file.path, maxBytes: 16).update(.init())
        }
        #expect(throws: ProtectedConfigurationError.tooDeep) {
            try ProtectedConfigurationFile(path: deep.file.path, maxDepth: 2).update(.init())
        }
        #expect(throws: ProtectedConfigurationError.invalidDocument) {
            try ProtectedConfigurationFile(path: duplicate.file.path).update(.init())
        }
        #expect(throws: ProtectedConfigurationError.invalidDocument) {
            try ProtectedConfigurationFile(path: invalidUTF8.file.path).update(.init())
        }
        #expect(throws: ProtectedConfigurationError.tooDeep) {
            try ProtectedConfigurationFile(path: shallow.file.path, maxDepth: 2)
                .update(.init(oauthAccount: .value(#"{"x":{"y":1}}"#)))
        }
    }

    @Test("Protected configuration refuses symlinks and unexpected owners")
    func protectedConfigurationRefusesUnsafeFiles() throws {
        let fixture = try ConfigurationFixture(#"{"oauthAccount":null}"#)
        defer { fixture.cleanup() }
        let link = fixture.directory.appendingPathComponent("linked.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.file)

        #expect(throws: ProtectedConfigurationError.unsafeFile) {
            try ProtectedConfigurationFile(path: link.path).update(.init())
        }
        #expect(throws: ProtectedConfigurationError.unsafeFile) {
            try ProtectedConfigurationFile(path: fixture.file.path, expectedOwner: geteuid() + 1).update(.init())
        }
    }

    @Test("Protected configuration detects pre-commit races", arguments: ConfigurationRace.allCases)
    func protectedConfigurationDetectsRace(_ race: ConfigurationRace) throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("opencode", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let source = #"{"oauthAccount":{"old":true}}"#
        let fixture = try ConfigurationFixture(source)
        defer { fixture.cleanup() }
        let originalInode = try fileInode(fixture.file)
        var externalInode: ino_t?
        var stagedFiles = 0
        var guards = 0
        let writer = ProtectedConfigurationFile(path: fixture.file.path, hooks: .init(beforeCommit: {
            stagedFiles = try fixture.temporaryFiles().count
            try race.apply(to: fixture.file)
            let installedInode = try fileInode(fixture.file)
            if race == .identity {
                externalInode = installedInode
                #expect(try Data(contentsOf: fixture.file) == Data(source.utf8))
                #expect(installedInode != originalInode)
                #expect(try fixture.metadata().owner == geteuid())
                #expect(try fixture.metadata().mode == 0o600)
            }
        }))

        #expect(throws: ProtectedConfigurationError.changedBeforeCommit) {
            try writer.replace(
                expectedSource: source,
                with: .init(oauthAccount: .null),
                guardedBy: { guards += 1 }
            )
        }
        #expect(stagedFiles == 1)
        #expect(guards == 0)
        #expect(try Data(contentsOf: fixture.file) == Data(race.expectedDocument(source).utf8))
        #expect(race.matchesInode(original: originalInode, current: try fileInode(fixture.file)))
        if race == .identity {
            #expect(try fileInode(fixture.file) == externalInode)
        }
        let metadata = try fixture.metadata()
        #expect(metadata.owner == geteuid())
        #expect(metadata.mode == race.expectedMode)
        #expect(try fixture.temporaryFiles().isEmpty)
        fixture.cleanup()
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.path))
    }

    @Test("Protected configuration distinguishes failures before and after commit")
    func protectedConfigurationDistinguishesCommitFailures() throws {
        let before = try ConfigurationFixture(#"{"oauthAccount":{"old":true}}"#)
        defer { before.cleanup() }
        let after = try ConfigurationFixture(#"{"oauthAccount":{"old":true}}"#)
        defer { after.cleanup() }

        #expect(throws: ProtectedConfigurationError.writeFailed) {
            try ProtectedConfigurationFile(path: before.file.path, hooks: .init(beforeCommit: { throw FixtureError() }))
                .update(.init(oauthAccount: .null))
        }
        #expect(try String(contentsOf: before.file, encoding: .utf8) == #"{"oauthAccount":{"old":true}}"#)
        #expect(try before.temporaryFiles().isEmpty)
        #expect(throws: ProtectedConfigurationError.indeterminateAfterCommit) {
            try ProtectedConfigurationFile(path: after.file.path, hooks: .init(afterCommit: { throw FixtureError() }))
                .update(.init(oauthAccount: .null))
        }
        #expect(try String(contentsOf: after.file, encoding: .utf8) == #"{"oauthAccount":null}"#)
        #expect(try after.temporaryFiles().isEmpty)
    }

    @Test("Manager lock serializes holders without replacing the lock inode")
    func managerLockSerializesAndReleases() throws {
        let directory = try disposableDirectory("lock")
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try ManagerFileLock.acquire(directory: directory.path)
        defer { first.release() }
        let inode = try fileInode(directory.appendingPathComponent("claude-login.lock"))

        #expect(throws: ManagerFileLockError.contended) {
            try ManagerFileLock.acquire(directory: directory.path)
        }
        first.release()
        let next = try ManagerFileLock.acquire(directory: directory.path)
        #expect(try fileInode(directory.appendingPathComponent("claude-login.lock")) == inode)
        next.release()
    }

    @Test("Manager lock rejects unsafe directory and lock-file protections")
    func managerLockRejectsUnsafePaths() throws {
        let directory = try disposableDirectory("unsafe-lock")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        chmod(directory.path, 0o755)
        #expect(throws: ManagerFileLockError.unsafeDirectory) {
            try ManagerFileLock.acquire(directory: directory.path)
        }
        chmod(directory.path, 0o700)
        let target = directory.appendingPathComponent("target")
        try Data().write(to: target)
        try FileManager.default.createSymbolicLink(
            at: directory.appendingPathComponent("claude-login.lock"), withDestinationURL: target
        )
        #expect(throws: ManagerFileLockError.unsafeFile) {
            try ManagerFileLock.acquire(directory: directory.path)
        }
    }

    @Test("W5 routing derives the exact default service and OS account")
    func routingAcceptsOnlyVerifiedDefaults() throws {
        let base = ClaudeRoutingEvidence.testing(environmentUser: "fixture-user")
        #expect(try ClaudeRoutingValidator.route(base) == .init(
            service: "Claude Code-credentials", account: "fixture-user",
            configurationPath: "/synthetic/home/.claude.json"
        ))
        #expect(try ClaudeRoutingValidator.route(.testing(environmentUser: nil)).account == "os-fixture")
        #expect(try ClaudeRoutingValidator.route(.testing(environmentUser: "bad user")).account == "claude-code-user")
    }

    @Test("W5 routing fails closed on unsupported evidence", arguments: RoutingRejection.cases)
    func routingRejectsUnsupportedEvidence(_ rejection: RoutingRejection) {
        #expect(throws: rejection.error) { try ClaudeRoutingValidator.route(rejection.evidence) }
    }

    @Test("Process preflight blocks every same-user Claude host role", arguments: ClaudeProcessRole.allCases)
    func processPreflightBlocksActiveRoles(_ role: ClaudeProcessRole) {
        let process = ClaudeProcessRecord(
            pid: 20, parentPID: 1, uid: 501, executablePath: "/synthetic/host", role: role
        )
        var wrote = false
        #expect(throws: ClaudeProcessPreflightError.active) {
            try ClaudeProcessPreflight.testing([process]).performGuarded(
                write: { wrote = true }, verify: {}
            )
        }
        #expect(!wrote)
    }

    @Test("Process preflight permits other users and checks before write and after verification")
    func processPreflightEnforcesCallingContract() throws {
        var probes = 0
        var phases: [String] = []
        let preflight = ClaudeProcessPreflight(
            expectedUID: 501, trustedExecutablePath: "/synthetic/claude",
            probe: .init(snapshot: { probes += 1; return [
                .init(pid: 30, parentPID: 1, uid: 502, executablePath: "/synthetic/claude", role: .daemon)
            ] })
        )
        try preflight.performGuarded(
            write: { phases.append("write") }, verify: { phases.append("verify") }
        )
        #expect(probes == 2)
        #expect(phases == ["write", "verify"])
        #expect(throws: ClaudeProcessPreflightError.active) {
            try ClaudeProcessPreflight.testing([
                .init(pid: 31, parentPID: 1, uid: 501, executablePath: "/synthetic/claude", role: nil)
            ]).requireQuiescent()
        }
    }

    @Test("Process preflight treats incomplete and cyclic observations as uncertain", arguments: processUncertaintyCases)
    func processPreflightRejectsUncertainty(_ records: [ClaudeProcessRecord]) {
        #expect(throws: ClaudeProcessPreflightError.uncertain) {
            try ClaudeProcessPreflight.testing(records).requireQuiescent()
        }
    }

    @Test("Native process probe reads a supplied self PID")
    func nativeProcessProbeReadsSuppliedSelfPID() throws {
        let probe = NativeProcessProbe.system(processIDs: { [getpid()] })

        let records = try probe.snapshot()
        let record = try #require(records.first)
        let executablePath = try #require(record.executablePath)
        #expect(records.count == 1)
        #expect(record.pid == getpid())
        #expect(record.uid == geteuid())
        #expect(record.parentPID != nil)
        #expect(executablePath.isEmpty == false)
        #expect(throws: ClaudeProcessPreflightError.active) {
            try ClaudeProcessPreflight(expectedUID: geteuid(), trustedExecutablePath: executablePath, probe: probe)
                .requireQuiescent()
        }
    }

    @Test("Native process probe fails closed for an unavailable PID")
    func nativeProcessProbeRejectsUnavailablePID() {
        let probe = NativeProcessProbe.system(processIDs: { [Int32.max] })

        #expect(throws: ClaudeProcessPreflightError.uncertain) { try probe.snapshot() }
    }

    @Test("Native process probe requests short BSD metadata and skips zombie paths")
    func nativeProcessProbeUsesZombieAwareMetadata() throws {
        let fixture = ProcessNativeFixture(status: UInt32(SZOMB))

        let record = try #require(NativeProcessProbe.system(
            processIDs: { [42] }, calls: fixture.calls
        ).snapshot().first)

        #expect(fixture.infoRequests.count == 1)
        #expect(fixture.infoRequests.first?.0 == PROC_PIDT_SHORTBSDINFO)
        #expect(fixture.infoRequests.first?.1 == 1)
        #expect(fixture.pathCalls == 0)
        #expect(record.executablePath == nil)
    }

    @Test("Native process inventory rejects uncertain native results", arguments: InventoryFailure.allCases)
    func nativeProcessInventoryRejectsUncertainResults(_ failure: InventoryFailure) {
        let fixture = ProcessNativeFixture(inventoryFailure: failure)
        var writes = 0

        #expect(throws: ClaudeProcessPreflightError.uncertain) {
            try ClaudeProcessPreflight(
                expectedUID: 501, trustedExecutablePath: "/synthetic/claude",
                probe: NativeProcessProbe.system(calls: fixture.calls)
            ).performGuarded(write: { writes += 1 }, verify: {})
        }
        #expect(writes == 0)
    }

    @Test("Native process inventory accepts an under-capacity result and ignores kernel PID zero")
    func nativeProcessInventoryAcceptsBoundedResult() throws {
        let fixture = ProcessNativeFixture()

        let records = try NativeProcessProbe.system(calls: fixture.calls).snapshot()

        #expect(records.map(\.pid) == [42])
    }

    @Test("Native process metadata rejects incomplete or mismatched results", arguments: MetadataFailure.allCases)
    func nativeProcessMetadataRejectsUncertainResults(_ failure: MetadataFailure) {
        let fixture = ProcessNativeFixture(metadataFailure: failure)
        var writes = 0

        #expect(throws: ClaudeProcessPreflightError.uncertain) {
            try ClaudeProcessPreflight(
                expectedUID: 501, trustedExecutablePath: "/synthetic/claude",
                probe: NativeProcessProbe.system(processIDs: { [42] }, calls: fixture.calls)
            ).performGuarded(write: { writes += 1 }, verify: {})
        }
        #expect(writes == 0)
    }

    @Test("Every non-zombie process requires a valid executable path", arguments: PathFailure.allCases)
    func nativeProcessProbeRejectsInvalidPaths(_ failure: PathFailure) {
        let fixture = ProcessNativeFixture(pathFailure: failure)
        var writes = 0

        #expect(throws: ClaudeProcessPreflightError.uncertain) {
            try ClaudeProcessPreflight(
                expectedUID: 501, trustedExecutablePath: "/synthetic/claude",
                probe: NativeProcessProbe.system(processIDs: { [42] }, calls: fixture.calls)
            ).performGuarded(write: { writes += 1 }, verify: {})
        }
        #expect(writes == 0)
    }

    @Test("Stopped, exiting, root, and foreign live processes still require paths", arguments: liveMetadataCases)
    func nativeProcessProbeReadsEveryLivePath(_ metadata: LiveMetadataCase) throws {
        let fixture = ProcessNativeFixture(status: metadata.status, flags: metadata.flags, uid: metadata.uid)

        let records = try NativeProcessProbe.system(processIDs: { [42] }, calls: fixture.calls).snapshot()

        #expect(records.first?.executablePath == "/synthetic/live")
        #expect(fixture.pathCalls == 1)
    }

    @Test("A process whose executable was deleted is identified by its command name")
    func deletedExecutableIsIdentifiedByName() throws {
        func preflight(_ name: String) -> ClaudeProcessPreflight {
            .init(expectedUID: 501, trustedExecutablePath: "/synthetic/claude", probe: .system(
                processIDs: { [42] }, calls: ProcessNativeFixture(deletedExecutableName: name).calls
            ))
        }
        let record = try #require(preflight("chrome_crashpad").probe.snapshot().first)
        #expect(record.executablePath == nil)
        #expect(record.deletedExecutableName == "chrome_crashpad")
        try preflight("chrome_crashpad").requireQuiescent()
        #expect(throws: ClaudeProcessPreflightError.active) { try preflight("2.1.274").requireQuiescent() }
        #expect(throws: ClaudeProcessPreflightError.active) { try preflight("claude").requireQuiescent() }
        #expect(throws: ClaudeProcessPreflightError.uncertain) { try preflight("").requireQuiescent() }
    }

    @Test("Zombie ancestry still reaches a recognized same-user live ancestor")
    func processPreflightPreservesZombieAncestry() {
        let records = [
            ClaudeProcessRecord(pid: 50, parentPID: 51, uid: 501, executablePath: "/synthetic/child", role: nil),
            ClaudeProcessRecord(pid: 51, parentPID: 52, uid: 501, executablePath: nil, role: nil, isZombie: true),
            ClaudeProcessRecord(pid: 52, parentPID: 1, uid: 501, executablePath: "/synthetic/host", role: .editor)
        ]

        #expect(throws: ClaudeProcessPreflightError.active) {
            try ClaudeProcessPreflight.testing(records).requireQuiescent()
        }
    }

    @Test("Zombie records cannot carry a path or classified role")
    func processPreflightRejectsMalformedZombies() {
        #expect(throws: ClaudeProcessPreflightError.uncertain) {
            try ClaudeProcessPreflight.testing([
                .init(pid: 60, parentPID: 1, uid: 501, executablePath: "/synthetic/zombie", role: nil, isZombie: true)
            ]).requireQuiescent()
        }
        #expect(throws: ClaudeProcessPreflightError.uncertain) {
            try ClaudeProcessPreflight.testing([
                .init(pid: 61, parentPID: 1, uid: 501, executablePath: nil, role: .daemon, isZombie: true)
            ]).requireQuiescent()
        }
    }

    @Test("An ancestry cycle remains uncertain when it crosses a zombie")
    func processPreflightRejectsZombieCycle() {
        #expect(throws: ClaudeProcessPreflightError.uncertain) {
            try ClaudeProcessPreflight.testing([
                .init(pid: 70, parentPID: 71, uid: 501, executablePath: "/synthetic/live", role: nil),
                .init(pid: 71, parentPID: 70, uid: 501, executablePath: nil, role: nil, isZombie: true)
            ]).requireQuiescent()
        }
    }

    @Test("App adapter lists only sorted safe alias state through manager-only scope")
    func appAdapterProjectsManagerState() async throws {
        let directory = try disposableDirectory("app-adapter")
        let state = ClaudeLoginState(
            snapshots: ["beta": try snapshot(account: "b", accessToken: "", refreshToken: ""),
                        "alpha": try snapshot(account: "a")], activeAlias: "beta"
        )
        let data = try ClaudeLoginEnvelopeCodec().encode(state)
        let adapter = ClaudeLoginAppAdapter(makeBackend: {
            let custody = ClaudeLoginCustody(store: MemoryClaudeLoginDataStore(data: data))
            return CommandScopedClaudeLoginBackend(
                acquireLock: { try ManagerFileLock.acquire(directory: directory.path) },
                routingEvidence: { .testing() },
                readCustody: { custody },
                writeCustody: { _, _ in custody },
                processPreflight: safeProcessPreflight(),
                currentSnapshot: { _ in Issue.record("list captured Claude state"); throw FixtureError() },
                selectionResources: { _ in .init(
                    readRoots: { Issue.record("unknown alias read resources"); throw FixtureError() },
                    replaceSecure: { _, _, _ in }, replaceConfiguration: { _, _, _ in }
                ) }
            )
        })

        #expect(await adapter.list() == .listed(.init(
            aliases: [.init(name: "alpha", requiresReLogin: false), .init(name: "beta", requiresReLogin: true)],
            lastSelectedHint: "beta"
        )))
        #expect(await ClaudeLoginAppAdapter().list() == .backendUnavailable)
        #expect(await adapter.use(alias: "missing") == .unknownAlias)
        try FileManager.default.removeItem(at: directory)
        #expect(FileManager.default.fileExists(atPath: directory.path) == false)
    }

    @Test("App adapter serializes commands and maps completion without cancellation shortcuts")
    func appAdapterSerializesSafeOutcomes() async {
        let adapter = ClaudeLoginAppAdapter(makeBackend: { AppResultBackend() })
        async let use = adapter.use(alias: "alpha")
        async let recovery = adapter.recover()
        #expect(await [use, recovery] == [.verifiedApplied("alpha"), .recoveryChecked])
        let cancelled = Task { await adapter.use(alias: "beta") }
        cancelled.cancel()
        #expect(await cancelled.value == .verifiedApplied("beta"))
        #expect(await ClaudeLoginAppAdapter(makeBackend: { AppResultBackend(cleanupUncertain: true) })
            .use(alias: "alpha") == .postCommitCleanupUncertain)
    }

    @Test("App adapter holds the real manager lock across use and recovery callbacks, then releases it")
    func appAdapterHoldsAndReleasesManagerLock() async throws {
        let use = try SelectionFixture(verifyLockContention: true)
        defer { use.cleanup() }
        #expect(await use.runApp { await $0.use(alias: "beta") } == .verifiedApplied("beta"))
        #expect(use.boundaryEvents.contains("replace-configuration"))
        #expect(use.boundaryEvents.contains("process-12"))
        #expect(try use.custody.load().activeAlias == "beta")
        #expect(use.resources.secureRoot == use.betaSecure)
        use.cleanup()

        let recovery = try SelectionFixture(verifyLockContention: true)
        defer { recovery.cleanup() }
        var expectedState = try recovery.preparePendingRecovery()
        expectedState.journal = nil
        #expect(await recovery.runApp { await $0.recover() } == .recoveryChecked)
        #expect(recovery.boundaryEvents.contains("replace-secure"))
        #expect(try recovery.custody.load() == expectedState)
        recovery.cleanup()
    }

    @Test("App adapter finishes a use cancelled mid-transaction without partial state or a false result")
    func appAdapterCompletesUseCancelledMidTransaction() async throws {
        let fixture = try SelectionFixture(verifyLockContention: true)
        defer { fixture.cleanup() }
        var cancelledAfter: String?
        fixture.onCommandEvent = { [unowned fixture] in
            guard cancelledAfter == nil, fixture.boundaryEvents.last == "replace-secure" else { return }
            withUnsafeCurrentTask { $0?.cancel() }
            cancelledAfter = fixture.boundaryEvents.last
        }
        let outcome = await Task { () -> (ClaudeLoginAppResult, Bool) in
            let result = await fixture.runApp { await $0.use(alias: "beta") }
            return (result, Task.isCancelled)
        }.value
        fixture.onCommandEvent = nil

        #expect(cancelledAfter == "replace-secure")
        #expect(outcome.1)
        #expect(outcome.0 == .verifiedApplied("beta"))
        #expect(fixture.boundaryEvents.drop { $0 != "replace-secure" }.contains("replace-configuration"))
        #expect(fixture.boundaryEvents.contains("process-12"))
        let state = try fixture.custody.load()
        #expect(state.activeAlias == "beta" && state.journal == nil)
        #expect(fixture.resources.secureRoot == fixture.betaSecure)
        #expect(fixture.resources.configurationRoot == fixture.betaConfiguration)
    }

    @Test("Store switches a saved login through the guarded backend and publishes no secrets")
    @MainActor
    func storeSwitchesThroughGuardedBackend() async throws {
        let fixture = try SelectionFixture()
        defer { fixture.cleanup() }
        let backend = fixture.backend
        let store = ControlStore(claudeLogins: ClaudeLoginAppAdapter(makeBackend: { backend }))

        try await #require(store.reloadClaudeLogins()).value
        #expect(store.claudeLogins == .loaded(.init(aliases: [
            .init(name: "alpha", requiresReLogin: false), .init(name: "beta", requiresReLogin: false)
        ], lastSelectedHint: "alpha")))
        try await #require(store.selectClaudeLogin("beta")).value

        #expect(store.claudeNotice?.text == "Switched Claude to beta.")
        #expect(try fixture.custody.load().activeAlias == "beta")
        #expect(fixture.resources.secureRoot == fixture.betaSecure)
        let published = "\(store.claudeLogins) \(String(describing: store.claudeNotice))"
        for secret in ["accessToken", "RB", "account-b", "org-b"] { #expect(!published.contains(secret)) }
    }
    @Test("Storage contract accepts reviewed Claude Code builds whatever their minified names")
    func storageContractAcceptsReviewedBuilds() {
        for names in StorageDerivation.reviewedNames {
            #expect(ClaudeStorageContract.matches(StorageDerivation.binary(names)))
        }
    }

    @Test("Storage contract refuses changed, missing, or duplicated credential derivation", arguments: StorageDerivation.Change.allCases)
    func storageContractRefusesChanges(_ change: StorageDerivation.Change) {
        #expect(ClaudeStorageContract.matches(change.binary) == false)
    }

    @Test(
        "Opt-in: installed Claude Code builds satisfy the storage contract",
        .enabled(if: ProcessInfo.processInfo.environment["AI_CONTROL_CLAUDE_BINARIES"] != nil)
    )
    func installedBuildsSatisfyStorageContract() {
        let paths = ProcessInfo.processInfo.environment["AI_CONTROL_CLAUDE_BINARIES"]?.split(separator: ":") ?? []
        #expect(!paths.isEmpty)
        for path in paths { #expect(ClaudeStorageContract.matches(executableAt: String(path)), "\(path)") }
    }

    @Test("Live routing reports overrides, alternate auth, and legacy files as conflicts")
    func liveRoutingReportsConflicts() throws {
        let clean = LiveSystemFixture().system.routingEvidence()
        #expect(clean.storageContractVerified)
        #expect(clean.conflicts.isEmpty)
        #expect(clean.resolvedConfigurationPath == "/home/me/.claude.json")
        #expect(clean.defaultConfigurationPath == "/home/me/.claude.json")
        #expect(clean.environmentUser == "me")
        #expect(try ClaudeRoutingValidator.route(clean) == .init(
            service: "Claude Code-credentials", account: "me", configurationPath: "/home/me/.claude.json"
        ))

        let cases: [(LiveSystemFixture, ClaudeRoutingConflict)] = [
            (.init(environment: ["CLAUDE_CONFIG_DIR": "/elsewhere"]), .configurationOverride),
            (.init(environment: ["CLAUDE_SECURESTORAGE_CONFIG_DIR": ""]), .secureStorageOverride),
            (.init(environment: ["CLAUDE_CODE_CUSTOM_OAUTH_URL": "https://x"]), .customOAuth),
            (.init(environment: ["CLAUDE_CODE_OAUTH_CLIENT_ID": "id"]), .customOAuth),
            (.init(environment: ["ANTHROPIC_API_KEY": "k"]), .alternateAuthentication),
            (.init(environment: ["CLAUDE_CODE_OAUTH_TOKEN": "t"]), .alternateAuthentication),
            (.init(environment: ["CLAUDE_CODE_USE_BEDROCK": "1"]), .alternateAuthentication),
            (.init(files: ["/home/me/.claude/.credentials.json"]), .plaintextFallback),
            (.init(files: ["/home/me/.claude/.config.json"]), .legacyStorage)
        ]
        for (fixture, conflict) in cases {
            #expect(fixture.system.routingEvidence().conflicts == [conflict])
        }
    }

    @Test("Live routing verifies only a native-installer build whose storage contract matches")
    func liveRoutingRequiresVerifiedNativeBuild() {
        #expect(LiveSystemFixture().checkedExecutables == ["/home/me/.local/share/claude/versions/2.1.282"])
        #expect(LiveSystemFixture(contractMatches: false).system.routingEvidence().storageContractVerified == false)
        #expect(LiveSystemFixture(executable: nil).system.routingEvidence().storageContractVerified == false)
        let foreign = LiveSystemFixture(executable: "/opt/homebrew/lib/node_modules/claude/cli.js")
        #expect(foreign.system.routingEvidence().storageContractVerified == false)
        #expect(foreign.checkedExecutables.isEmpty)
    }

    @Test("Process preflight treats any installed Claude version as active")
    func preflightDetectsEveryInstalledVersion() throws {
        func preflight(_ path: String) -> ClaudeProcessPreflight {
            .init(expectedUID: 501, trustedExecutablePath: "/v/2.1.282", probe: .init(snapshot: {
                [.init(pid: 9, parentPID: 1, uid: 501, executablePath: path, role: nil)]
            }), trustedExecutableDirectory: "/v")
        }
        #expect(throws: ClaudeProcessPreflightError.active) { try preflight("/v/2.1.274").requireQuiescent() }
        #expect(throws: ClaudeProcessPreflightError.active) { try preflight("/v/2.1.282").requireQuiescent() }
        try preflight("/vx/2.1.274").requireQuiescent()
        try preflight("/usr/bin/zsh").requireQuiescent()
    }

    @Test("Live configuration replacement writes owned fields only and refuses other edits")
    func liveConfigurationReplacementIsScoped() throws {
        let source = #"{"oauthAccount":{"accountUuid":"a"},"keep":900719925474099312345,"modelAccessCache":2}"#
        let fixture = try ConfigurationFixture(source)
        defer { fixture.cleanup() }
        let file = ProtectedConfigurationFile(path: fixture.file.path)
        let replacement = try ScopedJSON(source).replacing([
            "oauthAccount": .value(#"{"accountUuid":"b"}"#), "modelAccessCache": .missing
        ])
        var guards = 0

        try ClaudeLiveSystem.replaceConfiguration(file, expected: source, replacement: replacement) { guards += 1 }

        #expect(try String(contentsOf: fixture.file, encoding: .utf8) == replacement)
        #expect(guards == 1)
        let foreign = try ScopedJSON(replacement).replacing(["keep": .value("1")])
        #expect(throws: ClaudeLoginSelectionError.changedRoots) {
            try ClaudeLiveSystem.replaceConfiguration(file, expected: replacement, replacement: foreign) { guards += 1 }
        }
        #expect(try String(contentsOf: fixture.file, encoding: .utf8) == replacement)
        #expect(guards == 1)
        let restored = try ScopedJSON(replacement).replacing(["modelAccessCache": .value("2")])
        try ClaudeLiveSystem.replaceConfiguration(file, expected: replacement, replacement: restored) {}
        #expect(try String(contentsOf: fixture.file, encoding: .utf8) == restored)
    }

    @Test("A running Claude session refuses the switch with a distinct result")
    func appAdapterReportsRunningClaude() async {
        let adapter = ClaudeLoginAppAdapter(makeBackend: { AppResultBackend(selectionError: ClaudeProcessPreflightError.active) })
        #expect(await adapter.use(alias: "alpha") == .claudeRunning)
    }

    @Test("Terminal commands explain a running Claude and an unreviewed Claude build")
    func commandsExplainRunningClaudeAndUnreviewedBuild() {
        var messages: [String] = []
        for error in [ClaudeProcessPreflightError.active as Error, ClaudeRoutingError.unsupportedBuild] {
            #expect(runClaudeLogins(arguments: ["claude-login", "use", "alpha"], makeBackend: {
                AppResultBackend(selectionError: error)
            }, output: { messages.append($0) }, runGUI: {}) == 3)
        }
        #expect(messages == [
            "Blocked: Claude Code is running; quit every session and try again.",
            "Blocked: this Claude Code build stores logins differently from reviewed builds."
        ])
    }

    @Test("Security tool item reads text or hex passwords and maps missing items")
    func securityToolItemReads() throws {
        let tool = FakeSecurityTool(responses: [(0, Data("{\"a\":1}\n".utf8)), (0, Data("7b2262223a327d\n".utf8)), (44, Data())])
        let item = SecurityToolKeychainItem(service: "Claude Code-credentials", account: "me", run: tool.run)
        #expect(try item.read() == Data(#"{"a":1}"#.utf8))
        #expect(try item.read() == Data(#"{"b":2}"#.utf8))
        #expect(throws: IsolatedKeychainError.missing) { try item.read() }
        #expect(tool.calls.first?.arguments == ["find-generic-password", "-a", "me", "-s", "Claude Code-credentials", "-w"])
        #expect(tool.calls.allSatisfy { $0.input == nil })
    }

    @Test("Security tool item sends small payloads on stdin and large ones like Claude Code")
    func securityToolItemWritesLikeClaude() throws {
        let tool = FakeSecurityTool(responses: [(0, Data()), (0, Data())])
        let item = SecurityToolKeychainItem(service: "Claude Code-credentials", account: "me", run: tool.run)
        try item.create(data: Data("{}".utf8), guardedBy: {})
        let large = Data(repeating: 0x61, count: 3000)
        try item.create(data: large, guardedBy: {})

        #expect(tool.calls[0].arguments == ["-i"])
        #expect(tool.calls[0].input == Data(#"add-generic-password -a "me" -s "Claude Code-credentials" -X "7b7d""#.utf8 + [0x0A]))
        #expect(tool.calls[1].arguments.prefix(5) == ["add-generic-password", "-a", "me", "-s", "Claude Code-credentials"])
        #expect(tool.calls[1].arguments.last == String(repeating: "61", count: 3000))
        #expect(tool.calls[1].input == nil)
        #expect(throws: IsolatedKeychainError.corrupt) {
            try SecurityToolKeychainItem(service: "x", account: #"a" -s "b"#, run: tool.run).create(data: Data(), guardedBy: {})
        }
    }

    @Test("Security tool replace compares before its guard and writes only after it")
    func securityToolItemReplaceOrdersGuard() throws {
        var events: [String] = []
        let tool = FakeSecurityTool(responses: [(0, Data("{\"a\":1}".utf8)), (0, Data()), (0, Data("{\"a\":2}".utf8))])
        tool.onCall = { events.append($0.arguments.first ?? "") }
        let item = SecurityToolKeychainItem(service: "Claude Code-credentials", account: "me", run: tool.run)

        try item.replace(expectedData: Data(#"{"a":1}"#.utf8), with: Data(#"{"b":1}"#.utf8)) { events.append("guard") }
        #expect(events == ["find-generic-password", "guard", "-i"])
        #expect(tool.calls[1].input.map { String(decoding: $0, as: UTF8.self) }?.hasPrefix("add-generic-password -U ") == true)
        #expect(throws: IsolatedKeychainError.corrupt) {
            try item.replace(expectedData: Data(#"{"a":1}"#.utf8), with: Data()) { events.append("late guard") }
        }
        #expect(!events.contains("late guard"))
    }

    @Test("Manager store reads a legacy item without writing and migrates it on the first update")
    func managerStoreMigratesLegacyItem() throws {
        let tool = FakeSecurityTool(responses: [(44, Data()), (44, Data()), (0, Data())])
        var legacyDeleted = false
        let store = MigratingKeychainStore(
            primary: .init(service: "AIControl-claude-logins.v2", account: "501", run: tool.run),
            legacyRead: { Data("{\"v\":1}".utf8) }, legacyDelete: { legacyDeleted = true }
        )
        #expect(try store.read() == Data(#"{"v":1}"#.utf8))
        #expect(tool.calls.count == 1 && !legacyDeleted)

        var guards = 0
        try store.update(data: Data(#"{"v":2}"#.utf8)) { guards += 1 }
        #expect(guards == 1 && legacyDeleted)
        #expect(tool.calls.last?.input.map { String(decoding: $0, as: UTF8.self) }?.hasPrefix("add-generic-password -a ") == true)
    }

    @Test("Process preflight treats any executable named claude as a running Claude session")
    func preflightDetectsEmbeddedClaude() throws {
        func preflight(_ path: String) -> ClaudeProcessPreflight {
            .init(expectedUID: 501, trustedExecutablePath: "/v/2.1.282", probe: .init(snapshot: {
                [.init(pid: 9, parentPID: 1, uid: 501, executablePath: path, role: nil)]
            }), trustedExecutableDirectory: "/v")
        }
        #expect(throws: ClaudeProcessPreflightError.active) {
            try preflight("/home/me/.pi/agent/npm/node_modules/@anthropic-ai/claude-agent-sdk-darwin-arm64/claude").requireQuiescent()
        }
        try preflight("/Applications/Claude.app/Contents/MacOS/Claude").requireQuiescent()
        try preflight("/usr/local/bin/claudette").requireQuiescent()
    }

    @Test("After a native login to another saved account, switching re-saves that account, never the last-applied one")
    func nativeLoginIsCheckpointedUnderItsOwnAlias() throws {
        let fixture = try SelectionFixture()
        defer { fixture.cleanup() }
        let saved = try fixture.custody.load()
        #expect(saved.activeAlias == "alpha")
        let renewedBeta = fixture.betaSecure.replacingOccurrences(of: #""accessToken":"B""#, with: #""accessToken":"B2""#)
        fixture.resources.secureRoot = renewedBeta
        fixture.resources.configurationRoot = fixture.betaConfiguration

        #expect(fixture.run(alias: "alpha") == 0, "\(fixture.messages)")
        let state = try fixture.custody.load()
        #expect(state.snapshots["alpha"] == saved.snapshots["alpha"])
        #expect(state.snapshots["beta"]?.claudeAiOauth == (try ClaudeLoginSnapshot.capture(
            secureRoot: renewedBeta, configurationRoot: fixture.betaConfiguration
        )).claudeAiOauth)
        #expect(fixture.resources.secureRoot.contains(#""accessToken":"A1""#))
    }

    @Test("Open Claude sessions are allowed when the preflight permits them")
    func preflightCanPermitOpenSessions() throws {
        let running = [ClaudeProcessRecord(pid: 9, parentPID: 1, uid: 501, executablePath: "/v/claude", role: nil)]
        var preflight = ClaudeProcessPreflight.testing(running)
        #expect(throws: ClaudeProcessPreflightError.active) { try preflight.requireQuiescent() }
        preflight.permitsOpenSessions = true
        try preflight.requireQuiescent()
    }

    @Test("Live switching stays off unless explicitly enabled")
    func liveSwitchingStaysOffByDefault() async {
        #expect(ClaudeLiveSystem.isEnabled(environment: [:]) == false)
        #expect(ClaudeLiveSystem.isEnabled(environment: ["AI_CONTROL_CLAUDE_LIVE": "true"]) == false)
        #expect(ClaudeLiveSystem.isEnabled(environment: ["AI_CONTROL_CLAUDE_LIVE": "1"]))
        #expect(await ClaudeLoginAppAdapter.configured(environment: [:]).list() == .backendUnavailable)
    }
}

private struct AppResultBackend: ClaudeLoginBackend {
    var cleanupUncertain = false
    var selectionError: Error?
    func loadState() throws -> ClaudeLoginState { .init() }
    func currentSnapshot() throws -> ClaudeLoginSnapshot { throw FixtureError() }
    func saveState(_: ClaudeLoginState) throws {}
    func selectAlias(_: String) throws {
        if let selectionError { throw selectionError }
        if cleanupUncertain { throw ClaudeLoginSelectionError.cleanupUncertain }
    }
    func recoverPendingLogin() throws {}
}

private extension IsolatedKeychainAdapter {
    static func testing(status: OSStatus = errSecSuccess, result: CFTypeRef? = nil) -> Self {
        let calls = KeychainNativeCalls(
            copy: { _, output in output?.pointee = result; return status },
            add: { _ in status }, update: { _, _ in status }, delete: { _ in status }
        )
        return .init(
            keychain: NSObject(), service: "AIControl-claude-logins.v1.test-unit",
            account: "synthetic-account", calls: calls
        )
    }
}

private func sameKeychainList(_ lhs: [SecKeychain], _ rhs: [SecKeychain]) -> Bool {
    lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { CFEqual($0, $1) }
}

private struct FixtureError: Error {}

enum RecoveryCertaintyFailure: CaseIterable {
    case secureReadback, configurationReadback, secureMismatch, configurationMismatch
    case clearWrite, clearReadback

    var selectionFailure: SelectionFailure? {
        switch self { case .secureReadback: .secureReadback; case .configurationReadback: .configurationReadback; default: nil }
    }
    var retainsJournal: Bool { self != .clearReadback }
    fileprivate func arrange(_ fixture: SelectionFixture) {
        switch self {
        case .secureMismatch: fixture.resources.mismatchAtRead = 2
        case .configurationMismatch: fixture.resources.mismatchAtRead = 3
        case .clearWrite: fixture.store.failedUpdateOverride = fixture.store.updateCount + 1
        case .clearReadback: fixture.store.failedReadOverride = fixture.store.readCount + 3
        default: break
        }
    }
}

enum SelectionFailure: CaseIterable {
    case checkpointWrite, checkpointReadback, prepareWrite, prepareReadback, rootsChanged
    case secureWrite, secureReadback, secureVerificationMismatch, secureVerificationRead
    case configurationWrite, configurationReadback, combinedVerification
    case commitWrite, commitReadback, clearWrite, clearReadback, finalProcess
    case preparePostVerificationRead, commitPostVerificationRead

    static let journalCases: [Self] = [.rootsChanged, .secureWrite, .configurationWrite]
    static let securePostimageCases: [Self] = [.secureVerificationMismatch, .secureVerificationRead]
    static let certaintyReadCases: [Self] = [.preparePostVerificationRead, .commitPostVerificationRead]

    var failedRead: Int? {
        switch self {
        case .checkpointReadback: 3
        case .prepareReadback: 6
        case .preparePostVerificationRead: 7
        case .commitReadback: 9
        case .commitPostVerificationRead: 10
        case .clearReadback: 12
        default: nil
        }
    }
    var failedUpdate: Int? {
        switch self { case .checkpointWrite: 1; case .prepareWrite: 2; case .commitWrite: 3; case .clearWrite: 4; default: nil }
    }
    var mutatesBeforeFailure: Bool { self == .checkpointReadback || self == .prepareReadback || self == .commitReadback || self == .clearReadback }
    var expectedExit: Int32 { switch self { case .checkpointWrite, .checkpointReadback, .prepareWrite, .prepareReadback: 3; case .commitPostVerificationRead, .clearWrite, .clearReadback, .finalProcess: 3; default: 4 } }
    var expectedManagerWrites: Int { failedUpdate ?? (failedRead.map { [3: 1, 6: 2, 7: 2, 9: 3, 10: 3, 12: 4][$0]! } ?? (self == .finalProcess ? 4 : 2)) }
    var expectedDurableStateIndex: Int {
        switch self {
        case .checkpointWrite: 0
        case .checkpointReadback, .prepareWrite: 1
        case .commitReadback, .commitPostVerificationRead, .clearWrite: 3
        case .clearReadback, .finalProcess: 4
        default: 2
        }
    }
    var expectedBoundaryEventCount: Int {
        switch self {
        case .checkpointWrite: 6
        case .checkpointReadback: 7
        case .prepareWrite: 12
        case .prepareReadback: 13
        case .preparePostVerificationRead: 14
        case .rootsChanged: 16
        case .secureWrite, .secureReadback: 18
        case .secureVerificationMismatch, .secureVerificationRead: 19
        case .configurationWrite, .configurationReadback: 21
        case .combinedVerification: 22
        case .commitWrite: 26
        case .commitReadback: 27
        case .commitPostVerificationRead: 28
        case .clearWrite: 32
        case .clearReadback: 33
        case .finalProcess: 35
        }
    }
    var expectedPhase: ClaudeLoginJournalPhase? {
        switch self { case .checkpointWrite: nil; case .checkpointReadback: nil; case .prepareWrite: nil; case .prepareReadback: .pending; case .commitReadback, .commitPostVerificationRead, .clearWrite: .committed; case .clearReadback, .finalProcess: nil; default: .pending }
    }
    var expectedResourceEvents: [String] {
        switch self {
        case .checkpointWrite, .checkpointReadback, .prepareWrite, .prepareReadback, .preparePostVerificationRead, .rootsChanged: []
        case .secureWrite: ["secure-write"]
        case .secureReadback, .secureVerificationMismatch, .secureVerificationRead: ["secure-write", "secure-readback"]
        case .configurationWrite: ["secure-write", "secure-readback", "configuration-write"]
        case .configurationReadback: ["secure-write", "secure-readback", "configuration-write", "configuration-readback"]
        default: ["secure-write", "secure-readback", "configuration-write", "configuration-readback"]
        }
    }
    var expectedMessage: String { expectedExit == 4 ? "Recovery required before selecting another alias." : expectedPhase == .committed || self == .clearReadback || self == .finalProcess ? "Blocked: selection applied but cleanup is uncertain." : "Blocked: credential backend unavailable." }
}

enum DirectPersistenceCertaintyFailure: CaseIterable {
    case preparationPostguard, commitPostguard

    var failedCheck: Int { self == .preparationPostguard ? 5 : 10 }
    var expectedExit: Int32 { self == .preparationPostguard ? 4 : 3 }
    var expectedManagerWrites: Int { self == .preparationPostguard ? 2 : 3 }
    var expectedPhase: ClaudeLoginJournalPhase { self == .preparationPostguard ? .pending : .committed }
    var expectedMessage: String {
        self == .preparationPostguard
            ? "Recovery required before selecting another alias."
            : "Blocked: selection applied but cleanup is uncertain."
    }
}

enum SelectionGuardFailure: CaseIterable {
    case beforeCapture, beforeCheckpointMutation, beforeSecureMutation, afterCombinedVerification

    var failedCheck: Int { switch self { case .beforeCapture: 1; case .beforeCheckpointMutation: 2; case .beforeSecureMutation: 6; case .afterCombinedVerification: 8 } }
    var expectedExit: Int32 { switch self { case .beforeCapture, .beforeCheckpointMutation: 3; case .beforeSecureMutation, .afterCombinedVerification: 4 } }
    var expectedManagerWrites: Int { switch self { case .beforeCapture, .beforeCheckpointMutation: 0; case .beforeSecureMutation, .afterCombinedVerification: 2 } }
    var expectedResourceEvents: [String] { self == .afterCombinedVerification ? ["secure-write", "secure-readback", "configuration-write", "configuration-readback"] : [] }
    var expectedPhase: ClaudeLoginJournalPhase? { expectedManagerWrites == 0 ? nil : .pending }
    var preservesManagerPreimage: Bool { expectedManagerWrites == 0 }
    var preservesSecurePreimage: Bool { self != .afterCombinedVerification }
    var preservesConfigurationPreimage: Bool { self != .afterCombinedVerification }
    var expectedBoundaryEvents: [String] {
        switch self {
        case .beforeCapture:
            ["manager-read", "process-1"]
        case .beforeCheckpointMutation:
            ["manager-read", "process-1", "capture-roots", "manager-read", "process-2"]
        case .beforeSecureMutation:
            ["manager-read", "process-1", "capture-roots", "manager-read", "process-2", "manager-update", "manager-read", "manager-read", "process-3", "manager-read", "process-4", "manager-update", "manager-read", "manager-read", "process-5", "read-roots", "replace-secure", "process-6"]
        case .afterCombinedVerification:
            ["manager-read", "process-1", "capture-roots", "manager-read", "process-2", "manager-update", "manager-read", "manager-read", "process-3", "manager-read", "process-4", "manager-update", "manager-read", "manager-read", "process-5", "read-roots", "replace-secure", "process-6", "read-roots", "replace-configuration", "process-7", "read-roots", "process-8"]
        }
    }
}

enum UnsupportedSelectionRoot: CaseIterable { case enterpriseGateway, designOauth }

enum SelectionAdmissionRefusal: CaseIterable {
    case missingResource, ambiguousResource, duplicateJSONKeys, ambiguousIdentity, unmatchedIdentity, duplicateStoredIdentity

    var expectedBoundaryEvents: [String] {
        switch self {
        case .duplicateStoredIdentity: ["manager-read"]
        default: ["manager-read", "process-1", "capture-roots"]
        }
    }

    fileprivate func arrange(_ fixture: SelectionFixture) throws {
        switch self {
        case .missingResource:
            fixture.resources.initialReadError = .missing
        case .ambiguousResource:
            fixture.resources.initialReadError = .ambiguous
        case .duplicateJSONKeys:
            fixture.resources.secureRoot = #"{"claudeAiOauth":{},"claudeAiOauth":{}}"#
        case .ambiguousIdentity:
            fixture.resources.configurationRoot = #"{"oauthAccount":{},"sentinel":"keep"}"#
        case .unmatchedIdentity:
            fixture.resources.secureRoot = #"{"claudeAiOauth":{"accessToken":"C","refreshToken":"RC"},"sentinel":"secure"}"#
            fixture.resources.configurationRoot = #"{"oauthAccount":{"accountUuid":"account-c"},"sentinel":"keep"}"#
        case .duplicateStoredIdentity:
            fixture.store.data = try UnsafeEnvelopeCase.duplicateIdentity.data()
        }
    }
}

enum DeadOutgoingCredentials: CaseIterable {
    case missing, null, empty

    var secureRoot: String {
        switch self {
        case .missing: #"{"sentinel":"secure","huge":900719925474099312345}"#
        case .null: #"{"claudeAiOauth":null,"sentinel":"secure","huge":900719925474099312345}"#
        case .empty: #"{"claudeAiOauth":{"accessToken":"","refreshToken":"","expiresAt":0},"sentinel":"secure","huge":900719925474099312345}"#
        }
    }

    var expectedBetaSecure: String {
        switch self {
        case .missing: #"{"sentinel":"secure","huge":900719925474099312345,"claudeAiOauth":{"accessToken":"B","refreshToken":"RB"},"organizationUuid":"org-b","trustedDeviceToken":null}"#
        case .null, .empty: #"{"claudeAiOauth":{"accessToken":"B","refreshToken":"RB"},"sentinel":"secure","huge":900719925474099312345,"organizationUuid":"org-b","trustedDeviceToken":null}"#
        }
    }
}

private final class SelectionDataStore: ClaudeLoginDataStore {
    var data: Data
    let failure: SelectionFailure?
    private(set) var readCount = 0
    private(set) var updateCount = 0
    private(set) var updatePayloads: [Data] = []
    var failedReadOverride: Int?
    var failedUpdateOverride: Int?
    private let onBoundary: (String) -> Void

    init(data: Data, failure: SelectionFailure?, onBoundary: @escaping (String) -> Void = { _ in }) {
        self.data = data
        self.failure = failure
        self.onBoundary = onBoundary
    }
    func read() throws -> Data {
        onBoundary("manager-read")
        readCount += 1
        if (failedReadOverride ?? failure?.failedRead) == readCount { throw FixtureError() }
        return data
    }
    func create(data: Data) throws { throw FixtureError() }
    func update(data: Data) throws {
        onBoundary("manager-update")
        updateCount += 1
        updatePayloads.append(data)
        if (failedUpdateOverride ?? failure?.failedUpdate) == updateCount {
            if failure?.mutatesBeforeFailure == true { self.data = data }
            throw FixtureError()
        }
        self.data = data
    }
}

private struct GuardedSelectionDataStore: ClaudeLoginDataStore {
    let store: SelectionDataStore
    let guardMutation: () throws -> Void
    func read() throws -> Data { try store.read() }
    func create(data: Data) throws { try guardMutation(); try store.create(data: data) }
    func update(data: Data) throws { try guardMutation(); try store.update(data: data) }
}

private final class MemorySelectionResources {
    var secureRoot: String
    var configurationRoot: String
    var events: [String] = []
    private let failure: SelectionFailure?
    private let onBoundary: (String) -> Void
    private(set) var readCount = 0
    var initialReadError: IsolatedKeychainError?
    var changeBeforeSecureWrite = false
    var mismatchAtRead: Int?

    init(
        secureRoot: String, configurationRoot: String, failure: SelectionFailure?,
        onBoundary: @escaping (String) -> Void = { _ in }
    ) {
        self.secureRoot = secureRoot
        self.configurationRoot = configurationRoot
        self.failure = failure
        self.onBoundary = onBoundary
    }

    var io: ClaudeLoginResourceIO {
        .init(
            readRoots: {
                self.onBoundary(self.readCount == 0 ? "capture-roots" : "read-roots")
                self.readCount += 1
                if self.readCount == 1, let error = self.initialReadError { throw error }
                if self.failure == .rootsChanged, self.readCount == 2 { self.secureRoot += " " }
                if self.failure == .secureVerificationRead, self.readCount == 3 { throw FixtureError() }
                if self.failure == .secureVerificationMismatch, self.readCount == 3 { self.secureRoot = self.secureRoot.replacingOccurrences(of: #""B""#, with: #""X""#) }
                if self.failure == .combinedVerification, self.readCount == 4 { self.secureRoot = self.secureRoot.replacingOccurrences(of: #""B""#, with: #""X""#) }
                if self.mismatchAtRead == self.readCount {
                    if self.readCount == 2 { self.secureRoot = self.secureRoot.replacingOccurrences(of: #""A2""#, with: #""X""#) }
                    if self.readCount == 3 { self.configurationRoot = self.configurationRoot.replacingOccurrences(of: "account-a", with: "account-x") }
                }
                return .init(secure: self.secureRoot, configuration: self.configurationRoot)
            },
            replaceSecure: { expected, replacement, guardMutation in
                self.onBoundary("replace-secure")
                try guardMutation()
                if self.changeBeforeSecureWrite { self.secureRoot += " " }
                guard self.secureRoot == expected else { throw FixtureError() }
                self.events.append("secure-write")
                if self.failure == .secureWrite { throw FixtureError() }
                self.secureRoot = replacement
                self.events.append("secure-readback")
                if self.failure == .secureReadback { throw FixtureError() }
            },
            replaceConfiguration: { expected, replacement, guardMutation in
                self.onBoundary("replace-configuration")
                try guardMutation()
                guard self.configurationRoot == expected else { throw FixtureError() }
                self.events.append("configuration-write")
                if self.failure == .configurationWrite { throw FixtureError() }
                self.configurationRoot = replacement
                self.events.append("configuration-readback")
                if self.failure == .configurationReadback { throw FixtureError() }
            }
        )
    }
}

private final class SelectionBoundaryProbe {
    let directory: URL
    let verifiesContention: Bool
    var isCommandRunning = false
    var onCommandEvent: (() -> Void)?
    private(set) var events: [String] = []

    init(directory: URL, verifiesContention: Bool) {
        self.directory = directory
        self.verifiesContention = verifiesContention
    }

    func record(_ event: String) {
        events.append(event)
        guard isCommandRunning else { return }
        onCommandEvent?()
        guard verifiesContention else { return }
        do {
            let unexpected = try ManagerFileLock.acquire(directory: directory.path)
            unexpected.release()
            Issue.record("Selection callback acquired a competing manager lock during command execution")
        } catch ManagerFileLockError.contended {
        } catch {
            Issue.record("Selection callback observed an unexpected lock error: \(error)")
        }
    }
}

private final class SelectionFixture {
    let alpha2Secure = #"{"claudeAiOauth":{"accessToken":"A2","refreshToken":"RA2"},"organizationUuid":null,"sentinel":"secure","huge":900719925474099312345}"#
    let alpha2Configuration = #"{"oauthAccount":{"accountUuid":"account-a","future":900719925474099312345},"sentinel":"keep","huge":900719925474099312345,"additionalModelOptionsCache":null,"additionalModelCostsCache":1,"modelAccessCache":2,"orgModelDefaultCache":3,"lastSeenOrgDefaultUpdatedAt":4,"clientDataCache":5,"clientDataCacheSlots":6,"autoCompactWindowsCache":7,"cachedUsageUtilization":8}"#
    let alpha2ConfigurationWithoutCaches = #"{"oauthAccount":{"accountUuid":"account-a","future":900719925474099312345},"sentinel":"keep","huge":900719925474099312345}"#
    let betaSecure = #"{"claudeAiOauth":{"accessToken":"B","refreshToken":"RB"},"organizationUuid":"org-b","sentinel":"secure","huge":900719925474099312345,"trustedDeviceToken":null}"#
    let betaConfiguration = #"{"oauthAccount":{"accountUuid":"account-b","organizationUuid":"org-b"},"sentinel":"keep","huge":900719925474099312345}"#
    let alpha2: ClaudeLoginSnapshot
    let initialState: ClaudeLoginState
    let resources: MemorySelectionResources
    let custody: ClaudeLoginCustody
    let store: SelectionDataStore
    let directory: URL
    private let boundaryProbe: SelectionBoundaryProbe
    var boundaryEvents: [String] { boundaryProbe.events }
    var onCommandEvent: (() -> Void)? {
        get { boundaryProbe.onCommandEvent }
        set { boundaryProbe.onCommandEvent = newValue }
    }
    var messages: [String] = []
    private let scopedBackend: CommandScopedClaudeLoginBackend
    private let directBackend: any ClaudeLoginBackend
    var backend: any ClaudeLoginBackend { scopedBackend }

    init(
        failure: SelectionFailure? = nil, deadTarget: Bool = false, deadOutgoing: DeadOutgoingCredentials? = nil,
        unsupportedRoot: UnsupportedSelectionRoot? = nil, failInitialization: Bool = false,
        onDirectoryOwned: ((URL) -> Void)? = nil, guardFailure: SelectionGuardFailure? = nil,
        verifyLockContention: Bool = false, failedProcessCheck: Int? = nil
    ) throws {
        directory = try disposableDirectory("selection")
        onDirectoryOwned?(directory)
        if failInitialization { throw FixtureError() }
        let probe = SelectionBoundaryProbe(directory: directory, verifiesContention: verifyLockContention)
        boundaryProbe = probe
        var outgoingSecure = alpha2Secure
        var outgoingConfiguration = alpha2Configuration
        if let deadOutgoing { outgoingSecure = deadOutgoing.secureRoot }
        if unsupportedRoot == .enterpriseGateway { outgoingSecure = try ScopedJSON(outgoingSecure).replacing(["enterpriseGateway": .value("true")]) }
        if unsupportedRoot == .designOauth { outgoingConfiguration = try ScopedJSON(outgoingConfiguration).replacing(["designOauth": .value("true")]) }
        alpha2 = try ClaudeLoginSnapshot.capture(
            secureRoot: outgoingSecure, configurationRoot: outgoingConfiguration
        )
        let alpha1 = try ClaudeLoginSnapshot.capture(
            secureRoot: #"{"claudeAiOauth":{"accessToken":"A1","refreshToken":"RA1"}}"#,
            configurationRoot: #"{"oauthAccount":{"accountUuid":"account-a"}}"#
        )
        let targetSecure = deadTarget
            ? #"{"claudeAiOauth":{"accessToken":"","refreshToken":"","expiresAt":0},"organizationUuid":"org-b","trustedDeviceToken":null}"#
            : #"{"claudeAiOauth":{"accessToken":"B","refreshToken":"RB"},"organizationUuid":"org-b","trustedDeviceToken":null}"#
        let target = try ClaudeLoginSnapshot.capture(
            secureRoot: targetSecure,
            configurationRoot: #"{"oauthAccount":{"accountUuid":"account-b","organizationUuid":"org-b"}}"#
        )
        initialState = .init(snapshots: ["alpha": alpha1, "beta": target], activeAlias: "alpha")
        store = SelectionDataStore(
            data: try ClaudeLoginEnvelopeCodec().encode(initialState), failure: failure,
            onBoundary: probe.record
        )
        custody = ClaudeLoginCustody(store: store)
        let resourceStore = MemorySelectionResources(
            secureRoot: outgoingSecure, configurationRoot: outgoingConfiguration, failure: failure,
            onBoundary: probe.record
        )
        resources = resourceStore
        var checks = 0
        let process = ClaudeProcessPreflight(
            expectedUID: 501, trustedExecutablePath: "/synthetic/claude",
            probe: .init(snapshot: {
                checks += 1
                probe.record("process-\(checks)")
                if (failure == .finalProcess && checks == 12)
                    || guardFailure?.failedCheck == checks || failedProcessCheck == checks {
                    return [.init(pid: 40, parentPID: 1, uid: 501, executablePath: "/synthetic/terminal", role: .terminal)]
                }
                return []
            })
        )
        let lockDirectory = directory
        let selectionStore = store
        let selectionCustody = custody
        directBackend = GuardedClaudeLoginBackend(
            custody: selectionCustody, processPreflight: process,
            currentSnapshot: {
                probe.record("capture")
                return try ClaudeLoginSnapshot.capture(secureRoot: resourceStore.secureRoot, configurationRoot: resourceStore.configurationRoot)
            }, selectionResources: resourceStore.io
        )
        scopedBackend = CommandScopedClaudeLoginBackend(
            acquireLock: { try ManagerFileLock.acquire(directory: lockDirectory.path) },
            routingEvidence: { .testing() }, readCustody: { selectionCustody },
            writeCustody: { _, guardMutation in ClaudeLoginCustody(store: GuardedSelectionDataStore(store: selectionStore, guardMutation: guardMutation)) },
            processPreflight: process,
            currentSnapshot: { _ in
                probe.record("capture")
                return try ClaudeLoginSnapshot.capture(secureRoot: resourceStore.secureRoot, configurationRoot: resourceStore.configurationRoot)
            },
            selectionResources: { _ in resourceStore.io }
        )
    }

    var expectedBoundaryEvents: [String] {
        [
            "manager-read", "process-1", "capture-roots", "manager-read", "process-2",
            "manager-update", "manager-read", "manager-read", "process-3", "manager-read",
            "process-4", "manager-update", "manager-read", "manager-read", "process-5",
            "read-roots", "replace-secure", "process-6", "read-roots", "replace-configuration",
            "process-7", "read-roots", "process-8", "manager-read", "process-9",
            "manager-update", "manager-read", "manager-read", "process-10", "manager-read",
            "process-11", "manager-update", "manager-read", "manager-read", "process-12"
        ]
    }

    func expectedManagerStates(operationID: String?) throws -> [ClaudeLoginState] {
        var checkpoint = initialState
        checkpoint.snapshots["alpha"] = alpha2
        guard let operationID else { return [initialState, checkpoint] }
        let before = ClaudeLoginOwnedFields(
            secure: [
                "claudeAiOauth": .value(#"{"accessToken":"A2","refreshToken":"RA2"}"#),
                "organizationUuid": .null, "trustedDeviceToken": .missing
            ],
            configuration: [
                "oauthAccount": .value(#"{"accountUuid":"account-a","future":900719925474099312345}"#),
                "additionalModelOptionsCache": .null, "additionalModelCostsCache": .value("1"),
                "modelAccessCache": .value("2"), "orgModelDefaultCache": .value("3"),
                "lastSeenOrgDefaultUpdatedAt": .value("4"), "clientDataCache": .value("5"),
                "clientDataCacheSlots": .value("6"), "autoCompactWindowsCache": .value("7"),
                "cachedUsageUtilization": .value("8")
            ]
        )
        let after = ClaudeLoginOwnedFields(
            secure: [
                "claudeAiOauth": .value(#"{"accessToken":"B","refreshToken":"RB"}"#),
                "organizationUuid": .value(#""org-b""#), "trustedDeviceToken": .null
            ],
            configuration: [
                "oauthAccount": .value(#"{"accountUuid":"account-b","organizationUuid":"org-b"}"#),
                "additionalModelOptionsCache": .missing, "additionalModelCostsCache": .missing,
                "modelAccessCache": .missing, "orgModelDefaultCache": .missing,
                "lastSeenOrgDefaultUpdatedAt": .missing, "clientDataCache": .missing,
                "clientDataCacheSlots": .missing, "autoCompactWindowsCache": .missing,
                "cachedUsageUtilization": .missing
            ]
        )
        var pending = checkpoint
        pending.journal = .init(
            operationID: operationID, source: "alpha", target: "beta",
            before: before, after: after, phase: .pending
        )
        var committed = pending
        committed.activeAlias = "beta"
        committed.journal?.phase = .committed
        var cleared = committed
        cleared.journal = nil
        return [initialState, checkpoint, pending, committed, cleared]
    }

    func expectedResourceRoots(after failure: SelectionFailure) -> ClaudeLoginRoots {
        let mismatchedSecure = #"{"claudeAiOauth":{"accessToken":"X","refreshToken":"RB"},"organizationUuid":"org-b","sentinel":"secure","huge":900719925474099312345,"trustedDeviceToken":null}"#
        let secure: String
        switch failure {
        case .checkpointWrite, .checkpointReadback, .prepareWrite, .prepareReadback,
             .preparePostVerificationRead, .secureWrite:
             secure = alpha2Secure
        case .rootsChanged: secure = alpha2Secure + " "
        case .secureVerificationMismatch, .combinedVerification:
            secure = mismatchedSecure
        default:
            secure = betaSecure
        }
        let configuration: String
        switch failure {
        case .configurationReadback, .combinedVerification, .commitWrite, .commitReadback,
             .commitPostVerificationRead, .clearWrite, .clearReadback, .finalProcess:
            configuration = betaConfiguration
        default:
            configuration = alpha2Configuration
        }
        return .init(secure: secure, configuration: configuration)
    }

    func run(alias: String) -> Int32 {
        boundaryProbe.isCommandRunning = true
        defer { boundaryProbe.isCommandRunning = false }
        return runClaudeLogins(arguments: ["claude-login", "use", alias], makeBackend: { scopedBackend }, output: { messages.append($0) }, runGUI: {})
    }

    func runApp(_ command: (ClaudeLoginAppAdapter) async -> ClaudeLoginAppResult) async -> ClaudeLoginAppResult {
        boundaryProbe.isCommandRunning = true
        defer { boundaryProbe.isCommandRunning = false }
        let backend = scopedBackend
        return await command(ClaudeLoginAppAdapter(makeBackend: { backend }))
    }

    func runDirect(alias: String) -> Int32 {
        runClaudeLogins(
            arguments: ["claude-login", "use", alias], makeBackend: { directBackend },
            output: { messages.append($0) }, runGUI: {}
        )
    }

    func preparePendingRecovery() throws -> ClaudeLoginState {
        var state = try custody.load()
        guard let target = state.snapshots["beta"] else { throw FixtureError() }
        let before = try ClaudeLoginOwnedFields.capture(.init(
            secure: resources.secureRoot, configuration: resources.configurationRoot
        ))
        state.snapshots["alpha"] = try ClaudeLoginSnapshot.capture(
            secureRoot: resources.secureRoot, configurationRoot: resources.configurationRoot
        )
        state.journal = .init(
            operationID: UUID().uuidString, source: "alpha", target: "beta", before: before,
            after: .target(target), phase: .pending
        )
        try custody.save(state, permitsJournal: true)
        resources.secureRoot = try ScopedJSON(resources.secureRoot).replacing(state.journal!.after.secure)
        resources.configurationRoot = try ScopedJSON(resources.configurationRoot).replacing(state.journal!.after.configuration)
        return state
    }

    func runRecovery() -> Int32 {
        boundaryProbe.isCommandRunning = true
        defer { boundaryProbe.isCommandRunning = false }
        return runClaudeLogins(
            arguments: ["claude-login", "recover"], makeBackend: { scopedBackend },
            output: { messages.append($0) }, runGUI: {}
        )
    }

    func cleanup() {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        do {
            let reacquired = try ManagerFileLock.acquire(directory: directory.path)
            reacquired.release()
            try FileManager.default.removeItem(at: directory)
        } catch {
            Issue.record("Selection fixture cleanup failed for its owned directory: \(error)")
        }
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
}

enum JournalSerializedAttack: CaseIterable {
    case invalidPhase, invalidOperationID, unknownSource, invalidSource, unknownTarget, invalidTarget
    case missingOwnedKey, extraOwnedKey, invalidPresence, malformedRaw, valueNull, overDepthRaw
    case inconsistentBefore, inconsistentAfter, inconsistentCommittedMarker

    func mutating(_ control: Data) throws -> Data {
        guard let root = try JSONSerialization.jsonObject(
            with: control, options: .mutableContainers
        ) as? NSMutableDictionary,
        let journal = root["journal"] as? NSMutableDictionary,
        let before = journal["before"] as? NSMutableDictionary,
        let after = journal["after"] as? NSMutableDictionary,
        let beforeSecure = before["secure"] as? NSMutableDictionary,
        let beforeConfiguration = before["configuration"] as? NSMutableDictionary,
        let afterSecure = after["secure"] as? NSMutableDictionary,
        let afterConfiguration = after["configuration"] as? NSMutableDictionary else {
            throw ClaudeLoginEnvelopeError.invalid
        }
        switch self {
        case .invalidPhase: journal["phase"] = "prepared"
        case .invalidOperationID: journal["operationID"] = "not-a-uuid"
        case .unknownSource: journal["source"] = "gamma"
        case .invalidSource: journal["source"] = "Alpha"
        case .unknownTarget: journal["target"] = "gamma"
        case .invalidTarget: journal["target"] = "Beta"
        case .missingOwnedKey: beforeSecure.removeObject(forKey: "trustedDeviceToken")
        case .extraOwnedKey:
            afterConfiguration["futureCache"] = ["kind": "missing", "value": NSNull()]
        case .invalidPresence:
            beforeConfiguration["modelAccessCache"] = ["kind": "missing", "value": "unexpected"]
        case .malformedRaw:
            beforeConfiguration["modelAccessCache"] = ["kind": "value", "value": "{"]
        case .valueNull:
            beforeConfiguration["modelAccessCache"] = ["kind": "value", "value": "null"]
        case .overDepthRaw:
            beforeConfiguration["modelAccessCache"] = ["kind": "value", "value": String(repeating: "[", count: 65) + "0" + String(repeating: "]", count: 65)]
        case .inconsistentBefore:
            beforeSecure["claudeAiOauth"] = [
                "kind": "value", "value": #"{"accessToken":"X","refreshToken":"RX"}"#
            ]
        case .inconsistentAfter:
            afterSecure["claudeAiOauth"] = [
                "kind": "value", "value": #"{"accessToken":"A","refreshToken":"R"}"#
            ]
        case .inconsistentCommittedMarker:
            journal["phase"] = "committed"
        }
        return try JSONSerialization.data(withJSONObject: root, options: .sortedKeys)
    }
}

enum UnsafeEnvelopeCase: CaseIterable {
    case invalidUTF8, malformedJSON, nestedOuterDuplicate, malformedPresence, invalidAlias
    case tooManySnapshots, duplicateIdentity, identityMismatch, usabilityMismatch, invalidMarker
    case malformedEmbeddedJSON, nestedEmbeddedDuplicate, pendingScalarJournal

    var expectedError: ClaudeLoginEnvelopeError {
        switch self {
        case .pendingScalarJournal: .recoveryRequired
        default: .invalid
        }
    }

    func data() throws -> Data {
        switch self {
        case .invalidUTF8: return Data([0xFF])
        case .malformedJSON: return Data(#"{"version":1"#.utf8)
        case .nestedOuterDuplicate:
            return try serializedEnvelope(extraMember: #""future":{"key":1,"key":2}"#)
        case .malformedPresence:
            return try serializedEnvelope(credentialPresence: #"{"kind":"missing","value":"unexpected"}"#)
        case .invalidAlias:
            return try serializedEnvelope(entries: [("INVALID", try serializedSnapshot())], activeAlias: "INVALID")
        case .tooManySnapshots:
            return try serializedEnvelope(entries: [
                ("alpha", try serializedSnapshot()),
                ("beta", try serializedSnapshot(account: "account-b")),
            ] + (3...11).map { ("alias\($0)", try serializedSnapshot(account: "account-\($0)")) })
        case .duplicateIdentity:
            return try serializedEnvelope(entries: [
                ("alpha", try serializedSnapshot()), ("beta", try serializedSnapshot())
            ])
        case .identityMismatch:
            return try serializedEnvelope(entries: [("alpha", try serializedSnapshot(declaredAccount: "other-account"))])
        case .usabilityMismatch:
            return try serializedEnvelope(entries: [("alpha", try serializedSnapshot(usability: "reLoginNeeded"))])
        case .invalidMarker:
            return try serializedEnvelope(activeAlias: "beta")
        case .malformedEmbeddedJSON:
            return try serializedEnvelope(credentials: #"{"accessToken":"A""#)
        case .nestedEmbeddedDuplicate:
            return try serializedEnvelope(credentials: #"{"accessToken":"A","refreshToken":"R","future":{"key":1,"key":2}}"#)
        case .pendingScalarJournal:
            return try serializedEnvelope(journal: #""pending""#)
        }
    }
}

private func serializedEnvelope(
    entries: [(String, String)]? = nil,
    activeAlias: String? = "alpha",
    journal: String? = nil,
    credentials: String = #"{"accessToken":"A","refreshToken":"R"}"#,
    credentialPresence: String? = nil,
    extraMember: String? = nil
) throws -> Data {
    let snapshots = try entries ?? [("alpha", serializedSnapshot(
        credentials: credentials, credentialPresence: credentialPresence
    ))]
    let encodedEntries = try snapshots.map { try "\(encodedJSONString($0.0)):\($0.1)" }.joined(separator: ",")
    let marker = try activeAlias.map(encodedJSONString) ?? "null"
    let journalMember = journal.map { #","journal":\#($0)"# } ?? ""
    let extra = extraMember.map { ",\($0)" } ?? ""
    return Data(#"{"version":1,"snapshots":{\#(encodedEntries)},"activeAlias":\#(marker)\#(journalMember)\#(extra)}"#.utf8)
}

private func serializedSnapshot(
    account: String = "account-a",
    declaredAccount: String? = nil,
    usability: String = "usable",
    credentials: String = #"{"accessToken":"A","refreshToken":"R"}"#,
    credentialPresence: String? = nil
) throws -> String {
    let credential: String
    if let credentialPresence {
        credential = credentialPresence
    } else {
        credential = #"{"kind":"value","value":\#(try encodedJSONString(credentials))}"#
    }
    let oauth = #"{"kind":"value","value":\#(try encodedJSONString(#"{"accountUuid":"\#(account)"}"#))}"#
    return #"{"claudeAiOauth":\#(credential),"oauthAccount":\#(oauth),"organizationUUID":{"kind":"missing","value":null},"trustedDeviceToken":{"kind":"missing","value":null},"accountUUID":\#(try encodedJSONString(declaredAccount ?? account)),"identityOrganizationUUID":null,"usability":\#(try encodedJSONString(usability))}"#
}

private func encodedJSONString(_ value: String) throws -> String {
    String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
}

private final class MemoryClaudeLoginDataStore: ClaudeLoginDataStore {
    var data: Data?
    var readError: Error?
    var createError: Error?
    var updateError: Error?
    var readbackError: Error?
    var postMutationReadError: Error?
    var corruptAfterWrite: Bool
    var mutateBeforeUpdateError: Bool
    var event: (String) -> Void
    private(set) var readCount = 0
    private(set) var createCount = 0
    private(set) var updateCount = 0

    init(
        data: Data? = nil, readError: Error? = nil, createError: Error? = nil, updateError: Error? = nil,
        readbackError: Error? = nil, postMutationReadError: Error? = nil,
        corruptAfterWrite: Bool = false, mutateBeforeUpdateError: Bool = false,
        event: @escaping (String) -> Void = { _ in }
    ) {
        self.data = data
        self.readError = readError
        self.createError = createError
        self.updateError = updateError
        self.readbackError = readbackError
        self.postMutationReadError = postMutationReadError
        self.corruptAfterWrite = corruptAfterWrite
        self.mutateBeforeUpdateError = mutateBeforeUpdateError
        self.event = event
    }

    func read() throws -> Data {
        event("manager-read")
        readCount += 1
        if readCount > 1, let readbackError { throw readbackError }
        if createCount + updateCount > 0, let postMutationReadError { throw postMutationReadError }
        if let readError { throw readError }
        guard let data else { throw IsolatedKeychainError.missing }
        return data
    }

    func create(data: Data) throws {
        event("manager-create")
        createCount += 1
        if let createError { throw createError }
        self.data = corruptAfterWrite ? Data(#"{"version":1}"#.utf8) : data
    }

    func update(data: Data) throws {
        event("manager-update")
        updateCount += 1
        if mutateBeforeUpdateError { self.data = data }
        if let updateError { throw updateError }
        self.data = corruptAfterWrite ? Data(#"{"version":1}"#.utf8) : data
    }
}

private struct MutationGuardedDataStore: ClaudeLoginDataStore {
    let store: MemoryClaudeLoginDataStore
    let guardMutation: () throws -> Void

    init(_ store: MemoryClaudeLoginDataStore, _ guardMutation: @escaping () throws -> Void) {
        self.store = store
        self.guardMutation = guardMutation
    }

    func read() throws -> Data { try store.read() }
    func create(data: Data) throws { try guardMutation(); try store.create(data: data) }
    func update(data: Data) throws { try guardMutation(); try store.update(data: data) }
}

private func commandBackend(
    directory: URL,
    store: MemoryClaudeLoginDataStore,
    event: @escaping (String) -> Void = { _ in },
    currentSnapshot: (() throws -> ClaudeLoginSnapshot)? = nil
) -> CommandScopedClaudeLoginBackend {
    CommandScopedClaudeLoginBackend(
        acquireLock: { event("lock"); return try ManagerFileLock.acquire(directory: directory.path) },
        routingEvidence: { event("route"); return .testing() },
        readCustody: { event("read-factory"); return ClaudeLoginCustody(store: store) },
        writeCustody: { _, guardMutation in
            event("write-factory")
            return ClaudeLoginCustody(store: MutationGuardedDataStore(store, guardMutation))
        },
        processPreflight: .init(
            expectedUID: 501, trustedExecutablePath: "/synthetic/claude",
            probe: .init(snapshot: { event("process"); return [] })
        ),
        currentSnapshot: { _ in event("capture"); return try currentSnapshot?() ?? ClaudeLoginSnapshot.capture(
            secureRoot: #"{"claudeAiOauth":{"accessToken":"A","refreshToken":"R"}}"#,
            configurationRoot: #"{"oauthAccount":{"accountUuid":"account-a"}}"#
        ) }
    )
}

enum CommandFailureCase: CaseIterable {
    case factory, capture, create, update, readback

    var existing: Bool { self == .update || self == .readback }
    var attemptedWrites: Int { self == .create || self == .update || self == .readback ? 1 : 0 }
}

private func plainCommandBackend(
    directory: URL,
    store: MemoryClaudeLoginDataStore,
    processCheck: @escaping () -> Bool
) -> CommandScopedClaudeLoginBackend {
    CommandScopedClaudeLoginBackend(
        acquireLock: { try ManagerFileLock.acquire(directory: directory.path) },
        routingEvidence: { .testing() },
        readCustody: { ClaudeLoginCustody(store: store) },
        writeCustody: { _, _ in ClaudeLoginCustody(store: store) },
        processPreflight: .init(
            expectedUID: 501, trustedExecutablePath: "/synthetic/claude",
            probe: .init(snapshot: {
                processCheck()
                    ? [.init(pid: 40, parentPID: 1, uid: 501, executablePath: "/synthetic/terminal", role: .terminal)]
                    : []
            })
        ),
        currentSnapshot: { _ in try ClaudeLoginSnapshot.capture(
            secureRoot: #"{"claudeAiOauth":{"accessToken":"A","refreshToken":"R"}}"#,
            configurationRoot: #"{"oauthAccount":{"accountUuid":"account-a"}}"#
        ) }
    )
}

private func safeProcessPreflight() -> ClaudeProcessPreflight {
    .init(
        expectedUID: 501,
        trustedExecutablePath: "/synthetic/claude",
        probe: .init(snapshot: {
            [.init(pid: 40, parentPID: 1, uid: 502, executablePath: "/synthetic/other", role: nil)]
        })
    )
}

enum ConfigurationRace: CaseIterable {
    case content, identity, protection

    func expectedDocument(_ original: String) -> String {
        switch self {
        case .content: "{}"
        case .identity, .protection: original
        }
    }

    func matchesInode(original: ino_t, current: ino_t) -> Bool {
        switch self {
        case .content, .protection: current == original
        case .identity: current != original
        }
    }

    var expectedMode: mode_t {
        switch self {
        case .content, .identity: 0o600
        case .protection: 0o400
        }
    }

    func apply(to file: URL) throws {
        switch self {
        case .content:
            let descriptor = open(file.path, O_WRONLY | O_TRUNC)
            defer { close(descriptor) }
            _ = write(descriptor, "{}", 2)
        case .identity:
            let contents = try Data(contentsOf: file)
            try FileManager.default.removeItem(at: file)
            try contents.write(to: file)
            chmod(file.path, 0o600)
        case .protection:
            chmod(file.path, 0o400)
        }
    }
}

enum ConfigurationPresence: CaseIterable {
    case missing, null, value

    var value: JSONPresence {
        switch self {
        case .missing: .missing
        case .null: .null
        case .value: .value(#"{"accountUuid":"account-b","nested":{"opaque":true}}"#)
        }
    }

    var expectedDocument: String {
        switch self {
        case .missing:
            #"{"sentinel":900719925474099312345,"unknown":{"keep":true}}"#
        case .null:
            #"{"sentinel":900719925474099312345,"oauthAccount":null,"unknown":{"keep":true}}"#
        case .value:
            #"{"sentinel":900719925474099312345,"oauthAccount":{"accountUuid":"account-b","nested":{"opaque":true}},"unknown":{"keep":true}}"#
        }
    }
}

private final class FakeSecurityTool {
    struct Call { let arguments: [String]; let input: Data? }
    private var responses: [(Int32, Data)]
    private(set) var calls: [Call] = []
    var onCall: ((Call) -> Void)?

    init(responses: [(Int32, Data)]) { self.responses = responses }

    func run(_ arguments: [String], _ input: Data?) throws -> (status: Int32, output: Data) {
        let call = Call(arguments: arguments, input: input)
        calls.append(call)
        onCall?(call)
        guard !responses.isEmpty else { throw FixtureError() }
        let (status, output) = responses.removeFirst()
        return (status, output)
    }
}

private final class LiveSystemFixture {
    private(set) var checkedExecutables: [String] = []
    private let environment: [String: String]
    private let files: Set<String>
    private let executable: String?
    private let contractMatches: Bool

    init(
        environment: [String: String] = [:], files: Set<String> = [],
        executable: String? = "/home/me/.local/share/claude/versions/2.1.282", contractMatches: Bool = true
    ) {
        self.environment = environment.merging(["USER": "me"]) { current, _ in current }
        self.files = files
        self.executable = executable
        self.contractMatches = contractMatches
        _ = system.routingEvidence()
    }

    var system: ClaudeLiveSystem {
        .init(
            home: "/home/me", environment: environment, operatingSystemUser: "me",
            fileExists: { [files] in files.contains($0) },
            resolveExecutable: { [executable] in $0 == "/home/me/.local/bin/claude" ? executable : nil },
            storageContractMatches: { self.checkedExecutables.append($0); return self.contractMatches }
        )
    }
}

enum StorageDerivation {}

private final class ConfigurationFixture {
    let directory: URL
    let file: URL

    init(_ contents: String) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("opencode/config-\(UUID().uuidString)", isDirectory: true)
        file = directory.appendingPathComponent(".claude.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        try Data(contents.utf8).write(to: file)
        chmod(file.path, 0o600)
    }

    func cleanup() { try? FileManager.default.removeItem(at: directory) }

    func metadata() throws -> (owner: uid_t, mode: mode_t) {
        var value = stat()
        guard lstat(file.path, &value) == 0 else { throw FixtureError() }
        return (value.st_uid, value.st_mode & 0o777)
    }

    func temporaryFiles() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(".aicontrol-") }
    }
}

private func disposableDirectory(_ prefix: String) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("opencode", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root.appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
}

private func fileInode(_ file: URL) throws -> ino_t {
    var value = stat()
    guard lstat(file.path, &value) == 0 else { throw FixtureError() }
    return value.st_ino
}

private extension ClaudeRoutingEvidence {
    static func testing(
        storageContractVerified: Bool = true,
        path: String = "/synthetic/home/.claude.json",
        environmentUser: String? = "fixture-user",
        conflicts: Set<ClaudeRoutingConflict> = []
    ) -> Self {
        .init(
            storageContractVerified: storageContractVerified, resolvedConfigurationPath: path,
            defaultConfigurationPath: "/synthetic/home/.claude.json", environmentUser: environmentUser,
            operatingSystemUser: "os-fixture", conflicts: conflicts
        )
    }
}

struct RoutingRejection: Sendable {
    let evidence: ClaudeRoutingEvidence
    let error: ClaudeRoutingError
    static let cases: [Self] = [
        .init(evidence: .testing(storageContractVerified: false), error: .unsupportedBuild),
        .init(evidence: .testing(path: "/synthetic/alternate/.claude.json"), error: .nonDefaultResolver),
        .init(evidence: .testing(conflicts: [.configurationOverride]), error: .conflictingSource),
        .init(evidence: .testing(conflicts: [.secureStorageOverride]), error: .conflictingSource),
        .init(evidence: .testing(conflicts: [.customOAuth]), error: .conflictingSource),
        .init(evidence: .testing(conflicts: [.plaintextFallback]), error: .conflictingSource),
        .init(evidence: .testing(conflicts: [.legacyStorage]), error: .conflictingSource),
        .init(evidence: .testing(conflicts: [.alternateAuthentication]), error: .conflictingSource),
        .init(evidence: .testing(conflicts: [.unsupportedProviderState]), error: .conflictingSource)
    ]
}

struct MutationGuardCase: Sendable {
    let checkToFail: Int
    let existing: Bool
    static let cases = [
        Self(checkToFail: 1, existing: false), Self(checkToFail: 2, existing: false), Self(checkToFail: 3, existing: false),
        Self(checkToFail: 2, existing: true), Self(checkToFail: 3, existing: true)
    ]
}

let processUncertaintyCases: [[ClaudeProcessRecord]] = [
    [.init(pid: 40, parentPID: 1, uid: nil, executablePath: nil, role: nil)],
    [.init(pid: 40, parentPID: 1, uid: 501, executablePath: "/synthetic/a", role: nil),
     .init(pid: 40, parentPID: 1, uid: 501, executablePath: "/synthetic/b", role: nil)],
    [.init(pid: 40, parentPID: 41, uid: 501, executablePath: "/synthetic/a", role: nil),
     .init(pid: 41, parentPID: 40, uid: 501, executablePath: "/synthetic/b", role: nil)]
]

enum InventoryFailure: CaseIterable, Sendable {
    case sizingZero, sizingNegative, sizingMisaligned, sizingOverCap
    case copiedZero, copiedNegative, copiedMisaligned, copiedOverCapacity, copiedAtCapacity
    case negativePID, duplicatePID
}

enum MetadataFailure: CaseIterable, Sendable {
    case zero, short, oversized, wrongPID, permissionDenied, missingProcess
}

enum PathFailure: CaseIterable, Sendable {
    case zero, empty, missingTerminator, oversized, invalidUTF8
}

struct LiveMetadataCase: Sendable {
    let status: UInt32
    let flags: UInt32
    let uid: uid_t
}

let liveMetadataCases = [
    LiveMetadataCase(status: UInt32(SSTOP), flags: 0, uid: 501),
    LiveMetadataCase(status: UInt32(SRUN), flags: UInt32(PROC_FLAG_INEXIT), uid: 501),
    LiveMetadataCase(status: UInt32(SRUN), flags: 0, uid: 0),
    LiveMetadataCase(status: UInt32(SRUN), flags: 0, uid: 502)
]

private final class ProcessNativeFixture: @unchecked Sendable {
    var infoRequests: [(Int32, UInt64)] = []
    var pathCalls = 0
    private let inventoryFailure: InventoryFailure?
    private let metadataFailure: MetadataFailure?
    private let pathFailure: PathFailure?
    private let status: UInt32
    private let flags: UInt32
    private let uid: uid_t
    private let deletedExecutableName: String?

    init(
        inventoryFailure: InventoryFailure? = nil,
        metadataFailure: MetadataFailure? = nil,
        pathFailure: PathFailure? = nil,
        status: UInt32 = UInt32(SRUN),
        flags: UInt32 = 0,
        uid: uid_t = 501,
        deletedExecutableName: String? = nil
    ) {
        self.deletedExecutableName = deletedExecutableName
        self.inventoryFailure = inventoryFailure
        self.metadataFailure = metadataFailure
        self.pathFailure = pathFailure
        self.status = status
        self.flags = flags
        self.uid = uid
    }

    var calls: ProcessNativeCalls {
        .init(
            listPIDs: { [self] buffer, capacity in
                let stride = Int32(MemoryLayout<pid_t>.stride)
                if buffer == nil {
                    switch inventoryFailure {
                    case .sizingZero: return 0
                    case .sizingNegative: return -1
                    case .sizingMisaligned: return stride + 1
                    case .sizingOverCap: return (1 << 20) + stride
                    default: return 3 * stride
                    }
                }
                let values: [pid_t]
                switch inventoryFailure {
                case .negativePID: values = [-1, 42]
                case .duplicatePID: values = [42, 42]
                default: values = [0, 42]
                }
                buffer?.assumingMemoryBound(to: pid_t.self).update(from: values, count: values.count)
                switch inventoryFailure {
                case .copiedZero: return 0
                case .copiedNegative: return -1
                case .copiedMisaligned: return stride + 1
                case .copiedOverCapacity: return capacity + stride
                case .copiedAtCapacity: return capacity
                default: return Int32(values.count) * stride
                }
            },
            processInfo: { [self] pid, flavor, argument, buffer, size in
                infoRequests.append((flavor, argument))
                if metadataFailure == .zero { return 0 }
                if metadataFailure == .permissionDenied { return EPERM }
                if metadataFailure == .missingProcess { return ESRCH }
                if flavor == PROC_PIDT_SHORTBSDINFO {
                    var info = proc_bsdshortinfo()
                    info.pbsi_pid = metadataFailure == .wrongPID ? 43 : UInt32(pid)
                    info.pbsi_ppid = 1
                    info.pbsi_uid = uid
                    info.pbsi_status = status
                    info.pbsi_flags = flags
                    if let deletedExecutableName {
                        withUnsafeMutableBytes(of: &info.pbsi_comm) { $0.copyBytes(from: Array(deletedExecutableName.utf8)) }
                    }
                    buffer?.copyMemory(from: &info, byteCount: min(Int(size), MemoryLayout.size(ofValue: info)))
                } else {
                    var info = proc_bsdinfo()
                    info.pbi_pid = metadataFailure == .wrongPID ? 43 : UInt32(pid)
                    info.pbi_ppid = 1
                    info.pbi_uid = uid
                    info.pbi_status = status
                    buffer?.copyMemory(from: &info, byteCount: min(Int(size), MemoryLayout.size(ofValue: info)))
                }
                let exact = Int32(MemoryLayout<proc_bsdshortinfo>.size)
                if metadataFailure == .short { return exact - 1 }
                if metadataFailure == .oversized { return exact + 1 }
                return size
            },
            processPath: { [self] _, buffer, capacity in
                pathCalls += 1
                if deletedExecutableName != nil { errno = ENOENT; return 0 }
                if pathFailure == .zero { errno = EPERM; return 0 }
                let bytes: [UInt8]
                switch pathFailure {
                case .empty: bytes = [0]
                case .missingTerminator: bytes = [47, 120]
                case .invalidUTF8: bytes = [0xff, 0]
                default: bytes = Array("/synthetic/live\0".utf8)
                }
                for (index, byte) in bytes.enumerated() {
                    buffer?.assumingMemoryBound(to: UInt8.self)[index] = byte
                }
                return pathFailure == .oversized ? Int32(capacity) : Int32(max(bytes.count - 1, 1))
            }
        )
    }
}

private extension ClaudeProcessPreflight {
    static func testing(_ records: [ClaudeProcessRecord]) -> Self {
        .init(
            expectedUID: 501, trustedExecutablePath: "/synthetic/claude",
            probe: .init(snapshot: { records })
        )
    }
}
