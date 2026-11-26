import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Whether a Codex switch also writes Gentle Shell's own Codex login.
enum GentleShellSync: Equatable {
    case off
    case agentDirectoryMissing
    case on(agentDirectory: String)

    static func configured(_ settings: AIControlSettings, home: String, environment: [String: String]) -> Self {
        guard settings.gentleShell.sync else { return .off }
        guard let directory = GentleShellAgentDirectory.resolve(
            configured: settings.gentleShell.agentDirectory, home: home, environment: environment
        ) else { return .agentDirectoryMissing }
        return .on(agentDirectory: directory)
    }
}

/// What a Codex switch changed.
enum CodexSwitchOutcome: Equatable {
    case codexOnly
    case withGentleShell
    case gentleShellAgentDirectoryMissing
}

/// Finds Gentle Shell's agent folder (pi's `PI_CODING_AGENT_DIR`) without assuming one install layout.
enum GentleShellAgentDirectory {
    static func resolve(configured: String?, home: String, environment: [String: String]) -> String? {
        let named = { (key: String) in environment[key].flatMap { $0.isEmpty ? nil : $0 } }
        func directory(_ value: String) -> String? {
            let path = value == "~" ? home : value.hasPrefix("~/") ? home + value.dropFirst() : value
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue ? path : nil
        }
        // A folder the user or Gentle Shell named is never replaced by a guess.
        if let explicit = configured ?? named("GENTLE_PI_AGENT_HOME") ?? named("PI_CODING_AGENT_DIR") {
            return directory(explicit)
        }
        let data = named("XDG_DATA_HOME") ?? home + "/.local/share"
        if let manifest = FileManager.default.contents(atPath: data + "/gentle-shell/install/installation.json"),
           let agent = (try? JSONSerialization.jsonObject(with: manifest) as? [String: Any])?["Agent"] as? String,
           let path = directory(agent) {
            return path
        }
        return directory(home + "/.gentle-shell/agent")
    }
}

/// Claims of a ChatGPT access token, read offline.
enum CodexAccessToken {
    static func claims(_ token: String) -> [String: Any] {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return [:] }
        var payload = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload) else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    static func account(_ token: String) -> String? {
        (claims(token)["https://api.openai.com/auth"] as? [String: Any])?["chatgpt_account_id"] as? String
    }

    /// Expiry in epoch milliseconds, the unit Gentle Shell stores; 0 when the token does not say.
    static func expiryMilliseconds(_ token: String) -> Int64 {
        ((claims(token)["exp"] as? NSNumber)?.int64Value ?? 0) * 1000
    }
}

/// Gentle Shell's (pi-ai) `openai-codex` login, as stored in the agent folder's `auth.json`.
struct GentleShellCodexEntry: Equatable {
    let access: String
    let refresh: String
    let expires: Int64
    let accountID: String

    var json: [String: Any] {
        ["type": "oauth", "access": access, "refresh": refresh, "expires": expires, "accountId": accountID]
    }

    init?(json value: Any) {
        guard let entry = value as? [String: Any], entry["type"] as? String == "oauth",
              let access = entry["access"] as? String, let refresh = entry["refresh"] as? String, !refresh.isEmpty,
              let account = entry["accountId"] as? String ?? CodexAccessToken.account(access), !account.isEmpty
        else { return nil }
        self.access = access
        self.refresh = refresh
        expires = (entry["expires"] as? NSNumber)?.int64Value ?? 0
        accountID = account
    }

    /// A Codex CLI login in Gentle Shell's shape.
    init(codexLogin: Data) throws {
        guard let tokens = (try? JSONSerialization.jsonObject(with: codexLogin) as? [String: Any])?["tokens"] as? [String: Any],
              let access = tokens["access_token"] as? String, let refresh = tokens["refresh_token"] as? String,
              let account = CodexAccessToken.account(access) ?? tokens["account_id"] as? String
        else { throw CodexLoginError.unsupportedAuth }
        self.access = access
        self.refresh = refresh
        expires = CodexAccessToken.expiryMilliseconds(access)
        accountID = account
    }

    /// The Codex CLI login carrying this entry's tokens; its id token, account and other keys are kept.
    func adopted(into codexLogin: Data, at now: Date) throws -> Data {
        guard var root = try? JSONSerialization.jsonObject(with: codexLogin) as? [String: Any],
              var tokens = root["tokens"] as? [String: Any] else { throw CodexLoginError.unsupportedAuth }
        tokens["access_token"] = access
        tokens["refresh_token"] = refresh
        root["tokens"] = tokens
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        root["last_refresh"] = formatter.string(from: now)
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys, .withoutEscapingSlashes])
    }
}

/// Gentle Shell's `auth.json`, held under the same lock pi takes (proper-lockfile's `<real path>.lock` folder)
/// from the first read to the last write. A lock someone else holds is never removed.
final class GentleShellAuthFile {
    private let path: String
    private let lockPath: String
    private var locked = false
    private let original: Data?
    private let root: [String: Any]

    init(agentDirectory: String, wait: TimeInterval) throws {
        guard let real = Self.realPath(agentDirectory + "/auth.json")
                ?? Self.realPath(agentDirectory).map({ $0 + "/auth.json" }) else {
            throw CodexLoginError.gentleShellUnreadable
        }
        path = real
        lockPath = real + ".lock"
        let deadline = Date().addingTimeInterval(wait)
        while mkdir(lockPath, 0o700) != 0 {
            guard errno == EEXIST else { throw CodexLoginError.gentleShellUnreadable }
            guard Date() < deadline else { throw CodexLoginError.gentleShellBusy }
            Thread.sleep(forTimeInterval: 0.05)
        }
        locked = true
        original = FileManager.default.contents(atPath: real)
        if let original {
            guard let root = try? JSONSerialization.jsonObject(with: original) as? [String: Any] else {
                rmdir(lockPath)
                locked = false
                throw CodexLoginError.gentleShellUnreadable
            }
            self.root = root
        } else {
            guard !FileManager.default.fileExists(atPath: real) else {
                rmdir(lockPath)
                locked = false
                throw CodexLoginError.gentleShellUnreadable
            }
            root = [:]
        }
    }

    deinit { release() }

    func release() {
        guard locked else { return }
        rmdir(lockPath)
        locked = false
    }

    /// The `openai-codex` login, nil when Gentle Shell has none; an entry it cannot understand is unreadable.
    func codexEntry() throws -> GentleShellCodexEntry? {
        guard let value = root["openai-codex"] else { return nil }
        guard let entry = GentleShellCodexEntry(json: value) else { throw CodexLoginError.gentleShellUnreadable }
        return entry
    }

    /// Replaces only the `openai-codex` key, in one rename, only if the file still holds what was read.
    func write(_ entry: GentleShellCodexEntry) throws {
        var updated = root
        updated["openai-codex"] = entry.json
        let data = try JSONSerialization.data(withJSONObject: updated, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes])
        try CodexAuthFile.replace(path: path, expected: original, with: data)
    }

    private static func realPath(_ path: String) -> String? {
        guard let pointer = realpath(path, nil) else { return nil }
        defer { free(pointer) }
        return String(cString: pointer)
    }
}
