import Foundation
import Testing
@testable import AIControlCore

private final class UsageTokens: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String: String] = [:]
    func record(_ account: String, _ token: String) { lock.withLock { stored[account] = token } }
    var tokens: [String: String] { lock.withLock { stored } }
}

/// Gentle Shell keeps its own Codex login; with sync on, a Codex switch writes it too. Only fake files are used.
struct GentleShellSyncTests {
    private func json(_ data: Data?) throws -> [String: Any] {
        let bytes = try #require(data)
        return try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    }

    private func gentleShellFile(_ entries: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: entries, options: [.sortedKeys, .prettyPrinted])
    }

    private func entry(account: String, refresh: String, expiry: Int) throws -> [String: Any] {
        ["type": "oauth", "access": try fakeAccessToken(account: account, expiry: expiry), "refresh": refresh,
         "expires": expiry * 1000, "accountId": account]
    }

    /// Saves `work` (acct-a) and `home` (acct-b) and leaves `home` live.
    private func twoSavedLogins(_ fixture: CodexFixture) throws -> (work: Data, home: Data) {
        let work = try codexAuth(account: "acct-a", email: "a@example.com", refresh: "ra1", accessExpiry: 1_800_001_000)
        let home = try codexAuth(account: "acct-b", email: "b@example.com", refresh: "rb1", accessExpiry: 1_800_001_000)
        fixture.live = work
        #expect(fixture.run("save", "work") == 0)
        fixture.live = home
        #expect(fixture.run("save", "home") == 0)
        return (work, home)
    }

    @Test("With sync on, a switch writes Gentle Shell's openai-codex entry and keeps its other logins")
    func switchWritesGentleShellEntry() throws {
        let fixture = try CodexFixture()
        defer { fixture.cleanup() }
        let saved = try twoSavedLogins(fixture)
        let other: [String: Any] = ["type": "api_key", "key": "fake-key"]
        fixture.gentleShellAuth = try gentleShellFile([
            "anthropic": other, "openai-codex": try entry(account: "acct-b", refresh: "rb1", expiry: 1_800_001_000)
        ])
        fixture.gentleShell = .on(agentDirectory: fixture.agentDirectory)

        #expect(fixture.run("use", "work") == 0)

        #expect(fixture.live == saved.work)
        let written = try json(fixture.gentleShellAuth)
        #expect(written["anthropic"] as? NSDictionary == other as NSDictionary)
        #expect(written["openai-codex"] as? NSDictionary == [
            "type": "oauth", "access": try fakeAccessToken(account: "acct-a", expiry: 1_800_001_000),
            "refresh": "ra1", "expires": 1_800_001_000_000, "accountId": "acct-a"
        ] as NSDictionary)
        #expect(fixture.gentleShellMode == 0o600)
        #expect(!FileManager.default.fileExists(atPath: fixture.gentleShellAuthPath + ".lock"))
        #expect(fixture.messages.last == "Switched Codex and Gentle Shell to work.")
    }

    @Test("With sync on, using the live account still moves Gentle Shell to it, and a missing file is created")
    func liveAccountAndMissingFile() throws {
        let fixture = try CodexFixture()
        defer { fixture.cleanup() }
        _ = try twoSavedLogins(fixture)
        try FileManager.default.createDirectory(atPath: fixture.agentDirectory, withIntermediateDirectories: true)
        fixture.gentleShell = .on(agentDirectory: fixture.agentDirectory)

        #expect(fixture.run("use", "home") == 0)

        let written = try json(fixture.gentleShellAuth)
        #expect(Array(written.keys) == ["openai-codex"])
        #expect((written["openai-codex"] as? [String: Any])?["refresh"] as? String == "rb1")
        #expect(fixture.gentleShellMode == 0o600)
        #expect(fixture.messages.last == "Switched Codex and Gentle Shell to home.")
    }

    @Test("A newer Gentle Shell token is saved for its account before the switch; an older one is not")
    func checkpointAdoptsNewerGentleShellToken() throws {
        let fixture = try CodexFixture()
        defer { fixture.cleanup() }
        let saved = try twoSavedLogins(fixture)
        let newer = try entry(account: "acct-a", refresh: "ra2", expiry: 1_800_009_000)
        fixture.gentleShellAuth = try gentleShellFile(["openai-codex": newer])
        fixture.gentleShell = .on(agentDirectory: fixture.agentDirectory)

        #expect(fixture.run("use", "work") == 0)

        let live = try json(fixture.live)
        let tokens = try #require(live["tokens"] as? [String: Any])
        #expect(tokens["refresh_token"] as? String == "ra2")
        #expect(tokens["access_token"] as? String == newer["access"] as? String)
        #expect(tokens["account_id"] as? String == "acct-a")
        #expect(tokens["id_token"] as? String == (try json(saved.work)["tokens"] as? [String: Any])?["id_token"] as? String)
        #expect(live["last_refresh"] as? String == "2027-01-15T08:00:00Z")
        #expect((try json(fixture.gentleShellAuth)["openai-codex"] as? [String: Any])?["refresh"] as? String == "ra2")

        // An older Gentle Shell copy of `home` must not replace the saved one.
        fixture.gentleShellAuth = try gentleShellFile([
            "openai-codex": try entry(account: "acct-b", refresh: "rb0", expiry: 1_800_000_500)
        ])
        #expect(fixture.run("use", "home") == 0)
        #expect(fixture.live == saved.home)
        #expect((try json(fixture.gentleShellAuth)["openai-codex"] as? [String: Any])?["refresh"] as? String == "rb1")
    }

    @Test("Gentle Shell signed in to an unsaved account blocks the switch and changes neither file")
    func unsavedGentleShellAccountBlocks() throws {
        let fixture = try CodexFixture()
        defer { fixture.cleanup() }
        let saved = try twoSavedLogins(fixture)
        let stranger = try gentleShellFile(["openai-codex": try entry(account: "acct-z", refresh: "rz", expiry: 1_800_001_000)])
        fixture.gentleShellAuth = stranger
        fixture.gentleShell = .on(agentDirectory: fixture.agentDirectory)

        #expect(fixture.run("use", "work") == 3)

        #expect(fixture.live == saved.home)
        #expect(fixture.gentleShellAuth == stranger)
        #expect(fixture.messages.last ==
            "Blocked: Gentle Shell is signed in to a Codex account AI Control has not saved; nothing was changed. " +
            "Save that account in AI Control or turn off gentle-shell-sync.")
    }

    @Test("A busy or unreadable Gentle Shell login blocks before anything is written")
    func busyOrUnreadableBlocks() throws {
        let fixture = try CodexFixture()
        defer { fixture.cleanup() }
        let saved = try twoSavedLogins(fixture)
        let current = try gentleShellFile(["openai-codex": try entry(account: "acct-b", refresh: "rb1", expiry: 1_800_001_000)])
        fixture.gentleShellAuth = current
        fixture.gentleShell = .on(agentDirectory: fixture.agentDirectory)
        let lock = fixture.gentleShellAuthPath + ".lock"
        try FileManager.default.createDirectory(atPath: lock, withIntermediateDirectories: false)

        #expect(fixture.run("use", "work") == 3)
        #expect(fixture.live == saved.home)
        #expect(fixture.gentleShellAuth == current)
        #expect(FileManager.default.fileExists(atPath: lock))

        try FileManager.default.removeItem(atPath: lock)
        let broken = Data("not json".utf8)
        fixture.gentleShellAuth = broken
        #expect(fixture.run("use", "work") == 3)
        #expect(fixture.live == saved.home)
        #expect(fixture.gentleShellAuth == broken)
        #expect(Array(fixture.messages.suffix(2)) == [
            "Blocked: Gentle Shell is updating its login; nothing was changed. Try again.",
            "Blocked: Gentle Shell's auth.json could not be read; nothing was changed."
        ])
    }

    @Test("A target Gentle Shell cannot use is refused before either file is written")
    func unusableTargetRefusedBeforeWriting() throws {
        let fixture = try CodexFixture()
        defer { fixture.cleanup() }
        var root = try json(try codexAuth(account: "acct-a", email: "a@example.com", refresh: "ra1"))
        var tokens = try #require(root["tokens"] as? [String: Any])
        tokens.removeValue(forKey: "access_token")
        root["tokens"] = tokens
        fixture.live = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        #expect(fixture.run("save", "work") == 0)
        let home = try codexAuth(account: "acct-b", email: "b@example.com", refresh: "rb1", accessExpiry: 1_800_001_000)
        fixture.live = home
        #expect(fixture.run("save", "home") == 0)
        let current = try gentleShellFile(["openai-codex": try entry(account: "acct-b", refresh: "rb1", expiry: 1_800_001_000)])
        fixture.gentleShellAuth = current
        fixture.gentleShell = .on(agentDirectory: fixture.agentDirectory)

        #expect(fixture.run("use", "work") == 3)

        #expect(fixture.live == home)
        #expect(fixture.gentleShellAuth == current)
        #expect(fixture.messages.last == "Blocked: only ChatGPT sign-in Codex logins can be saved or switched.")
    }

    @Test("When the previous login cannot be put back after a failed sign-in, the message says so")
    func failedRestoreIsReported() async throws {
        let fixture = try CodexFixture()
        defer { fixture.cleanup() }
        fixture.live = try codexAuth(account: "acct-a", email: "a@example.com", refresh: "ra1", accessExpiry: 1_800_001_000)
        #expect(fixture.run("save", "work") == 0)
        fixture.gentleShellAuth = try gentleShellFile([
            "openai-codex": try entry(account: "acct-z", refresh: "rz", expiry: 1_800_001_000)
        ])
        fixture.gentleShell = .on(agentDirectory: fixture.agentDirectory)
        struct SignInFailed: Error {}
        let adapter = CodexLoginAppAdapter(makeSystem: { fixture.system }, services: .init(
            fetch: { _ in Data() }, signIn: { throw SignInFailed() }, renew: { $0 }
        ))

        #expect(await adapter.add(alias: "home") == .blocked(
            "Sign-in did not finish, and your previous Codex login could not be put back: it is still saved as work. " +
            "Blocked: Gentle Shell is signed in to a Codex account AI Control has not saved; nothing was changed. " +
            "Save that account in AI Control or turn off gentle-shell-sync."
        ))
        #expect(fixture.live == nil)
    }

    /// Usage of every saved login with sync on, returning the access token each request carried, by account.
    private func usageTokens(_ fixture: CodexFixture) async -> [String: String] {
        let seen = UsageTokens()
        let adapter = CodexLoginAppAdapter(makeSystem: { fixture.system }, services: .init(
            fetch: { request in
                seen.record(request.value(forHTTPHeaderField: "ChatGPT-Account-Id") ?? "",
                            request.value(forHTTPHeaderField: "Authorization") ?? "")
                return Data("{}".utf8)
            },
            signIn: {}, renew: { $0 }, now: { fixture.now }
        ))
        _ = await adapter.usage()
        return seen.tokens
    }

    private func savedRefresh(_ fixture: CodexFixture, _ alias: String) throws -> String? {
        let saved = try #require(try CodexLoginManager(system: fixture.system).savedLogins()[alias])
        return (try json(saved)["tokens"] as? [String: Any])?["refresh_token"] as? String
    }

    @Test("With sync on, usage of the live account uses Gentle Shell's newer login and saves it")
    func usageAdoptsNewerGentleShellLogin() async throws {
        let fixture = try CodexFixture()
        defer { fixture.cleanup() }
        _ = try twoSavedLogins(fixture)
        let newer = try entry(account: "acct-b", refresh: "rb2", expiry: 1_800_009_000)
        let current = try gentleShellFile(["openai-codex": newer])
        fixture.gentleShellAuth = current
        fixture.gentleShell = .on(agentDirectory: fixture.agentDirectory)

        let tokens = await usageTokens(fixture)

        #expect(tokens["acct-b"] == "Bearer " + (newer["access"] as? String ?? ""))
        let live = try #require(try json(fixture.live)["tokens"] as? [String: Any])
        #expect(live["refresh_token"] as? String == "rb2" && live["account_id"] as? String == "acct-b")
        #expect(try savedRefresh(fixture, "home") == "rb2")
        #expect(fixture.mode == 0o600)
        #expect(fixture.gentleShellAuth == current)
        #expect(!FileManager.default.fileExists(atPath: fixture.gentleShellAuthPath + ".lock"))
    }

    @Test("Usage keeps auth.json when sync is off, Gentle Shell is older, another account, or busy")
    func usageKeepsLiveLoginOtherwise() async throws {
        let fixture = try CodexFixture()
        defer { fixture.cleanup() }
        let saved = try twoSavedLogins(fixture)
        let liveAccess = "Bearer " + ((try json(saved.home)["tokens"] as? [String: Any])?["access_token"] as? String ?? "")
        let cases: [(GentleShellSync, [String: Any], Bool)] = [
            (.off, try entry(account: "acct-b", refresh: "rb2", expiry: 1_800_009_000), false),
            (.on(agentDirectory: fixture.agentDirectory), try entry(account: "acct-b", refresh: "rb0", expiry: 1_800_000_500), false),
            (.on(agentDirectory: fixture.agentDirectory), try entry(account: "acct-a", refresh: "ra2", expiry: 1_800_009_000), false),
            (.on(agentDirectory: fixture.agentDirectory), try entry(account: "acct-b", refresh: "rb2", expiry: 1_800_009_000), true)
        ]
        for (sync, gentleShellEntry, busy) in cases {
            let current = try gentleShellFile(["openai-codex": gentleShellEntry])
            fixture.gentleShellAuth = current
            fixture.gentleShell = sync
            let lock = fixture.gentleShellAuthPath + ".lock"
            if busy { try FileManager.default.createDirectory(atPath: lock, withIntermediateDirectories: false) }

            let tokens = await usageTokens(fixture)

            #expect(tokens["acct-b"] == liveAccess, "\(sync) busy=\(busy)")
            #expect(fixture.live == saved.home)
            #expect(try savedRefresh(fixture, "home") == "rb1")
            #expect(fixture.gentleShellAuth == current)
            #expect(FileManager.default.fileExists(atPath: lock) == busy)
            if busy { try FileManager.default.removeItem(atPath: lock) }
        }
    }

    @Test("When auth.json cannot be written, usage adoption leaves the saved copy as it was",
          .enabled(if: geteuid() != 0, "root ignores folder permissions, so the write cannot be made to fail"))
    func usageAdoptionWriteFailureChangesNothing() async throws {
        let fixture = try CodexFixture()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.directory.path)
            fixture.cleanup()
        }
        let saved = try twoSavedLogins(fixture)
        fixture.gentleShellAuth = try gentleShellFile([
            "openai-codex": try entry(account: "acct-b", refresh: "rb2", expiry: 1_800_009_000)
        ])
        fixture.gentleShell = .on(agentDirectory: fixture.agentDirectory)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: fixture.directory.path)

        #expect(throws: CodexLoginError.writeFailed) { try CodexLoginManager(system: fixture.system).adoptGentleShellLogin() }

        #expect(fixture.live == saved.home)
        #expect(try savedRefresh(fixture, "home") == "rb1")
    }

    @Test("A missing agent folder switches Codex only and says Gentle Shell was not changed")
    func missingAgentFolderSwitchesCodexOnly() throws {
        let fixture = try CodexFixture()
        defer { fixture.cleanup() }
        let saved = try twoSavedLogins(fixture)
        fixture.gentleShell = .agentDirectoryMissing

        #expect(fixture.run("use", "work") == 0)

        #expect(fixture.live == saved.work)
        #expect(fixture.gentleShellAuth == nil)
        #expect(fixture.messages.last ==
            "Switched Codex to work. Gentle Shell was not changed: its agent folder was not found.")
    }

    @Test("The agent folder comes from the setting, then the environment, then the installer, then the old layout")
    func agentDirectoryResolutionOrder() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("gs-home-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: home) }
        func make(_ path: String) throws -> String {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
            return path
        }
        func resolve(_ configured: String? = nil, _ environment: [String: String] = [:]) -> String? {
            GentleShellAgentDirectory.resolve(configured: configured, home: home, environment: environment)
        }
        #expect(resolve() == nil)

        let old = try make(home + "/.gentle-shell/agent")
        #expect(resolve() == old)

        let installed = try make(home + "/.local/share/gentle-shell/install/agent")
        let manifest = home + "/.local/share/gentle-shell/install/installation.json"
        try Data(#"{"Schema":"gentle-shell-user-install/v1","Agent":"\#(installed)"}"#.utf8).write(to: URL(fileURLWithPath: manifest))
        #expect(resolve() == installed)

        let xdg = try make(home + "/xdg")
        let xdgAgent = try make(home + "/xdg-agent")
        _ = try make(xdg + "/gentle-shell/install")
        try Data(#"{"Agent":"\#(xdgAgent)"}"#.utf8).write(to: URL(fileURLWithPath: xdg + "/gentle-shell/install/installation.json"))
        #expect(resolve(nil, ["XDG_DATA_HOME": xdg]) == xdgAgent)

        let piDir = try make(home + "/pi-agent")
        #expect(resolve(nil, ["PI_CODING_AGENT_DIR": piDir]) == piDir)
        #expect(resolve(nil, ["PI_CODING_AGENT_DIR": "~/pi-agent"]) == piDir)
        let gentleHome = try make(home + "/gentle-home")
        #expect(resolve(nil, ["PI_CODING_AGENT_DIR": piDir, "GENTLE_PI_AGENT_HOME": gentleHome]) == gentleHome)

        let configured = try make(home + "/configured")
        #expect(resolve(configured, ["GENTLE_PI_AGENT_HOME": gentleHome]) == configured)

        // A named folder that does not exist is never replaced by a guess.
        #expect(resolve(home + "/missing", ["GENTLE_PI_AGENT_HOME": gentleHome]) == nil)
        #expect(resolve(nil, ["GENTLE_PI_AGENT_HOME": home + "/missing"]) == nil)
    }
}
