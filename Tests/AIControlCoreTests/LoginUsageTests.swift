import Foundation
import Testing
@testable import AIControlCore

struct LoginUsageTests {
    @Test("Claude usage reads the five-hour and weekly windows with their reset times")
    func claudeUsageParsesWindows() throws {
        let body = #"{"five_hour":{"utilization":17.0,"resets_at":"2026-09-26T19:39:59.569094+00:00"},"seven_day":{"utilization":16.0,"resets_at":"2026-09-28T22:59:59.569146+00:00"},"seven_day_opus":null,"extra_usage":{"is_enabled":false}}"#
        let usage = try LoginUsage.claude(Data(body.utf8), fetchedAt: Date(timeIntervalSince1970: 0))

        #expect(usage.windows == [
            .init(label: "5h", usedPercent: 17, resetsAt: Date(timeIntervalSince1970: 1_790_451_599)),
            .init(label: "Week", usedPercent: 16, resetsAt: Date(timeIntervalSince1970: 1_790_636_399))
        ])
        #expect(usage.resetsAvailable == nil)
    }

    @Test("Codex usage reads its windows by length and the resets available")
    func codexUsageParsesWindowsAndResets() throws {
        let body = #"{"plan_type":"pro","rate_limit":{"allowed":true,"primary_window":{"used_percent":1,"limit_window_seconds":604800,"reset_after_seconds":596696,"reset_at":1791046696},"secondary_window":{"used_percent":40,"limit_window_seconds":18000,"reset_at":1790460000}},"rate_limit_reset_credits":{"available_count":2,"applicable_available_count":0}}"#
        let usage = try LoginUsage.codex(Data(body.utf8), fetchedAt: Date(timeIntervalSince1970: 0))

        #expect(usage.windows == [
            .init(label: "5h", usedPercent: 40, resetsAt: Date(timeIntervalSince1970: 1_790_460_000)),
            .init(label: "Week", usedPercent: 1, resetsAt: Date(timeIntervalSince1970: 1_791_046_696))
        ])
        #expect(usage.resetsAvailable == 2)
    }

    @Test("Usage responses without windows are refused")
    func usageRefusesEmptyResponses() {
        #expect(throws: LoginUsage.Error.self) { try LoginUsage.claude(Data(#"{"five_hour":null}"#.utf8), fetchedAt: .now) }
        #expect(throws: LoginUsage.Error.self) { try LoginUsage.codex(Data(#"{"error":"unauthorized"}"#.utf8), fetchedAt: .now) }
    }

    @Test("Claude access comes from the saved login until it is about to expire")
    func claudeAccessReadsSavedLogin() throws {
        let valid = #"{"accessToken":"a1","refreshToken":"r1","expiresAt":4102444800000}"#
        let expiring = #"{"accessToken":"a2","refreshToken":"r2","expiresAt":1000}"#
        #expect(ClaudeAccess(rawLogin: valid)?.token == "a1")
        #expect(ClaudeAccess(rawLogin: valid)?.isFresh(at: .now) == true)
        #expect(ClaudeAccess(rawLogin: expiring)?.isFresh(at: .now) == false)
        #expect(ClaudeAccess(rawLogin: #"{"accessToken":""}"#) == nil)
    }

    @Test("Usage requests carry the headers each service expects and no other secrets")
    func usageRequestsCarryExpectedHeaders() {
        let claude = UsageRequests.claude(accessToken: "tok")
        #expect(claude.url?.absoluteString == "https://api.anthropic.com/api/oauth/usage")
        #expect(claude.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        #expect(claude.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")

        let codex = UsageRequests.codex(accessToken: "tok", accountID: "acct")
        #expect(codex.url?.absoluteString == "https://chatgpt.com/backend-api/wham/usage")
        #expect(codex.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        #expect(codex.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "acct")
    }
}

struct ClaudeIsolatedRenewalTests {
    private func snapshot(access: String, refresh: String) throws -> ClaudeLoginSnapshot {
        try ClaudeLoginSnapshot.capture(
            secureRoot: #"{"claudeAiOauth":{"accessToken":"\#(access)","refreshToken":"\#(refresh)","expiresAt":1000}}"#,
            configurationRoot: #"{"oauthAccount":{"accountUuid":"account-a","emailAddress":"a@example.com"}}"#
        )
    }

    @Test("Renewal lets Claude refresh in a throwaway directory and returns the rotated login")
    func renewalReturnsRotatedLogin() throws {
        let items = IsolatedItems()
        var seen: (arguments: [String], environment: [String: String], configuration: String?)?
        let renewal = ClaudeIsolatedRenewal(
            claudeExecutable: "/fake/claude", keychainAccount: "me", item: { service, _ in items.item(service) },
            run: { _, arguments, environment, directory in
                seen = (arguments, environment, try? String(contentsOfFile: directory + "/.claude.json", encoding: .utf8))
                #expect(privateThrowaway(directory))
                let service = items.services.first!
                #expect(String(decoding: items.data[service] ?? Data(), as: UTF8.self).contains(#""expiresAt":0"#))
                items.data[service] = Data(#"{"claudeAiOauth":{"accessToken":"a2","refreshToken":"r2","expiresAt":4102444800000}}"#.utf8)
                return 0
            }
        )

        let renewed = try renewal.renew(try snapshot(access: "a1", refresh: "r1"))

        #expect(renewed.claudeAiOauth == .value(#"{"accessToken":"a2","refreshToken":"r2","expiresAt":4102444800000}"#))
        #expect(renewed.identity == (try snapshot(access: "a1", refresh: "r1")).identity)
        #expect(seen?.arguments == ["-p", "Reply with exactly: OK", "--model", "haiku"])
        #expect(seen?.environment["CLAUDE_CONFIG_DIR"] != nil)
        #expect(seen?.environment["ANTHROPIC_API_KEY"] == nil && seen?.environment["CLAUDE_CODE_OAUTH_TOKEN"] == nil)
        #expect(seen?.configuration?.contains("a@example.com") == true)
        #expect(items.services.allSatisfy { $0.hasPrefix("Claude Code-credentials-") && $0.count == 32 })
        #expect(items.data.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: seen?.environment["CLAUDE_CONFIG_DIR"] ?? "/"))
    }

    @Test("A failed renewal that rotated nothing refuses and still cleans up")
    func failedRenewalCleansUp() throws {
        let items = IsolatedItems()
        let renewal = ClaudeIsolatedRenewal(
            claudeExecutable: "/fake/claude", keychainAccount: "me", item: { service, _ in items.item(service) }, run: { _, _, _, _ in 1 }
        )
        #expect(throws: ClaudeIsolatedRenewal.Error.claudeFailed) { try renewal.renew(try snapshot(access: "a1", refresh: "r1")) }
        #expect(items.data.isEmpty)
    }

    @Test("A rotated login is kept even when Claude exits with an error afterwards")
    func rotatedLoginSurvivesClaudeFailure() throws {
        let items = IsolatedItems()
        let renewal = ClaudeIsolatedRenewal(
            claudeExecutable: "/fake/claude", keychainAccount: "me", item: { service, _ in items.item(service) }, run: { _, _, _, _ in
                items.data[items.services.first!] = Data(#"{"claudeAiOauth":{"accessToken":"a2","refreshToken":"r2","expiresAt":4102444800000}}"#.utf8)
                return 1
            }
        )
        #expect(try renewal.renew(try snapshot(access: "a1", refresh: "r1")).claudeAiOauth
            == .value(#"{"accessToken":"a2","refreshToken":"r2","expiresAt":4102444800000}"#))
    }
}

private final class IsolatedItems {
    var data: [String: Data] = [:]
    private(set) var services: [String] = []

    func item(_ service: String) -> any IsolatedCredentialItem {
        services.append(service)
        return Item(owner: self, service: service)
    }

    private struct Item: IsolatedCredentialItem {
        let owner: IsolatedItems
        let service: String
        func read() throws -> Data {
            guard let data = owner.data[service] else { throw IsolatedKeychainError.missing }
            return data
        }
        func create(data: Data) throws { owner.data[service] = data }
        func delete() throws { owner.data[service] = nil }
    }
}

struct ClaudeAppServicesTests {
    private static let fresh = "4102444800000"
    private func login(_ account: String, access: String, expiresAt: String = fresh) throws -> ClaudeLoginSnapshot {
        try ClaudeLoginSnapshot.capture(
            secureRoot: #"{"claudeAiOauth":{"accessToken":"\#(access)","refreshToken":"r-\#(access)","expiresAt":\#(expiresAt)}}"#,
            configurationRoot: #"{"oauthAccount":{"accountUuid":"\#(account)"}}"#
        )
    }

    private let usageBody = Data(#"{"five_hour":{"utilization":5.0,"resets_at":null},"seven_day":{"utilization":9.0,"resets_at":null}}"#.utf8)

    @Test("Usage uses the live login for the live account, saved logins for the rest, and renews expired ones")
    func usagePicksLoginPerAccount() async throws {
        let backend = UsageBackend(state: .init(snapshots: [
            "live": try login("a", access: "saved-live"),
            "fresh": try login("b", access: "saved-fresh"),
            "stale": try login("c", access: "saved-stale", expiresAt: "1000")
        ], activeAlias: "live"))
        let renewed = try login("c", access: "renewed-stale")
        var tokens: [String] = []
        var renewals = 0
        let adapter = ClaudeLoginAppAdapter(makeBackend: { backend }, services: .init(
            liveSnapshot: { try self.login("a", access: "live-now") },
            renew: { _ in renewals += 1; return renewed },
            fetch: { request in
                tokens.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
                return self.usageBody
            },
            signIn: { _ in }
        ))

        let usage = await adapter.usage()

        #expect(Set(tokens) == ["Bearer live-now", "Bearer saved-fresh", "Bearer renewed-stale"])
        #expect(renewals == 1)
        #expect(backend.state.snapshots["stale"] == renewed)
        #expect(backend.state.snapshots["live"] == (try login("a", access: "saved-live")))
        guard case .usage(let fresh) = usage["fresh"] else { Issue.record("no usage for fresh"); return }
        #expect(fresh.windows.map(\.usedPercent) == [5, 9])
    }

    @Test("A failed renewal or fetch reports that account's usage as unavailable")
    func usageFailuresStayPerAccount() async throws {
        let backend = UsageBackend(state: .init(snapshots: [
            "stale": try login("c", access: "saved-stale", expiresAt: "1000"), "fresh": try login("b", access: "saved-fresh")
        ]))
        let adapter = ClaudeLoginAppAdapter(makeBackend: { backend }, services: .init(
            liveSnapshot: { throw FixtureFailure() }, renew: { _ in throw FixtureFailure() },
            fetch: { _ in throw FixtureFailure() }, signIn: { _ in }
        ))
        let usage = await adapter.usage()
        #expect(usage["stale"] == .unavailable("Use this account once to refresh its usage."))
        #expect(usage["fresh"] == .unavailable("Usage could not be loaded."))
    }

    @Test("Adding an account re-saves the live login, signs in, then saves the new one")
    func addingSignsInBetweenSaves() async throws {
        let first = try login("a", access: "a1")
        let backend = UsageBackend(state: .init(snapshots: ["work": try login("a", access: "a0")], activeAlias: "work"))
        backend.current = first
        var events: [String] = []
        let adapter = ClaudeLoginAppAdapter(makeBackend: { backend }, services: .init(
            liveSnapshot: { first }, renew: { $0 }, fetch: { _ in Data() },
            signIn: { email in
                events.append("sign-in \(email ?? "-")")
                backend.current = try self.login("b", access: "b1")
            }
        ))

        #expect(await adapter.add(alias: "home", email: "b@example.com") == .done("Saved alias home."))
        #expect(events == ["sign-in b@example.com"])
        #expect(backend.state.snapshots["work"] == first)
        #expect(backend.state.snapshots["home"]?.identity == (try login("b", access: "b1")).identity)
        #expect(await adapter.rename(alias: "home", to: "house") == .done("Renamed alias home to house."))
        #expect(await adapter.rename(alias: "house", to: "work") == .blocked("Blocked: alias work is already saved."))
    }

    @Test("A cancelled sign-in saves nothing new")
    func cancelledSignInSavesNothing() async throws {
        let backend = UsageBackend(state: .init(snapshots: ["work": try login("a", access: "a0")], activeAlias: "work"))
        backend.current = try login("a", access: "a0")
        let adapter = ClaudeLoginAppAdapter(makeBackend: { backend }, services: .init(
            liveSnapshot: { try self.login("a", access: "a0") }, renew: { $0 }, fetch: { _ in Data() },
            signIn: { _ in throw FixtureFailure() }
        ))
        #expect(await adapter.add(alias: "home", email: nil) == .blocked("Sign-in did not finish; nothing was saved."))
        #expect(backend.state.snapshots.keys.sorted() == ["work"])
    }
}

private struct FixtureFailure: Error {}

private final class UsageBackend: ClaudeLoginBackend {
    var state: ClaudeLoginState
    var current: ClaudeLoginSnapshot?
    init(state: ClaudeLoginState) { self.state = state }
    func loadState() throws -> ClaudeLoginState { state }
    func currentSnapshot() throws -> ClaudeLoginSnapshot {
        guard let current else { throw FixtureFailure() }
        return current
    }
    func saveState(_ state: ClaudeLoginState) throws { self.state = state }
}

struct CodexAppServicesTests {
    private func auth(_ account: String, _ email: String, access: String, expires: TimeInterval = 4_102_444_800) throws -> Data {
        func segment(_ object: [String: Any]) throws -> String {
            try JSONSerialization.data(withJSONObject: object).base64EncodedString().replacingOccurrences(of: "=", with: "")
                .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        }
        return try JSONSerialization.data(withJSONObject: [
            "auth_mode": "chatgpt",
            "tokens": ["id_token": "h.\(try segment(["email": email])).s", "access_token": "h.\(try segment(["exp": expires, "n": access])).s",
                       "refresh_token": "r", "account_id": account]
        ], options: [.sortedKeys])
    }

    private let usageBody = Data(#"{"rate_limit":{"primary_window":{"used_percent":3,"limit_window_seconds":604800,"reset_at":1791046696}},"rate_limit_reset_credits":{"available_count":2}}"#.utf8)

    @Test("Codex usage uses auth.json for the live account and saved logins for the rest, skipping expired ones")
    func codexUsagePicksLoginPerAccount() async throws {
        let home = try auth("acct-b", "b@example.com", access: "saved-home")
        let expired = try auth("acct-c", "c@example.com", access: "old", expires: 1000)
        let fixture = try CodexServicesFixture(saved: ["work": try auth("acct-a", "a@example.com", access: "saved-work"), "home": home, "old": expired])
        defer { fixture.cleanup() }
        let liveHome = try auth("acct-b", "b@example.com", access: "live-home")
        fixture.live = liveHome
        var accounts: [String] = []
        let adapter = CodexLoginAppAdapter(makeSystem: { fixture.system }, services: .init(
            fetch: { request in accounts.append(request.value(forHTTPHeaderField: "ChatGPT-Account-Id") ?? ""); return self.usageBody },
            signIn: {}, renew: { _ in throw FixtureFailure() }
        ))

        let usage = await adapter.usage()

        #expect(accounts.sorted() == ["acct-a", "acct-b"])
        #expect(usage["old"] == .unavailable("Use this account once to refresh its usage."))
        guard case .usage(let work) = usage["work"] else { Issue.record("no usage for work"); return }
        #expect(work.resetsAvailable == 2 && work.windows.first?.usedPercent == 3)
    }

    @Test("An expired saved Codex login is renewed, saved again, and then used for usage")
    func expiredCodexLoginIsRenewed() async throws {
        let expired = try auth("acct-c", "c@example.com", access: "old", expires: 1000)
        let renewed = try auth("acct-c", "c@example.com", access: "new")
        let fixture = try CodexServicesFixture(saved: ["old": expired])
        defer { fixture.cleanup() }
        var renewedLogins: [Data] = []
        var tokens: [String] = []
        let adapter = CodexLoginAppAdapter(makeSystem: { fixture.system }, services: .init(
            fetch: { request in tokens.append(request.value(forHTTPHeaderField: "Authorization") ?? ""); return self.usageBody },
            signIn: {}, renew: { renewedLogins.append($0); return renewed }
        ))

        let usage = await adapter.usage()

        #expect(renewedLogins == [expired])
        #expect(try CodexLoginManager(system: fixture.system).savedLogins()["old"] == renewed)
        #expect(tokens.count == 1 && tokens[0].contains("."))
        guard case .usage = usage["old"] else { Issue.record("renewed login was not used"); return }
    }

    @Test("A renewal that returns another account is not saved")
    func renewalOfAnotherAccountIsRefused() async throws {
        let expired = try auth("acct-c", "c@example.com", access: "old", expires: 1000)
        let fixture = try CodexServicesFixture(saved: ["old": expired])
        defer { fixture.cleanup() }
        let stranger = try auth("acct-x", "x@example.com", access: "x")
        let adapter = CodexLoginAppAdapter(makeSystem: { fixture.system }, services: .init(
            fetch: { _ in self.usageBody }, signIn: {}, renew: { _ in stranger }
        ))
        #expect(await adapter.usage()["old"] == .unavailable("Use this account once to refresh its usage."))
        #expect(try CodexLoginManager(system: fixture.system).savedLogins()["old"] == expired)
    }

    @Test("Adding a Codex account clears auth.json only around sign-in and restores the previous login if it fails")
    func addingCodexRestoresOnFailure() async throws {
        let work = try auth("acct-a", "a@example.com", access: "w")
        let fixture = try CodexServicesFixture(saved: ["work": work])
        defer { fixture.cleanup() }
        fixture.live = work
        var sawCleared = false
        let failing = CodexLoginAppAdapter(makeSystem: { fixture.system }, services: .init(
            fetch: { _ in Data() }, signIn: { sawCleared = fixture.live == nil; throw FixtureFailure() }, renew: { $0 }
        ))
        #expect(await failing.add(alias: "home") == .blocked("Sign-in did not finish; your previous Codex login is back."))
        #expect(sawCleared)
        #expect(fixture.live == work)

        let home = try auth("acct-b", "b@example.com", access: "h")
        let working = CodexLoginAppAdapter(makeSystem: { fixture.system }, services: .init(
            fetch: { _ in Data() }, signIn: { fixture.live = home }, renew: { $0 }
        ))
        #expect(await working.add(alias: "home") == .done("Saved Codex login home (b@example.com)."))
        #expect(await working.rename(alias: "home", to: "house") == .done("Renamed Codex login home to house."))
    }
}

private final class CodexServicesFixture: @unchecked Sendable {
    let directory: URL
    private let store = CodexServicesMemory()

    init(saved: [String: Data]) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("codex-services-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        store.data = try JSONEncoder().encode(CodexLoginState(logins: saved))
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
            try? FileManager.default.removeItem(atPath: path)
            if let newValue { FileManager.default.createFile(atPath: path, contents: newValue) }
        }
    }

    func cleanup() { try? FileManager.default.removeItem(at: directory) }
}

private final class CodexServicesMemory: ClaudeLoginDataStore {
    var data: Data?
    func read() throws -> Data {
        guard let data else { throw IsolatedKeychainError.missing }
        return data
    }
    func create(data: Data) throws { self.data = data }
    func update(data: Data) throws { self.data = data }
}

struct CodexIsolatedRenewalTests {
    @Test("Renewal runs Codex with a throwaway CODEX_HOME holding an expired copy and returns the refreshed login")
    func renewalUsesThrowawayHome() throws {
        let login = Data(#"{"auth_mode":"chatgpt","last_refresh":"2026-09-26T00:00:00Z","tokens":{"id_token":"h.e30.s","access_token":"h.e30.s","refresh_token":"r1","account_id":"acct-a"}}"#.utf8)
        var seen: (arguments: [String], home: String?, copy: String?)?
        let renewal = CodexIsolatedRenewal(codexExecutable: "/fake/codex", run: { _, arguments, environment, _ in
            let home = environment["CODEX_HOME"] ?? ""
            #expect(privateThrowaway(home))
            seen = (arguments, home, try? String(contentsOfFile: home + "/auth.json", encoding: .utf8))
            try Data(#"{"auth_mode":"chatgpt","last_refresh":"2026-09-27T00:00:00Z","tokens":{"id_token":"h.e30.s","access_token":"new","refresh_token":"r2","account_id":"acct-a"}}"#.utf8)
                .write(to: URL(fileURLWithPath: home + "/auth.json"))
            return 0
        })

        let renewed = try renewal.renew(login)

        #expect(String(decoding: renewed, as: UTF8.self).contains(#""refresh_token":"r2""#))
        #expect(seen?.arguments.first == "exec")
        #expect(seen?.copy?.contains(#""refresh_token":"r1""#) == true)
        #expect(seen?.copy?.contains(#""last_refresh":"2000-01-01T00:00:00Z""#) == true)
        #expect(!FileManager.default.fileExists(atPath: seen?.home ?? "/"))
    }

    @Test("Renewal refuses when Codex changed nothing or switched accounts")
    func renewalRefusesUnchangedOrForeignLogins() throws {
        let login = Data(#"{"auth_mode":"chatgpt","tokens":{"id_token":"h.e30.s","access_token":"a","refresh_token":"r1","account_id":"acct-a"}}"#.utf8)
        let unchanged = CodexIsolatedRenewal(codexExecutable: "/fake/codex", run: { _, _, _, _ in 0 })
        #expect(throws: CodexIsolatedRenewal.Error.codexFailed) { try unchanged.renew(login) }
        let foreign = CodexIsolatedRenewal(codexExecutable: "/fake/codex", run: { _, _, environment, _ in
            try Data(#"{"auth_mode":"chatgpt","tokens":{"id_token":"h.e30.s","access_token":"b","refresh_token":"r9","account_id":"acct-z"}}"#.utf8)
                .write(to: URL(fileURLWithPath: (environment["CODEX_HOME"] ?? "") + "/auth.json"))
            return 0
        })
        #expect(throws: CodexIsolatedRenewal.Error.accountChanged) { try foreign.renew(login) }
    }
}

/// A renewal directory must have an unpredictable name and be reachable only by its owner, because it holds
/// a copy of a saved login.
private func privateThrowaway(_ directory: String) -> Bool {
    let name = (directory as NSString).lastPathComponent
    let mode = (try? FileManager.default.attributesOfItem(atPath: directory))?[.posixPermissions] as? Int
    return name.hasPrefix("ai-control-renewal.") && name.count > "ai-control-renewal.".count + 5 && mode == 0o700
}

struct PrivateTemporaryDirectoryTests {
    @Test("Each renewal directory is new, owner-only and removed by its owner")
    func uniqueOwnerOnly() throws {
        let first = try PrivateTemporaryDirectory.create(prefix: "ai-control-renewal")
        let second = try PrivateTemporaryDirectory.create(prefix: "ai-control-renewal")
        defer {
            try? FileManager.default.removeItem(atPath: first)
            try? FileManager.default.removeItem(atPath: second)
        }
        #expect(first != second)
        #expect(privateThrowaway(first) && privateThrowaway(second))
    }
}
