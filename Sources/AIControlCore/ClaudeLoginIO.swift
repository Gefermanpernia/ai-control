import Foundation
import Security
import Darwin

enum IsolatedKeychainError: Error, Equatable {
    case missing
    case duplicate
    case ambiguous
    case denied
    case cancelled
    case locked
    case corrupt
    case operatingSystem(OSStatus)
}

struct KeychainNativeCalls {
    var copy: (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus
    var add: (CFDictionary) -> OSStatus
    var update: (CFDictionary, CFDictionary) -> OSStatus
    var delete: (CFDictionary) -> OSStatus

    static let live = Self(
        copy: SecItemCopyMatching,
        add: { SecItemAdd($0, nil) },
        update: SecItemUpdate,
        delete: SecItemDelete
    )
}

struct ManagerKeychainNativeCalls {
    var createTrustedApplication: (String) -> (OSStatus, CFTypeRef?)
    var createAccess: (CFString, CFArray) -> (OSStatus, CFTypeRef?)

    static let live = Self(
        createTrustedApplication: { path in
            var application: SecTrustedApplication?
            let status = SecTrustedApplicationCreateFromPath(path, &application)
            return (status, application)
        },
        createAccess: { description, applications in
            var access: SecAccess?
            let status = SecAccessCreate(description, applications, &access)
            return (status, access)
        }
    )
}

protocol ClaudeLoginDataStore {
    func read() throws -> Data
    func create(data: Data) throws
    func update(data: Data) throws
    func create(data: Data, guardedBy guardMutation: () throws -> Void) throws
    func update(data: Data, guardedBy guardMutation: () throws -> Void) throws
}

extension ClaudeLoginDataStore {
    func create(data: Data, guardedBy guardMutation: () throws -> Void) throws {
        try guardMutation()
        try create(data: data)
    }

    func update(data: Data, guardedBy guardMutation: () throws -> Void) throws {
        try guardMutation()
        try update(data: data)
    }
}

enum ClaudeLoginEnvelopeError: Error, Equatable {
    case tooLarge
    case invalid
    case unsupportedVersion
    case recoveryRequired
    case readbackMismatch
}

struct ClaudeLoginEnvelopeCodec {
    private struct Envelope: Codable {
        let version: Int
        let snapshots: [String: Snapshot]
        let activeAlias: String?
        let journal: Journal?
    }

    private struct Snapshot: Codable {
        let claudeAiOauth: Presence
        let oauthAccount: Presence
        let organizationUUID: Presence
        let trustedDeviceToken: Presence
        let accountUUID: String
        let identityOrganizationUUID: String?
        let usability: String
    }

    private struct Presence: Codable {
        let kind: String
        let value: String?

        init(_ source: JSONPresence) {
            switch source {
            case .missing: kind = "missing"; value = nil
            case .null: kind = "null"; value = nil
            case .value(let raw): kind = "value"; value = raw
            }
        }

        func decoded(maxBytes: Int, maxDepth: Int) throws -> JSONPresence {
            switch (kind, value) {
            case ("missing", nil): return .missing
            case ("null", nil): return .null
            case ("value", .some(let raw)):
                try ClaudeLoginEnvelopeCodec.admitRawValue(raw, maxBytes: maxBytes, maxDepth: maxDepth)
                guard raw.trimmingCharacters(in: .whitespacesAndNewlines) != "null" else {
                    throw ClaudeLoginEnvelopeError.invalid
                }
                return .value(raw)
            default: throw ClaudeLoginEnvelopeError.invalid
            }
        }
    }

    private struct OwnedFields: Codable {
        let secure: [String: Presence]
        let configuration: [String: Presence]

        init(_ source: ClaudeLoginOwnedFields) {
            secure = source.secure.mapValues(Presence.init)
            configuration = source.configuration.mapValues(Presence.init)
        }

        func decoded(maxBytes: Int, maxDepth: Int) throws -> ClaudeLoginOwnedFields {
            .init(
                secure: try secure.mapValues { try $0.decoded(maxBytes: maxBytes, maxDepth: maxDepth) },
                configuration: try configuration.mapValues { try $0.decoded(maxBytes: maxBytes, maxDepth: maxDepth) }
            )
        }
    }

    private struct Journal: Codable {
        let operationID: String
        let source: String
        let target: String
        let before: OwnedFields
        let after: OwnedFields
        let phase: String

        init(_ source: ClaudeLoginJournal) {
            operationID = source.operationID; self.source = source.source; target = source.target
            before = .init(source.before); after = .init(source.after); phase = source.phase.rawValue
        }
    }

    let maxBytes: Int
    let maxDepth: Int

    init(maxBytes: Int = 1_048_576, maxDepth: Int = 64) {
        self.maxBytes = maxBytes
        self.maxDepth = maxDepth
    }

    func encode(_ state: ClaudeLoginState) throws -> Data {
        try validate(state)
        let snapshots = Dictionary(uniqueKeysWithValues: state.snapshots.map { alias, snapshot in
            (alias, Snapshot(
                claudeAiOauth: Presence(snapshot.claudeAiOauth), oauthAccount: Presence(snapshot.oauthAccount),
                organizationUUID: Presence(snapshot.organizationUUID),
                trustedDeviceToken: Presence(snapshot.trustedDeviceToken),
                accountUUID: snapshot.identity.accountUUID,
                identityOrganizationUUID: snapshot.identity.organizationUUID,
                usability: snapshot.usability == .usable ? "usable" : "reLoginNeeded"
            ))
        })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(Envelope(
            version: 1, snapshots: snapshots, activeAlias: state.activeAlias,
            journal: state.journal.map(Journal.init)
        )) else {
            throw ClaudeLoginEnvelopeError.invalid
        }
        guard data.count <= maxBytes else { throw ClaudeLoginEnvelopeError.tooLarge }
        guard Self.hasBoundedDepth(data, maxDepth: maxDepth) else { throw ClaudeLoginEnvelopeError.invalid }
        return data
    }

    func decode(_ data: Data) throws -> ClaudeLoginState {
        guard data.count <= maxBytes else { throw ClaudeLoginEnvelopeError.tooLarge }
        guard Self.hasBoundedDepth(data, maxDepth: maxDepth) else { throw ClaudeLoginEnvelopeError.invalid }
        if let source = String(data: data, encoding: .utf8),
           let root = try? ScopedJSON(source), case .value = root.presence(of: "journal") {
            throw ClaudeLoginEnvelopeError.recoveryRequired
        }
        let state = try decodeRecoveryRecord(data)
        guard state.journal == nil else { throw ClaudeLoginEnvelopeError.recoveryRequired }
        return state
    }

    func decodeRecoveryRecord(_ data: Data) throws -> ClaudeLoginState {
        guard data.count <= maxBytes else { throw ClaudeLoginEnvelopeError.tooLarge }
        guard let source = String(data: data, encoding: .utf8), Self.hasBoundedDepth(data, maxDepth: maxDepth) else {
            throw ClaudeLoginEnvelopeError.invalid
        }
        do { _ = try ScopedJSON(source) } catch { throw ClaudeLoginEnvelopeError.invalid }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            throw ClaudeLoginEnvelopeError.invalid
        }
        guard envelope.version == 1 else { throw ClaudeLoginEnvelopeError.unsupportedVersion }
        var snapshots: [String: ClaudeLoginSnapshot] = [:]
        for (alias, stored) in envelope.snapshots {
            let snapshot = try reconstructedSnapshot(
                claudeAiOauth: stored.claudeAiOauth,
                oauthAccount: stored.oauthAccount,
                organizationUUID: stored.organizationUUID,
                trustedDeviceToken: stored.trustedDeviceToken
            )
            guard snapshot.identity == .init(
                accountUUID: stored.accountUUID,
                organizationUUID: stored.identityOrganizationUUID
            ), stored.usability == (snapshot.usability == .usable ? "usable" : "reLoginNeeded") else {
                throw ClaudeLoginEnvelopeError.invalid
            }
            snapshots[alias] = snapshot
        }
        let journal: ClaudeLoginJournal?
        if let stored = envelope.journal {
            guard !stored.operationID.isEmpty,
                  let phase = ClaudeLoginJournalPhase(rawValue: stored.phase) else {
                throw ClaudeLoginEnvelopeError.invalid
            }
            journal = try .init(
                operationID: stored.operationID, source: stored.source, target: stored.target,
                before: stored.before.decoded(maxBytes: maxBytes, maxDepth: maxDepth),
                after: stored.after.decoded(maxBytes: maxBytes, maxDepth: maxDepth), phase: phase
            )
        } else { journal = nil }
        let state = ClaudeLoginState(
            snapshots: snapshots, activeAlias: envelope.activeAlias, journal: journal
        )
        try validate(state)
        return state
    }

    private func validate(_ state: ClaudeLoginState) throws {
        guard state.snapshots.count <= 2,
              state.snapshots.keys.allSatisfy({ $0.range(of: #"^[a-z][a-z0-9_-]{0,31}$"#, options: .regularExpression) != nil }),
              state.activeAlias.map({ state.snapshots[$0] != nil }) ?? true,
              Set(state.snapshots.values.map(\.identity)).count == state.snapshots.count else {
            throw ClaudeLoginEnvelopeError.invalid
        }
        if let journal = state.journal {
            try validateRawValues(journal.before)
            try validateRawValues(journal.after)
            guard UUID(uuidString: journal.operationID) != nil,
                  let source = state.snapshots[journal.source], let target = state.snapshots[journal.target],
                  Set(journal.before.secure.keys) == ["claudeAiOauth", "organizationUuid", "trustedDeviceToken"],
                  Set(journal.after.secure.keys) == Set(journal.before.secure.keys),
                  Set(journal.before.configuration.keys) == Set(["oauthAccount"] + ClaudeConfigurationPatch.accountCacheKeys),
                  Set(journal.after.configuration.keys) == Set(journal.before.configuration.keys),
                  journal.before.secure == ClaudeLoginOwnedFields.target(source).secure,
                  journal.before.configuration["oauthAccount"] == source.oauthAccount,
                  journal.after == ClaudeLoginOwnedFields.target(target),
                  journal.phase != .committed || state.activeAlias == journal.target else {
                throw ClaudeLoginEnvelopeError.invalid
            }
        }
        for snapshot in state.snapshots.values {
            let reconstructed = try reconstructedSnapshot(
                claudeAiOauth: Presence(snapshot.claudeAiOauth),
                oauthAccount: Presence(snapshot.oauthAccount),
                organizationUUID: Presence(snapshot.organizationUUID),
                trustedDeviceToken: Presence(snapshot.trustedDeviceToken)
            )
            guard reconstructed == snapshot else { throw ClaudeLoginEnvelopeError.invalid }
        }
    }

    private func validateRawValues(_ fields: ClaudeLoginOwnedFields) throws {
        for presence in Array(fields.secure.values) + fields.configuration.values {
            _ = try Presence(presence).decoded(maxBytes: maxBytes, maxDepth: maxDepth)
        }
    }

    private func reconstructedSnapshot(
        claudeAiOauth: Presence,
        oauthAccount: Presence,
        organizationUUID: Presence,
        trustedDeviceToken: Presence
    ) throws -> ClaudeLoginSnapshot {
        do {
            let secure = try ScopedJSON("{}").replacing([
                "claudeAiOauth": try claudeAiOauth.decoded(maxBytes: maxBytes, maxDepth: maxDepth),
                "organizationUuid": try organizationUUID.decoded(maxBytes: maxBytes, maxDepth: maxDepth),
                "trustedDeviceToken": try trustedDeviceToken.decoded(maxBytes: maxBytes, maxDepth: maxDepth)
            ])
            let configuration = try ScopedJSON("{}").replacing([
                "oauthAccount": try oauthAccount.decoded(maxBytes: maxBytes, maxDepth: maxDepth)
            ])
            return try ClaudeLoginSnapshot.capture(secureRoot: secure, configurationRoot: configuration)
        } catch let error as ClaudeLoginEnvelopeError {
            throw error
        } catch {
            throw ClaudeLoginEnvelopeError.invalid
        }
    }

    private static func admitRawValue(_ raw: String, maxBytes: Int, maxDepth: Int) throws {
        let data = Data(raw.utf8)
        guard data.count <= maxBytes else { throw ClaudeLoginEnvelopeError.tooLarge }
        guard hasBoundedDepth(data, maxDepth: maxDepth) else { throw ClaudeLoginEnvelopeError.invalid }
        do { _ = try ScopedJSON("{}").replacing(["value": .value(raw)]) }
        catch { throw ClaudeLoginEnvelopeError.invalid }
    }

    private static func hasBoundedDepth(_ data: Data, maxDepth: Int) -> Bool {
        var depth = 0
        var inString = false
        var escaped = false
        for byte in data {
            if inString {
                if escaped { escaped = false }
                else if byte == 0x5C { escaped = true }
                else if byte == 0x22 { inString = false }
            } else if byte == 0x22 {
                inString = true
            } else if byte == 0x7B || byte == 0x5B {
                depth += 1
                if depth > maxDepth { return false }
            } else if byte == 0x7D || byte == 0x5D {
                depth -= 1
                if depth < 0 { return false }
            }
        }
        return depth == 0 && !inString && !escaped
    }
}

struct ClaudeLoginCustody {
    let store: any ClaudeLoginDataStore
    var codec = ClaudeLoginEnvelopeCodec()

    func load() throws -> ClaudeLoginState {
        try loadWithPresence().state
    }

    func loadWithPresence() throws -> (state: ClaudeLoginState, exists: Bool) {
        do { return (try codec.decode(store.read()), true) }
        catch IsolatedKeychainError.missing { return (ClaudeLoginState(), false) }
    }

    func loadRecoveryRecord() throws -> ClaudeLoginState {
        try codec.decodeRecoveryRecord(store.read())
    }

    func save(
        _ state: ClaudeLoginState,
        expectedExisting: Bool? = nil,
        guardedBy guardMutation: () throws -> Void = {},
        permitsJournal: Bool = false
    ) throws {
        let encoded = try codec.encode(state)
        do {
            let existing = try store.read()
            _ = permitsJournal ? try codec.decodeRecoveryRecord(existing) : try codec.decode(existing)
        } catch IsolatedKeychainError.missing {
            guard expectedExisting != true else { throw IsolatedKeychainError.missing }
            try store.create(data: encoded, guardedBy: guardMutation)
            try verify(encoded, represents: state, permitsJournal: permitsJournal)
            return
        }
        guard expectedExisting != false else { throw IsolatedKeychainError.corrupt }
        try store.update(data: encoded, guardedBy: guardMutation)
        try verify(encoded, represents: state, permitsJournal: permitsJournal)
    }

    private func verify(_ encoded: Data, represents state: ClaudeLoginState, permitsJournal: Bool) throws {
        do {
            let readback = try store.read()
            let decoded = permitsJournal ? try codec.decodeRecoveryRecord(readback) : try codec.decode(readback)
            guard readback == encoded, decoded == state else {
                throw ClaudeLoginEnvelopeError.readbackMismatch
            }
        } catch {
            throw ClaudeLoginEnvelopeError.readbackMismatch
        }
    }
}

enum ManagerKeychainPolicy {
    enum Error: Swift.Error, Equatable { case unapprovedBinary(OSStatus), accessCreation(OSStatus) }

    static func creationAttributes(uid: uid_t, approvedAccess: CFTypeRef) -> [CFString: Any] {
        [
            kSecAttrService: "AIControl-claude-logins.v1",
            kSecAttrAccount: String(uid),
            kSecAttrSynchronizable: false,
            kSecAttrAccess: approvedAccess
        ]
    }

    static func creationAttributes(
        uid: uid_t = geteuid(),
        approvedBinaryPath: String,
        calls: ManagerKeychainNativeCalls = .live
    ) throws -> [CFString: Any] {
        let (applicationStatus, application) = calls.createTrustedApplication(approvedBinaryPath)
        guard applicationStatus == errSecSuccess, let application else {
            throw Error.unapprovedBinary(applicationStatus)
        }
        let (accessStatus, access) = calls.createAccess(
            "AIControl Claude login manager" as CFString,
            [application] as CFArray
        )
        guard accessStatus == errSecSuccess, let access else { throw Error.accessCreation(accessStatus) }
        return creationAttributes(uid: uid, approvedAccess: access)
    }
}

struct IsolatedKeychainAdapter: ClaudeLoginDataStore {
    private let keychain: CFTypeRef
    private let service: String
    private let account: String
    private let calls: KeychainNativeCalls
    private let creationAttributes: [CFString: Any]
    private let beforeMutation: () throws -> Void

    init(
        keychain: CFTypeRef,
        service: String,
        account: String,
        creationAttributes: [CFString: Any] = [:],
        beforeMutation: @escaping () throws -> Void = {},
        calls: KeychainNativeCalls = .live
    ) {
        self.keychain = keychain
        self.service = service
        self.account = account
        self.creationAttributes = creationAttributes
        self.beforeMutation = beforeMutation
        self.calls = calls
    }

    init(
        keychain: CFTypeRef,
        approvedBinaryPath: String,
        uid: uid_t = geteuid(),
        policyCalls: ManagerKeychainNativeCalls = .live,
        beforeMutation: @escaping () throws -> Void = {},
        calls: KeychainNativeCalls = .live
    ) throws {
        let attributes = try ManagerKeychainPolicy.creationAttributes(
            uid: uid,
            approvedBinaryPath: approvedBinaryPath,
            calls: policyCalls
        )
        self.init(
            keychain: keychain,
            service: "AIControl-claude-logins.v1",
            account: String(uid),
            creationAttributes: attributes,
            beforeMutation: beforeMutation,
            calls: calls
        )
    }

    func create(data: Data) throws {
        try create(data: data, guardedBy: beforeMutation)
    }

    func create(data: Data, guardedBy guardMutation: () throws -> Void) throws {
        var query = creationAttributes
        identityQuery.forEach { query[$0] = $1 }
        query[kSecUseKeychain] = keychain
        query[kSecAttrSynchronizable] = false
        query[kSecValueData] = data
        try guardMutation()
        try check(calls.add(query as CFDictionary))
    }

    func read() throws -> Data {
        let reference = try persistentReference()
        return try readData(reference: reference)
    }

    private func readData(reference: Data) throws -> Data {
        var query = referenceQuery(reference)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        try check(calls.copy(query as CFDictionary, &result))
        guard let data = result as? Data else { throw IsolatedKeychainError.corrupt }
        return data
    }

    func update(data: Data) throws {
        try update(data: data, guardedBy: beforeMutation)
    }

    func update(data: Data, guardedBy guardMutation: () throws -> Void) throws {
        let reference = try persistentReference()
        try guardMutation()
        try check(calls.update(
            referenceQuery(reference) as CFDictionary,
            [kSecValueData: data] as CFDictionary
        ))
    }

    func replace(expectedData: Data, with data: Data, guardedBy guardMutation: () throws -> Void) throws {
        let reference = try persistentReference()
        guard try readData(reference: reference) == expectedData else { throw IsolatedKeychainError.corrupt }
        try guardMutation()
        try check(calls.update(
            referenceQuery(reference) as CFDictionary,
            [kSecValueData: data] as CFDictionary
        ))
    }

    func delete() throws {
        let reference = try persistentReference()
        try check(calls.delete(referenceQuery(reference) as CFDictionary))
    }

    private var exactQuery: [CFString: Any] {
        var query = identityQuery
        query[kSecMatchSearchList] = [keychain]
        return query
    }

    private var identityQuery: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
    }

    private func persistentReference() throws -> Data {
        var query = exactQuery
        query[kSecReturnPersistentRef] = true
        query[kSecMatchLimit] = kSecMatchLimitAll
        var result: CFTypeRef?
        try check(calls.copy(query as CFDictionary, &result))
        guard let references = result as? [Data] else { throw IsolatedKeychainError.corrupt }
        guard references.count == 1, let reference = references.first else {
            throw IsolatedKeychainError.ambiguous
        }
        return reference
    }

    private func referenceQuery(_ reference: Data) -> [CFString: Any] {
        [
            kSecValuePersistentRef: reference,
            kSecMatchSearchList: [keychain]
        ]
    }

    private func check(_ status: OSStatus) throws {
        switch status {
        case errSecSuccess: return
        case errSecItemNotFound: throw IsolatedKeychainError.missing
        case errSecDuplicateItem: throw IsolatedKeychainError.duplicate
        case errSecAuthFailed: throw IsolatedKeychainError.denied
        case errSecUserCanceled: throw IsolatedKeychainError.cancelled
        case errSecInteractionNotAllowed: throw IsolatedKeychainError.locked
        default: throw IsolatedKeychainError.operatingSystem(status)
        }
    }

    @discardableResult
    static func removeFromSearchList(_ keychain: SecKeychain) -> Bool {
        var current: CFArray?
        guard SecKeychainCopySearchList(&current) == errSecSuccess,
              let entries = current as? [SecKeychain] else { return false }
        let filtered = entries.filter { !CFEqual($0, keychain) }
        guard filtered.count == entries.count ||
                SecKeychainSetSearchList(filtered as CFArray) == errSecSuccess else { return false }
        var verified: CFArray?
        guard SecKeychainCopySearchList(&verified) == errSecSuccess,
              let remaining = verified as? [SecKeychain] else { return false }
        return !remaining.contains { CFEqual($0, keychain) }
    }
}

enum ProtectedConfigurationError: Error, Equatable {
    case tooLarge
    case tooDeep
    case invalidDocument
    case unsafeFile
    case changedBeforeCommit
    case writeFailed
    case indeterminateAfterCommit
}

struct ClaudeConfigurationPatch {
    var oauthAccount: JSONPresence?
    var invalidateAccountCaches: Bool

    init(oauthAccount: JSONPresence? = nil, invalidateAccountCaches: Bool = false) {
        self.oauthAccount = oauthAccount
        self.invalidateAccountCaches = invalidateAccountCaches
    }

    fileprivate var changes: [String: JSONPresence] {
        var result: [String: JSONPresence] = [:]
        if let oauthAccount { result["oauthAccount"] = oauthAccount }
        if invalidateAccountCaches {
            for key in Self.accountCacheKeys { result[key] = .missing }
        }
        return result
    }

    static let accountCacheKeys = [
        "additionalModelOptionsCache", "additionalModelCostsCache", "modelAccessCache",
        "orgModelDefaultCache", "lastSeenOrgDefaultUpdatedAt", "clientDataCache",
        "clientDataCacheSlots", "autoCompactWindowsCache", "cachedUsageUtilization"
    ]
}

struct ProtectedConfigurationHooks {
    var beforeCommit: () throws -> Void
    var afterCommit: () throws -> Void

    init(
        beforeCommit: @escaping () throws -> Void = {},
        afterCommit: @escaping () throws -> Void = {}
    ) {
        self.beforeCommit = beforeCommit
        self.afterCommit = afterCommit
    }
}

struct ProtectedConfigurationFile {
    private struct Snapshot {
        let descriptor: Int32
        let metadata: stat
        let data: Data
    }

    let path: String
    var maxBytes = 1_048_576
    var maxDepth = 64
    var expectedOwner = geteuid()
    var hooks = ProtectedConfigurationHooks()

    func update(_ patch: ClaudeConfigurationPatch) throws {
        try replace(expectedSource: nil, with: patch, guardedBy: {})
    }

    private func replace(
        expectedSource: String?,
        with patch: ClaudeConfigurationPatch,
        guardedBy guardMutation: () throws -> Void
    ) throws {
        let initial = try snapshot()
        defer { close(initial.descriptor) }
        let source = try admittedString(initial.data)
        guard expectedSource == nil || source == expectedSource else {
            throw ProtectedConfigurationError.changedBeforeCommit
        }
        let rendered: String
        do {
            rendered = try ScopedJSON(source).replacing(patch.changes)
        } catch {
            throw ProtectedConfigurationError.invalidDocument
        }
        let output = Data(rendered.utf8)
        guard output.count <= maxBytes else { throw ProtectedConfigurationError.tooLarge }
        _ = try admittedString(output)

        let directory = URL(fileURLWithPath: path).deletingLastPathComponent().path
        let temporary = directory + "/.aicontrol-" + UUID().uuidString
        var committed = false
        defer { if !committed { unlink(temporary) } }
        let temporaryDescriptor = open(temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard temporaryDescriptor >= 0 else { throw ProtectedConfigurationError.writeFailed }
        defer { close(temporaryDescriptor) }

        guard writeAll(output, to: temporaryDescriptor),
              fchown(temporaryDescriptor, initial.metadata.st_uid, initial.metadata.st_gid) == 0,
              fchmod(temporaryDescriptor, initial.metadata.st_mode & 0o7777) == 0,
              fcopyfile(initial.descriptor, temporaryDescriptor, nil, copyfile_flags_t(COPYFILE_ACL)) == 0,
              fsync(temporaryDescriptor) == 0 else {
            throw ProtectedConfigurationError.writeFailed
        }
        do { try hooks.beforeCommit() } catch { throw ProtectedConfigurationError.writeFailed }
        let current = try snapshot()
        defer { close(current.descriptor) }
        guard sameIdentityAndProtection(initial.metadata, current.metadata), initial.data == current.data else {
            throw ProtectedConfigurationError.changedBeforeCommit
        }
        try guardMutation()
        var temporaryMetadata = stat()
        guard fstat(temporaryDescriptor, &temporaryMetadata) == 0,
              sameProtection(initial.metadata, temporaryMetadata) else {
            throw ProtectedConfigurationError.writeFailed
        }
        guard rename(temporary, path) == 0 else { throw ProtectedConfigurationError.writeFailed }
        committed = true

        do {
            try hooks.afterCommit()
            let directoryDescriptor = open(directory, O_RDONLY)
            guard directoryDescriptor >= 0 else { throw ProtectedConfigurationError.writeFailed }
            defer { close(directoryDescriptor) }
            guard fsync(directoryDescriptor) == 0 else { throw ProtectedConfigurationError.writeFailed }
            let verified = try snapshot()
            defer { close(verified.descriptor) }
            guard verified.data == output, sameProtection(initial.metadata, verified.metadata) else {
                throw ProtectedConfigurationError.writeFailed
            }
        } catch {
            throw ProtectedConfigurationError.indeterminateAfterCommit
        }
    }

    func replace(expectedSource: String, with patch: ClaudeConfigurationPatch, guardedBy guardMutation: () throws -> Void) throws {
        try replace(expectedSource: Optional(expectedSource), with: patch, guardedBy: guardMutation)
    }

    private func snapshot() throws -> Snapshot {
        var pathMetadata = stat()
        guard lstat(path, &pathMetadata) == 0, (pathMetadata.st_mode & S_IFMT) == S_IFREG else {
            throw ProtectedConfigurationError.unsafeFile
        }
        let descriptor = open(path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw ProtectedConfigurationError.unsafeFile }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              metadata.st_dev == pathMetadata.st_dev, metadata.st_ino == pathMetadata.st_ino,
              metadata.st_uid == expectedOwner, (metadata.st_mode & 0o022) == 0,
              metadata.st_size >= 0, metadata.st_size <= maxBytes else {
            close(descriptor)
            if metadata.st_size > maxBytes { throw ProtectedConfigurationError.tooLarge }
            throw ProtectedConfigurationError.unsafeFile
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        guard let data = try? handle.read(upToCount: maxBytes + 1), data.count <= maxBytes else {
            close(descriptor)
            throw ProtectedConfigurationError.tooLarge
        }
        return Snapshot(descriptor: descriptor, metadata: metadata, data: data)
    }

    private func admittedString(_ data: Data) throws -> String {
        var depth = 0
        var quoted = false
        var escaped = false
        for byte in data {
            if quoted {
                if escaped { escaped = false }
                else if byte == 0x5C { escaped = true }
                else if byte == 0x22 { quoted = false }
            } else if byte == 0x22 { quoted = true }
            else if byte == 0x7B || byte == 0x5B {
                depth += 1
                guard depth <= maxDepth else { throw ProtectedConfigurationError.tooDeep }
            } else if byte == 0x7D || byte == 0x5D { depth -= 1 }
        }
        guard let source = String(data: data, encoding: .utf8) else {
            throw ProtectedConfigurationError.invalidDocument
        }
        return source
    }

    private func writeAll(_ data: Data, to descriptor: Int32) -> Bool {
        data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return true }
            var offset = 0
            while offset < bytes.count {
                let count = write(descriptor, base.advanced(by: offset), bytes.count - offset)
                guard count > 0 else { return false }
                offset += count
            }
            return true
        }
    }

    private func sameIdentityAndProtection(_ lhs: stat, _ rhs: stat) -> Bool {
        lhs.st_dev == rhs.st_dev && lhs.st_ino == rhs.st_ino && sameProtection(lhs, rhs)
    }

    private func sameProtection(_ lhs: stat, _ rhs: stat) -> Bool {
        lhs.st_uid == rhs.st_uid && lhs.st_gid == rhs.st_gid &&
            (lhs.st_mode & 0o7777) == (rhs.st_mode & 0o7777)
    }
}

enum ManagerFileLockError: Error, Equatable {
    case unsafeDirectory
    case unsafeFile
    case contended
    case systemFailure
}

final class ManagerFileLock {
    private var descriptor: Int32

    private init(descriptor: Int32) { self.descriptor = descriptor }

    static func acquire(directory: String, expectedOwner: uid_t = geteuid()) throws -> ManagerFileLock {
        if mkdir(directory, 0o700) != 0 && errno != EEXIST {
            throw ManagerFileLockError.systemFailure
        }
        var pathMetadata = stat()
        guard lstat(directory, &pathMetadata) == 0,
              (pathMetadata.st_mode & S_IFMT) == S_IFDIR,
              pathMetadata.st_uid == expectedOwner,
              (pathMetadata.st_mode & 0o777) == 0o700 else {
            throw ManagerFileLockError.unsafeDirectory
        }
        let directoryDescriptor = open(directory, O_RDONLY | O_NOFOLLOW)
        guard directoryDescriptor >= 0 else { throw ManagerFileLockError.unsafeDirectory }
        defer { close(directoryDescriptor) }
        var directoryMetadata = stat()
        guard fstat(directoryDescriptor, &directoryMetadata) == 0,
              directoryMetadata.st_dev == pathMetadata.st_dev,
              directoryMetadata.st_ino == pathMetadata.st_ino,
              directoryMetadata.st_uid == expectedOwner,
              (directoryMetadata.st_mode & 0o777) == 0o700 else {
            throw ManagerFileLockError.unsafeDirectory
        }

        let name = "claude-login.lock"
        var prior = stat()
        let existed = fstatat(directoryDescriptor, name, &prior, AT_SYMLINK_NOFOLLOW) == 0
        if !existed && errno != ENOENT { throw ManagerFileLockError.systemFailure }
        if existed && (prior.st_mode & S_IFMT) != S_IFREG { throw ManagerFileLockError.unsafeFile }
        let fileDescriptor = openat(directoryDescriptor, name, O_RDWR | O_CREAT | O_NOFOLLOW, 0o600)
        guard fileDescriptor >= 0 else { throw ManagerFileLockError.unsafeFile }
        var fileMetadata = stat()
        guard fstat(fileDescriptor, &fileMetadata) == 0,
              (!existed || (fileMetadata.st_dev == prior.st_dev && fileMetadata.st_ino == prior.st_ino)),
              (fileMetadata.st_mode & S_IFMT) == S_IFREG,
              fileMetadata.st_uid == expectedOwner,
              (fileMetadata.st_mode & 0o777) == 0o600 else {
            close(fileDescriptor)
            throw ManagerFileLockError.unsafeFile
        }
        guard flock(fileDescriptor, LOCK_EX | LOCK_NB) == 0 else {
            let failure = errno
            close(fileDescriptor)
            if failure == EWOULDBLOCK || failure == EAGAIN { throw ManagerFileLockError.contended }
            throw ManagerFileLockError.systemFailure
        }
        return ManagerFileLock(descriptor: fileDescriptor)
    }

    func release() {
        guard descriptor >= 0 else { return }
        _ = flock(descriptor, LOCK_UN)
        close(descriptor)
        descriptor = -1
    }

    deinit { release() }
}

enum ClaudeRoutingConflict: Hashable, Sendable {
    case configurationOverride
    case secureStorageOverride
    case customOAuth
    case plaintextFallback
    case legacyStorage
    case alternateAuthentication
    case unsupportedProviderState
}

struct ClaudeRoutingEvidence: Sendable {
    let version: String
    let executableSHA256: String
    let resolvedConfigurationPath: String
    let defaultConfigurationPath: String
    let environmentUser: String?
    let operatingSystemUser: String?
    let conflicts: Set<ClaudeRoutingConflict>
}

struct ClaudeStorageRoute: Equatable, Sendable {
    let service: String
    let account: String
    let configurationPath: String
}

enum ClaudeRoutingError: Error, Equatable {
    case unsupportedBuild
    case unexpectedHash
    case nonDefaultResolver
    case conflictingSource
}

enum ClaudeRoutingValidator {
    static let version = "2.1.252"
    static let executableSHA256 = "b661c6a094fcc32656bf7c0071c5b45bf900b34d4f0a1ab3d78fd59aeba2c2c7"

    static func route(_ evidence: ClaudeRoutingEvidence) throws -> ClaudeStorageRoute {
        guard evidence.version == version else { throw ClaudeRoutingError.unsupportedBuild }
        guard evidence.executableSHA256.lowercased() == executableSHA256 else {
            throw ClaudeRoutingError.unexpectedHash
        }
        guard evidence.resolvedConfigurationPath == evidence.defaultConfigurationPath else {
            throw ClaudeRoutingError.nonDefaultResolver
        }
        guard evidence.conflicts.isEmpty else { throw ClaudeRoutingError.conflictingSource }
        let candidate = evidence.environmentUser ?? evidence.operatingSystemUser
        let account = candidate?.range(of: #"^[a-zA-Z0-9._-]+$"#, options: .regularExpression) == nil
            ? "claude-code-user" : candidate ?? "claude-code-user"
        return .init(
            service: "Claude Code-credentials",
            account: account,
            configurationPath: evidence.resolvedConfigurationPath
        )
    }
}

enum ClaudeProcessRole: CaseIterable, Sendable {
    case terminal
    case editor
    case sdk
    case daemon
    case remoteControl
}

struct ClaudeProcessRecord: Equatable, Sendable {
    let pid: pid_t
    let parentPID: pid_t?
    let uid: uid_t?
    let executablePath: String?
    let role: ClaudeProcessRole?
    let isZombie: Bool

    init(
        pid: pid_t,
        parentPID: pid_t?,
        uid: uid_t?,
        executablePath: String?,
        role: ClaudeProcessRole?,
        isZombie: Bool = false
    ) {
        self.pid = pid
        self.parentPID = parentPID
        self.uid = uid
        self.executablePath = executablePath
        self.role = role
        self.isZombie = isZombie
    }
}

struct ProcessNativeCalls {
    let listPIDs: (UnsafeMutableRawPointer?, Int32) -> Int32
    let processInfo: (pid_t, Int32, UInt64, UnsafeMutableRawPointer?, Int32) -> Int32
    let processPath: (pid_t, UnsafeMutableRawPointer?, UInt32) -> Int32

    static let live = Self(
        listPIDs: { proc_listpids(UInt32(PROC_ALL_PIDS), 0, $0, $1) },
        processInfo: proc_pidinfo,
        processPath: proc_pidpath
    )
}

struct NativeProcessProbe {
    let snapshot: () throws -> [ClaudeProcessRecord]

    static func system(
        processIDs: (() throws -> [pid_t])? = nil,
        calls: ProcessNativeCalls = .live
    ) -> Self {
        .init(snapshot: {
            let processIDs = try validated(processIDs?() ?? inventory(calls: calls))
            return try processIDs.map { pid in
                var info = proc_bsdshortinfo()
                let infoSize = Int32(MemoryLayout<proc_bsdshortinfo>.size)
                guard calls.processInfo(pid, PROC_PIDT_SHORTBSDINFO, 1, &info, infoSize) == infoSize,
                      info.pbsi_pid == UInt32(pid) else {
                    throw ClaudeProcessPreflightError.uncertain
                }
                let isZombie = info.pbsi_status == UInt32(SZOMB)
                return .init(
                    pid: pid,
                    parentPID: pid_t(info.pbsi_ppid),
                    uid: info.pbsi_uid,
                    executablePath: isZombie ? nil : try executablePath(pid: pid, calls: calls),
                    role: nil,
                    isZombie: isZombie
                )
            }
        })
    }

    private static func inventory(calls: ProcessNativeCalls) throws -> [pid_t] {
        let byteCount = calls.listPIDs(nil, 0)
        let stride = Int32(MemoryLayout<pid_t>.stride)
        guard byteCount > 0, byteCount <= 1 << 20, byteCount % stride == 0 else {
            throw ClaudeProcessPreflightError.uncertain
        }
        var pids = [pid_t](repeating: 0, count: Int(byteCount / stride))
        let copied = pids.withUnsafeMutableBytes {
            calls.listPIDs($0.baseAddress, Int32($0.count))
        }
        guard copied > 0, copied < byteCount, copied % stride == 0 else {
            throw ClaudeProcessPreflightError.uncertain
        }
        return Array(pids.prefix(Int(copied / stride)))
    }

    private static func validated(_ processIDs: [pid_t]) throws -> [pid_t] {
        var seen: Set<pid_t> = []
        return try processIDs.compactMap { pid in
            if pid == 0 { return nil }
            guard pid > 0, seen.insert(pid).inserted else {
                throw ClaudeProcessPreflightError.uncertain
            }
            return pid
        }
    }

    private static func executablePath(pid: pid_t, calls: ProcessNativeCalls) throws -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let copied = calls.processPath(pid, &buffer, UInt32(buffer.count))
        guard copied > 0, copied < buffer.count else { throw ClaudeProcessPreflightError.uncertain }
        let end = min(Int(copied) + 1, buffer.count)
        guard let terminator = buffer[..<end].firstIndex(of: 0), terminator > 0,
              let path = String(bytes: buffer[..<terminator].map(UInt8.init(bitPattern:)), encoding: .utf8),
              !path.isEmpty else {
            throw ClaudeProcessPreflightError.uncertain
        }
        return path
    }
}

enum ClaudeProcessPreflightError: Error, Equatable {
    case active
    case uncertain
}

struct ClaudeProcessPreflight {
    let expectedUID: uid_t
    let trustedExecutablePath: String
    let probe: NativeProcessProbe

    func requireQuiescent() throws {
        let records: [ClaudeProcessRecord]
        do { records = try probe.snapshot() } catch { throw ClaudeProcessPreflightError.uncertain }
        var byPID: [pid_t: ClaudeProcessRecord] = [:]
        for record in records {
            let validLifecycle = record.isZombie
                ? record.executablePath == nil && record.role == nil
                : record.executablePath?.isEmpty == false
            guard record.pid > 0, record.parentPID.map({ $0 >= 0 }) ?? true,
                  record.uid != nil, validLifecycle,
                  byPID.updateValue(record, forKey: record.pid) == nil else {
                throw ClaudeProcessPreflightError.uncertain
            }
        }
        for origin in records where origin.uid == expectedUID {
            var current: ClaudeProcessRecord? = origin
            var visited: Set<pid_t> = []
            while let record = current {
                guard visited.insert(record.pid).inserted else {
                    throw ClaudeProcessPreflightError.uncertain
                }
                if !record.isZombie && (record.role != nil || record.executablePath == trustedExecutablePath) {
                    throw ClaudeProcessPreflightError.active
                }
                guard let parent = record.parentPID, let ancestor = byPID[parent],
                      ancestor.uid == expectedUID else { break }
                current = ancestor
            }
        }
    }

    func performGuarded(write: () throws -> Void, verify: () throws -> Void) throws {
        try requireQuiescent()
        try write()
        try verify()
        try requireQuiescent()
    }
}
