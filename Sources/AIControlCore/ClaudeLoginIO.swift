import Foundation
import Security

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
