import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import AIControlCore

private struct StatusFailure: Error {}

private final class StatusLines: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []
    func append(_ line: String) { lock.withLock { stored.append(line) } }
    var last: String? { lock.withLock { stored.last } }
    func clear() { lock.withLock { stored = [] } }
}

private final class StatusClaudeBackend: ClaudeLoginBackend {
    var state: ClaudeLoginState
    var unreadable = false
    var current: ClaudeLoginSnapshot?
    init(_ state: ClaudeLoginState = .init()) { self.state = state }
    func loadState() throws -> ClaudeLoginState { if unreadable { throw StatusFailure() }; return state }
    func currentSnapshot() throws -> ClaudeLoginSnapshot { guard let current else { throw StatusFailure() }; return current }
    func saveState(_ state: ClaudeLoginState) throws { self.state = state }
}

private final class StatusCodexStore: ClaudeLoginDataStore {
    var data: Data
    init(_ data: Data) { self.data = data }
    func read() throws -> Data { data }
    func create(data: Data) throws { self.data = data }
    func update(data: Data) throws { self.data = data }
}

private final class StatusCodexFixture: @unchecked Sendable {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("status-codex-\(UUID().uuidString)")
    let store: StatusCodexStore
    init(saved: [String: Data]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        store = StatusCodexStore(try JSONEncoder().encode(CodexLoginState(logins: saved)))
    }
    var system: CodexLoginSystem {
        .init(authPath: directory.appendingPathComponent("auth.json").path, store: store,
              acquireLock: { [directory] in try ManagerFileLock.acquire(directory: directory.appendingPathComponent("lock").path) },
              keyringHoldsLogin: { false })
    }
    var live: Data? {
        get { FileManager.default.contents(atPath: directory.appendingPathComponent("auth.json").path) }
        set {
            let path = directory.appendingPathComponent("auth.json").path
            if let newValue { _ = FileManager.default.createFile(atPath: path, contents: newValue) }
        }
    }
    func cleanup() { try? FileManager.default.removeItem(at: directory) }
}

struct LoginStatusTests {
    private var noMonitors: UsageMonitors {
        .init(environment: [:], readFile: { _ in throw StatusFailure() },
              fetch: { _ in Issue.record("unexpected monitor fetch"); throw StatusFailure() }, now: Date.init)
    }

    private func snapshot(_ account: String) throws -> ClaudeLoginSnapshot {
        try .capture(secureRoot: #"{"claudeAiOauth":{"accessToken":"tok","refreshToken":"r","expiresAt":4102444800000}}"#,
                     configurationRoot: #"{"oauthAccount":{"accountUuid":"\#(account)"}}"#)
    }

    private func auth() -> Data {
        Data(#"{"auth_mode":"chatgpt","tokens":{"id_token":"h.eyJlbWFpbCI6ImFAZXhhbXBsZS5jb20ifQ.s","access_token":"h.eyJleHAiOjQxMDI0NDQ4MDB9.s","refresh_token":"r","account_id":"acct-a"}}"#.utf8)
    }

    private func adapters(
        claude backend: StatusClaudeBackend, codex fixture: StatusCodexFixture,
        claudeFetch: @escaping (URLRequest) async throws -> Data,
        codexFetch: @escaping (URLRequest) async throws -> Data
    ) -> (ClaudeLoginAppAdapter, CodexLoginAppAdapter) {
        (ClaudeLoginAppAdapter(makeBackend: { backend }, services: .init(
            liveSnapshot: { throw StatusFailure() }, renew: { $0 }, fetch: claudeFetch, signIn: { _ in },
            now: { Date(timeIntervalSince1970: 0) })),
         CodexLoginAppAdapter(makeSystem: { fixture.system }, services: .init(
            fetch: codexFetch, signIn: {}, renew: { $0 }, now: { Date(timeIntervalSince1970: 0) })))
    }

    private func document(_ status: LoginStatus) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try #require(JSONSerialization.jsonObject(with: encoder.encode(status)) as? [String: Any])
    }

    @Test("Status has complete null-bearing shape and never fetches usage without opt-in")
    func statusWithoutUsage() async throws {
        let backend = StatusClaudeBackend(.init(snapshots: ["work": try snapshot("a")], activeAlias: "work"))
        let fixture = try StatusCodexFixture(saved: ["home": auth()])
        defer { fixture.cleanup() }
        fixture.live = auth()
        let (claude, codex) = adapters(claude: backend, codex: fixture,
                                        claudeFetch: { _ in Issue.record("unexpected Claude fetch"); throw StatusFailure() },
                                        codexFetch: { _ in Issue.record("unexpected Codex fetch"); throw StatusFailure() })
        let root = try document(await loginStatus(claude: claude, codex: codex, includeUsage: false, monitors: noMonitors))
        #expect(root.keys.sorted() == ["claude", "codex", "monitors", "version"])
        #expect((root["monitors"] as? [Any])?.isEmpty == true)
        #expect(root["version"] as? Int == 1)
        let c = try #require(root["claude"] as? [String: Any])
        #expect(c.keys.sorted() == ["available", "installed", "logins", "selected"])
        #expect(c["available"] as? Bool == true && c["selected"] as? String == "work")
        let ca = try #require((c["logins"] as? [[String: Any]])?.first)
        #expect(ca.keys.sorted() == ["name", "needsLogin", "usage", "usageError"])
        #expect(ca["name"] as? String == "work" && ca["needsLogin"] as? Bool == false)
        #expect(ca["usage"] is NSNull && ca["usageError"] is NSNull)
        let x = try #require(root["codex"] as? [String: Any])
        #expect(x.keys.sorted() == ["available", "inUse", "installed", "logins"])
        #expect(x["available"] as? Bool == true && x["inUse"] as? String == "home")
        let xa = try #require((x["logins"] as? [[String: Any]])?.first)
        #expect(xa.keys.sorted() == ["email", "name", "usage", "usageError"])
        #expect(xa["email"] as? String == "a@example.com")
        #expect(xa["usage"] is NSNull && xa["usageError"] is NSNull)
    }

    @Test("Monitor JSON has explicit nulls, never exposes the key, and avoids fetch without opt-in")
    func monitorDocument() async throws {
        let secret = "monitor-secret-not-for-output"
        let monitor = UsageMonitors(environment: ["OPENCODE_AUTH_CONTENT":
            #"{"opencode-go":{"type":"api","key":"\#(secret)"}}"#],
            readFile: { _ in Issue.record("unexpected file read"); throw StatusFailure() },
            fetch: { _ in Issue.record("unexpected network fetch"); throw StatusFailure() }, now: Date.init)
        let snapshot = await loginStatus(claude: .init(), codex: .init(), includeUsage: false, monitors: monitor)
        let root = try document(snapshot)
        let value = try #require((root["monitors"] as? [[String: Any]])?.first)
        #expect(value.keys.sorted() == ["error", "id", "models", "name", "usage"])
        #expect(value["models"] is NSNull)
        #expect(value["id"] as? String == "opencode-go")
        #expect(value["name"] as? String == "OpenCode Go")
        #expect(value["usage"] is NSNull && value["error"] is NSNull)
        let encoder = JSONEncoder()
        #expect(!String(decoding: try encoder.encode(snapshot), as: UTF8.self).contains(secret))
    }

    @Test("NaN and OpenCode Go encode in stable order with explicit model nulls and no keys")
    func nanDocument() async throws {
        let secret = "nan-fixture-secret"
        let monitor = UsageMonitors(environment: ["OPENCODE_AUTH_CONTENT":
            #"{"opencode-go":{"type":"api","key":"go-fixture-secret"}}"#, "NAN_API_KEY": secret],
            readFile: { _ in Issue.record("unexpected file read"); throw StatusFailure() },
            fetch: { request in
                if request.url?.host == "api.nan.builders" {
                    return (200, Data(#"{"totals":{"by_model":[{"model":"glm5.3-flash","prompt_tokens":1,"completion_tokens":1,"total_tokens":2000000000,"api_requests":1},{"model":"glm5.3","prompt_tokens":0,"completion_tokens":1,"total_tokens":1,"api_requests":1}]}}"#.utf8))
                }
                return (401, Data())
            }, now: { ISO8601DateFormatter().date(from: "2026-09-27T12:00:00Z")! })
        let snapshot = await loginStatus(claude: .init(), codex: .init(), includeUsage: false, monitors: monitor)
        let values = try #require(try document(snapshot)["monitors"] as? [[String: Any]])
        #expect(values.map { $0["id"] as? String } == ["opencode-go", "nan"])
        for value in values {
            #expect(value.keys.sorted() == ["error", "id", "models", "name", "usage"])
            #expect(value["models"] is NSNull && value["usage"] is NSNull && value["error"] is NSNull)
        }
        let encoded = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        #expect(!encoded.contains(secret) && !encoded.contains("go-fixture-secret"))
        let withUsage = await loginStatus(claude: .init(), codex: .init(), includeUsage: true, monitors: monitor)
        let used = try #require(try document(withUsage)["monitors"] as? [[String: Any]])
        #expect(used.map { $0["id"] as? String } == ["opencode-go", "nan"])
        #expect(used[0]["models"] is NSNull)
        #expect(used[1]["usage"] is NSNull && used[1]["error"] is NSNull)
        let models = try #require(used[1]["models"] as? [[String: Any]])
        #expect(models.count == 2)
        #expect(models[0].keys.sorted() == ["model", "quotaTokens", "resetsAt", "totalTokens", "usedPercent"])
        #expect(models[0]["model"] as? String == "glm5.3-flash")
        #expect(models[0]["totalTokens"] as? Int == 2000000000)
        #expect(models[0]["quotaTokens"] as? Int == 2000000000)
        #expect((models[0]["usedPercent"] as? NSNumber)?.doubleValue == 100)
        #expect(models[0]["resetsAt"] as? String == "2026-10-01T00:00:00Z")
        #expect(models[1]["model"] as? String == "glm5.3")
        #expect(models[1]["quotaTokens"] is NSNull && models[1]["usedPercent"] is NSNull && models[1]["resetsAt"] is NSNull)
        #expect(!String(decoding: try JSONEncoder().encode(withUsage), as: UTF8.self).contains(secret))
    }

    @Test("Status usage includes ISO UTC dates and per-login failures")
    func statusWithUsage() async throws {
        let backend = StatusClaudeBackend(.init(snapshots: ["work": try snapshot("a")]))
        let fixture = try StatusCodexFixture(saved: ["home": auth()])
        defer { fixture.cleanup() }
        let (claude, codex) = adapters(claude: backend, codex: fixture,
            claudeFetch: { _ in Data(#"{"five_hour":{"utilization":12,"resets_at":"2026-09-26T19:39:59Z"}}"#.utf8) },
            codexFetch: { _ in throw StatusFailure() })
        let root = try document(await loginStatus(claude: claude, codex: codex, includeUsage: true, monitors: noMonitors))
        let ca = try #require(((root["claude"] as? [String: Any])?["logins"] as? [[String: Any]])?.first)
        let usage = try #require(ca["usage"] as? [String: Any])
        #expect(usage.keys.sorted() == ["fetchedAt", "resetsAvailable", "windows"])
        #expect(usage["fetchedAt"] as? String == "1970-01-01T00:00:00Z")
        #expect(usage["resetsAvailable"] is NSNull)
        let window = try #require((usage["windows"] as? [[String: Any]])?.first)
        #expect(window.keys.sorted() == ["label", "resetsAt", "usedPercent"])
        #expect(window["resetsAt"] as? String == "2026-09-26T19:39:59Z")
        #expect((window["usedPercent"] as? NSNumber)?.doubleValue == 12)
        let xa = try #require(((root["codex"] as? [String: Any])?["logins"] as? [[String: Any]])?.first)
        #expect(xa["usage"] is NSNull && xa["usageError"] as? String == "Usage could not be loaded.")
    }

    @Test("Status reports which CLIs are installed so the UI can hide the others")
    func statusReportsInstalledCLIs() async throws {
        let root = try document(await loginStatus(claude: .init(), codex: .init(), includeUsage: false,
                                                  installed: .init(claude: true, codex: false), monitors: noMonitors))
        #expect((root["claude"] as? [String: Any])?["installed"] as? Bool == true)
        #expect((root["codex"] as? [String: Any])?["installed"] as? Bool == false)
    }

    @Test("Unavailable and unreadable lists stay empty and unavailable")
    func unavailableLists() async throws {
        let unavailable = try document(await loginStatus(claude: .init(), codex: .init(), includeUsage: true, monitors: noMonitors))
        for provider in ["claude", "codex"] {
            let value = try #require(unavailable[provider] as? [String: Any])
            #expect(value["available"] as? Bool == false)
            #expect((value["logins"] as? [Any])?.isEmpty == true)
        }
        let backend = StatusClaudeBackend()
        backend.unreadable = true
        let fixture = try StatusCodexFixture(saved: [:])
        defer { fixture.cleanup() }
        fixture.store.data = Data("broken".utf8)
        let unreadable = try document(await loginStatus(claude: .init(makeBackend: { backend }),
            codex: .init(makeSystem: { fixture.system }), includeUsage: false, monitors: noMonitors))
        for provider in ["claude", "codex"] {
            let value = try #require(unreadable[provider] as? [String: Any])
            #expect(value["available"] as? Bool == false)
            #expect((value["logins"] as? [Any])?.isEmpty == true)
        }
    }

    @Test("Add reports adapter messages and stable exit codes; rejects invalid aliases before sign-in")
    func addContract() throws {
        let backend = StatusClaudeBackend()
        backend.current = try snapshot("a")
        var signIns = 0
        let claude = ClaudeLoginAppAdapter(makeBackend: { backend }, services: .init(
            liveSnapshot: { try self.snapshot("a") }, renew: { $0 }, fetch: { _ in Data() },
            signIn: { _ in signIns += 1 }))
        let lines = StatusLines()
        func run(_ arguments: [String], claude: ClaudeLoginAppAdapter = .init(), codex: CodexLoginAppAdapter = .init()) -> Int32 {
            lines.clear()
            return runAsyncReport(arguments: arguments, claude: claude, codex: codex, output: { lines.append($0) })
        }
        #expect(run(["claude-login", "add", "work", "a@example.com"], claude: claude) == 0)
        #expect(lines.last == "Saved alias work.")
        #expect(signIns == 1)
        #expect(run(["claude-login", "add", "second"], claude: .init()) == 3)
        #expect(lines.last == "Login switching is off. Start AI Control with aic.")
        #expect(run(["codex-login", "add", "second"], codex: .init()) == 3)
        #expect(lines.last == "Login switching is off. Start AI Control with aic.")
        for provider in ["claude-login", "codex-login"] {
            #expect(run([provider, "add", "bad\n"], claude: claude) == 2)
            #expect(lines.last?.hasPrefix("Usage:") == true)
        }
        let fixture = try StatusCodexFixture(saved: [:])
        defer { fixture.cleanup() }
        let codex = CodexLoginAppAdapter(makeSystem: { fixture.system }, services: .init(
            fetch: { _ in Data() }, signIn: { fixture.live = self.auth() }, renew: { $0 }))
        #expect(run(["codex-login", "add", "home"], codex: codex) == 0)
        #expect(lines.last == "Saved Codex login home (a@example.com).")
        #expect(signIns == 1)
    }
}
