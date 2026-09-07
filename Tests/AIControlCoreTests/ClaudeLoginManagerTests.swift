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
