import Foundation
import Testing
@testable import AIControlCore

struct CodexLoginTests {
    @Test("Identity comes from the ChatGPT account id and the id token email, offline")
    func identityIsReadOffline() throws {
        let identity = try CodexAuthFile.identity(codexAuth(account: "acct-a", email: "a@example.com"))
        #expect(identity == .init(accountID: "acct-a", email: "a@example.com"))
        #expect(throws: CodexLoginError.unsupportedAuth) {
            try CodexAuthFile.identity(Data(#"{"auth_mode":"apikey","OPENAI_API_KEY":"k"}"#.utf8))
        }
        #expect(throws: CodexLoginError.unsupportedAuth) {
            try CodexAuthFile.identity(codexAuth(account: "", email: "a@example.com"))
        }
    }

    @Test("Save stores the live login once per account and refuses name or account collisions")
    func saveStoresEachAccountOnce() throws {
        let fixture = try CodexFixture()
        defer { fixture.cleanup() }
        fixture.live = try codexAuth(account: "acct-a", email: "a@example.com")

        #expect(fixture.run("save", "work") == 0)
        #expect(fixture.run("save", "other") == 3)
        fixture.live = try codexAuth(account: "acct-b", email: "b@example.com")
        #expect(fixture.run("save", "work") == 3)
        #expect(fixture.run("save", "home") == 0)
        #expect(fixture.run("list") == 0)
        #expect(fixture.messages == [
            "Saved Codex login work (a@example.com).",
            "Blocked: this Codex login is already saved as work.",
            "Blocked: work belongs to another Codex account.",
            "Saved Codex login home (b@example.com).",
            "home: b@example.com (in use)", "work: a@example.com"
        ])
    }

    @Test("Use re-saves the outgoing login, then swaps auth.json and keeps its protection")
    func useCheckpointsThenSwaps() throws {
        let fixture = try CodexFixture()
        defer { fixture.cleanup() }
        let a1 = try codexAuth(account: "acct-a", email: "a@example.com", refresh: "ra1")
        let b1 = try codexAuth(account: "acct-b", email: "b@example.com", refresh: "rb1")
        fixture.live = a1
        #expect(fixture.run("save", "work") == 0)
        fixture.live = b1
        #expect(fixture.run("save", "home") == 0)
        let b2 = try codexAuth(account: "acct-b", email: "b@example.com", refresh: "rb2")
        fixture.live = b2

        #expect(fixture.run("use", "work") == 0)
        #expect(fixture.live == a1)
        #expect(fixture.mode == 0o600)
        #expect(fixture.run("use", "home") == 0)
        #expect(fixture.live == b2)
        #expect(fixture.messages.suffix(2) == [
            "Switched Codex to work.",
            "Switched Codex to home."
        ])
    }

    @Test("Use refuses an unsaved live login, an unknown alias, keyring storage, and a concurrent change")
    func useRefusesUnsafeStates() throws {
        let fixture = try CodexFixture()
        defer { fixture.cleanup() }
        let a1 = try codexAuth(account: "acct-a", email: "a@example.com")
        fixture.live = a1
        #expect(fixture.run("save", "work") == 0)
        let stranger = try codexAuth(account: "acct-c", email: "c@example.com")
        fixture.live = stranger

        #expect(fixture.run("use", "work") == 3)
        #expect(fixture.run("use", "missing") == 3)
        #expect(fixture.live == stranger)

        fixture.live = a1
        fixture.keyringHoldsLogin = true
        #expect(fixture.run("use", "work") == 3)
        fixture.keyringHoldsLogin = false

        let b1 = try codexAuth(account: "acct-b", email: "b@example.com")
        fixture.live = b1
        #expect(fixture.run("save", "home") == 0)
        let refreshed = try codexAuth(account: "acct-b", email: "b@example.com", refresh: "rb9")
        fixture.beforeReplace = { fixture.live = refreshed }
        #expect(fixture.run("use", "work") == 3)
        #expect(fixture.live == refreshed)
        #expect(fixture.messages.filter { $0.hasPrefix("Blocked") } == [
            "Blocked: the current Codex login (c@example.com) is not saved; save it first.",
            "Blocked: no Codex login is saved as missing.",
            "Blocked: Codex keeps its login in the Keychain; only auth.json logins can be switched.",
            "Blocked: Codex changed its login during the switch; try again."
        ])
    }

    @Test("Preparing a login re-saves the live login and removes auth.json so codex login has nothing to revoke")
    func prepareLoginDetachesLiveLogin() throws {
        let fixture = try CodexFixture()
        defer { fixture.cleanup() }
        let a1 = try codexAuth(account: "acct-a", email: "a@example.com", refresh: "ra1")
        fixture.live = a1
        #expect(fixture.run("save", "work") == 0)
        let a2 = try codexAuth(account: "acct-a", email: "a@example.com", refresh: "ra2")
        fixture.live = a2

        #expect(fixture.run("prepare-login") == 0)
        #expect(fixture.live == nil)
        #expect(fixture.run("use", "work") == 0)
        #expect(fixture.live == a2)

        fixture.live = try codexAuth(account: "acct-c", email: "c@example.com")
        #expect(fixture.run("prepare-login") == 3)
        #expect(fixture.live != nil)
        #expect(fixture.messages.contains("Saved work; auth.json cleared for codex login."))
    }

    @Test("Rename moves a saved Codex login")
    func renameMovesLogin() throws {
        let fixture = try CodexFixture()
        defer { fixture.cleanup() }
        fixture.live = try codexAuth(account: "acct-a", email: "a@example.com")
        #expect(fixture.run("save", "work") == 0)
        #expect(fixture.run("rename", "work", "job") == 0)
        #expect(fixture.run("use", "job") == 0)
        #expect(fixture.messages[1] == "Renamed Codex login work to job.")
    }
}

private func codexAuth(account: String, email: String, refresh: String = "refresh") throws -> Data {
    let payload = try JSONSerialization.data(withJSONObject: ["email": email])
        .base64EncodedString().replacingOccurrences(of: "=", with: "")
        .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
    let auth: [String: Any] = [
        "auth_mode": "chatgpt", "OPENAI_API_KEY": NSNull(), "last_refresh": "2026-09-26T00:00:00Z",
        "tokens": ["id_token": "h.\(payload).s", "access_token": "access", "refresh_token": refresh, "account_id": account]
    ]
    return try JSONSerialization.data(withJSONObject: auth, options: [.sortedKeys])
}

private final class CodexFixture {
    let directory: URL
    var messages: [String] = []
    var keyringHoldsLogin = false
    var beforeReplace: (() -> Void)?
    private let store = CodexMemoryStore()

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("codex-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    }

    var authPath: String { directory.appendingPathComponent("auth.json").path }

    var live: Data? {
        get { FileManager.default.contents(atPath: authPath) }
        set {
            try? FileManager.default.removeItem(atPath: authPath)
            if let newValue { FileManager.default.createFile(atPath: authPath, contents: newValue, attributes: [.posixPermissions: 0o600]) }
        }
    }

    var mode: Int? { (try? FileManager.default.attributesOfItem(atPath: authPath))?[.posixPermissions] as? Int }

    func run(_ arguments: String...) -> Int32 {
        let system = CodexLoginSystem(
            authPath: authPath, store: store,
            acquireLock: { [directory] in try ManagerFileLock.acquire(directory: directory.appendingPathComponent("lock").path) },
            keyringHoldsLogin: { self.keyringHoldsLogin },
            beforeReplace: { self.beforeReplace?() }
        )
        return runCodexLogins(arguments: ["codex-login"] + arguments, system: system, output: { self.messages.append($0) })
    }

    func cleanup() { try? FileManager.default.removeItem(at: directory) }
}

private final class CodexMemoryStore: ClaudeLoginDataStore {
    var data: Data?
    func read() throws -> Data {
        guard let data else { throw IsolatedKeychainError.missing }
        return data
    }
    func create(data: Data) throws {
        guard self.data == nil else { throw IsolatedKeychainError.duplicate }
        self.data = data
    }
    func update(data: Data) throws {
        guard self.data != nil else { throw IsolatedKeychainError.missing }
        self.data = data
    }
}
