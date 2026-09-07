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
        #expect(messages == ["Usage: AIControl claude-login save <alias> | list | use <alias> | recover"])
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

    @Test("A third alias is refused without persistence")
    func thirdAliasIsRefusedWithoutPersistence() throws {
        let first = try snapshot(account: "account-a")
        let second = try snapshot(account: "account-b")
        let third = try snapshot(account: "account-c")
        let backend = RecordingClaudeLoginBackend(
            state: .init(snapshots: ["alpha": first, "beta": second], activeAlias: "alpha"),
            current: third
        )

        let exit = runClaudeLogins(arguments: ["claude-login", "save", "gamma"], makeBackend: { backend }, output: { _ in }, runGUI: {})

        #expect(exit == 3)
        #expect(backend.savedStates.isEmpty)
        #expect(backend.state.snapshots.count == 2)
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

    @Test("Use and recover remain safely unavailable")
    func laterTransactionCommandsDoNotConstructBackend() {
        var backendCreations = 0
        var messages: [String] = []

        let useExit = runClaudeLogins(arguments: ["claude-login", "use", "alpha"], makeBackend: {
            backendCreations += 1
            fatalError("Backend must not be constructed")
        }, output: { messages.append($0) }, runGUI: {})
        let recoverExit = runClaudeLogins(arguments: ["claude-login", "recover"], makeBackend: {
            backendCreations += 1
            fatalError("Backend must not be constructed")
        }, output: { messages.append($0) }, runGUI: {})

        #expect(useExit == 3)
        #expect(recoverExit == 3)
        #expect(backendCreations == 0)
        #expect(messages == ["Blocked: account selection is not implemented.", "Blocked: recovery is not implemented."])
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
        let fixture = try ConfigurationFixture(#"{"oauthAccount":{"old":true}}"#)
        defer { fixture.cleanup() }
        let writer = ProtectedConfigurationFile(path: fixture.file.path, hooks: .init(beforeCommit: {
            try race.apply(to: fixture.file)
        }))

        #expect(throws: ProtectedConfigurationError.changedBeforeCommit) {
            try writer.update(.init(oauthAccount: .null))
        }
        #expect(try fixture.temporaryFiles().isEmpty)
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

enum ConfigurationRace: CaseIterable {
    case content, identity, protection

    func apply(to file: URL) throws {
        switch self {
        case .content:
            let descriptor = open(file.path, O_WRONLY | O_TRUNC)
            defer { close(descriptor) }
            _ = write(descriptor, "{}", 2)
        case .identity:
            try FileManager.default.removeItem(at: file)
            try Data("{}".utf8).write(to: file)
            chmod(file.path, 0o600)
        case .protection:
            chmod(file.path, 0o400)
        }
    }
}

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
        version: String = "2.1.252",
        hash: String = "b661c6a094fcc32656bf7c0071c5b45bf900b34d4f0a1ab3d78fd59aeba2c2c7",
        path: String = "/synthetic/home/.claude.json",
        environmentUser: String? = "fixture-user",
        conflicts: Set<ClaudeRoutingConflict> = []
    ) -> Self {
        .init(
            version: version, executableSHA256: hash, resolvedConfigurationPath: path,
            defaultConfigurationPath: "/synthetic/home/.claude.json", environmentUser: environmentUser,
            operatingSystemUser: "os-fixture", conflicts: conflicts
        )
    }
}

struct RoutingRejection: Sendable {
    let evidence: ClaudeRoutingEvidence
    let error: ClaudeRoutingError
    static let cases: [Self] = [
        .init(evidence: .testing(version: "2.1.253"), error: .unsupportedBuild),
        .init(evidence: .testing(hash: "synthetic-wrong-hash"), error: .unexpectedHash),
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

let processUncertaintyCases: [[ClaudeProcessRecord]] = [
    [.init(pid: 40, parentPID: 1, uid: nil, executablePath: nil, role: nil)],
    [.init(pid: 40, parentPID: 1, uid: 501, executablePath: "/synthetic/a", role: nil),
     .init(pid: 40, parentPID: 1, uid: 501, executablePath: "/synthetic/b", role: nil)],
    [.init(pid: 40, parentPID: 41, uid: 501, executablePath: "/synthetic/a", role: nil),
     .init(pid: 41, parentPID: 40, uid: 501, executablePath: "/synthetic/b", role: nil)]
]

private extension ClaudeProcessPreflight {
    static func testing(_ records: [ClaudeProcessRecord]) -> Self {
        .init(
            expectedUID: 501, trustedExecutablePath: "/synthetic/claude",
            probe: .init(snapshot: { records })
        )
    }
}
