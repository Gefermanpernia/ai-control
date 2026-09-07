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

struct IsolatedKeychainAdapter {
    private let keychain: CFTypeRef
    private let service: String
    private let account: String
    private let calls: KeychainNativeCalls

    init(
        keychain: CFTypeRef,
        service: String,
        account: String,
        calls: KeychainNativeCalls = .live
    ) {
        self.keychain = keychain
        self.service = service
        self.account = account
        self.calls = calls
    }

    func create(data: Data) throws {
        var query = identityQuery
        query[kSecUseKeychain] = keychain
        query[kSecAttrSynchronizable] = false
        query[kSecValueData] = data
        try check(calls.add(query as CFDictionary))
    }

    func read() throws -> Data {
        let reference = try persistentReference()
        var query = referenceQuery(reference)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        try check(calls.copy(query as CFDictionary, &result))
        guard let data = result as? Data else { throw IsolatedKeychainError.corrupt }
        return data
    }

    func update(data: Data) throws {
        let reference = try persistentReference()
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

    private static let accountCacheKeys = [
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
        let initial = try snapshot()
        defer { close(initial.descriptor) }
        let source = try admittedString(initial.data)
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
