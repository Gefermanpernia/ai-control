#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Usage limits the provider reports for one saved login.
struct LoginUsage: Equatable, Sendable {
    struct Window: Equatable, Sendable {
        let label: String
        let usedPercent: Double
        let resetsAt: Date?
    }

    enum Error: Swift.Error { case unreadable }

    let windows: [Window]
    /// Codex reports how many rate-limit resets the account can still use.
    let resetsAvailable: Int?
    let fetchedAt: Date

    /// Parses Claude's `/api/oauth/usage` response.
    static func claude(_ data: Data, fetchedAt: Date) throws -> Self {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Error.unreadable }
        let windows = [("five_hour", "5h"), ("seven_day", "Week")].compactMap { key, label -> Window? in
            guard let window = root[key] as? [String: Any], let used = window["utilization"] as? Double else { return nil }
            return .init(label: label, usedPercent: used, resetsAt: (window["resets_at"] as? String).flatMap(date(iso8601:)))
        }
        guard !windows.isEmpty else { throw Error.unreadable }
        return .init(windows: windows, resetsAvailable: nil, fetchedAt: fetchedAt)
    }

    /// Parses Codex's `/wham/usage` response; windows are ordered shortest first.
    static func codex(_ data: Data, fetchedAt: Date) throws -> Self {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let limits = root["rate_limit"] as? [String: Any] else { throw Error.unreadable }
        let windows = ["primary_window", "secondary_window"].compactMap { key -> (seconds: Double, window: Window)? in
            guard let window = limits[key] as? [String: Any], let used = (window["used_percent"] as? NSNumber)?.doubleValue,
                  let seconds = (window["limit_window_seconds"] as? NSNumber)?.doubleValue else { return nil }
            let reset = (window["reset_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            return (seconds, .init(label: label(seconds: seconds), usedPercent: used, resetsAt: reset))
        }.sorted { $0.seconds < $1.seconds }.map(\.window)
        guard !windows.isEmpty else { throw Error.unreadable }
        let credits = root["rate_limit_reset_credits"] as? [String: Any]
        return .init(windows: windows, resetsAvailable: credits?["available_count"] as? Int, fetchedAt: fetchedAt)
    }

    private static func label(seconds: Double) -> String {
        switch seconds {
        case 604_800: return "Week"
        case 86_400: return "Day"
        default: return "\(Int((seconds / 3600).rounded()))h"
        }
    }

    private static func date(iso8601 text: String) -> Date? {
        // Fractional seconds vary in length; whole seconds are precise enough for a reset time.
        let whole = text.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return ISO8601DateFormatter().date(from: whole)
    }
}

/// The access token inside a saved Claude login and whether Claude would still use it without refreshing.
struct ClaudeAccess: Equatable {
    let token: String
    let expiresAt: Date?

    init?(rawLogin: String) {
        guard let login = try? JSONSerialization.jsonObject(with: Data(rawLogin.utf8)) as? [String: Any],
              let token = login["accessToken"] as? String, !token.isEmpty else { return nil }
        self.token = token
        expiresAt = (login["expiresAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
    }

    /// Claude refreshes a login five minutes before it expires, so treat that margin as expired.
    func isFresh(at now: Date) -> Bool { expiresAt.map { $0.timeIntervalSince(now) > 300 } ?? false }
}

enum UsageRequests {
    static func claude(accessToken: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!, timeoutInterval: 15)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        return request
    }

    static func codex(accessToken: String, accountID: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!, timeoutInterval: 15)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        request.setValue("codex-cli", forHTTPHeaderField: "User-Agent")
        return request
    }
}

/// A Keychain item that a renewal creates, reads back and always removes.
protocol IsolatedCredentialItem {
    func read() throws -> Data
    func create(data: Data) throws
    func delete() throws
}

/// Lets the official Claude Code refresh a saved login whose access has expired.
///
/// Claude runs one tiny request with the login in a throwaway configuration directory, which Claude maps to
/// its own Keychain item, so the live login and `~/.claude.json` are never touched. The copy is marked
/// expired so Claude always refreshes it. Claude rotates the refresh token as it refreshes, so the rotated
/// login is returned for saving before anything is removed.
struct ClaudeIsolatedRenewal {
    enum Error: Swift.Error, Equatable { case notALogin, claudeFailed, identityChanged }
    typealias Runner = (_ executable: String, _ arguments: [String], _ environment: [String: String], _ directory: String) throws -> Int32

    let claudeExecutable: String
    let keychainAccount: String
    /// The item Claude uses for the throwaway directory: a Keychain item on macOS, a file on Linux.
    let item: (_ service: String, _ directory: String) -> any IsolatedCredentialItem
    let run: Runner

    func renew(_ snapshot: ClaudeLoginSnapshot) throws -> ClaudeLoginSnapshot {
        guard case .value = snapshot.claudeAiOauth, case .value = snapshot.oauthAccount else { throw Error.notALogin }
        let directory = try FileManager.default.url(
            for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: FileManager.default.temporaryDirectory, create: true
        ).path
        defer { try? FileManager.default.removeItem(atPath: directory) }
        // Claude names the item for a custom configuration directory after the first 8 hex digits of its SHA-256.
        let digest = SHA256.hash(data: Data(directory.precomposedStringWithCanonicalMapping.utf8))
        let service = "Claude Code-credentials-" + digest.map { String(format: "%02x", $0) }.joined().prefix(8)
        let credentials = item(service, directory)
        guard case .value(let login) = snapshot.claudeAiOauth else { throw Error.notALogin }
        var secureFields = ClaudeLoginOwnedFields.target(snapshot).secure
        secureFields["claudeAiOauth"] = .value(try ScopedJSON(login).replacing(["expiresAt": .value("0")]))
        let secure = try ScopedJSON("{}").replacing(secureFields)
        let profile = try ScopedJSON("{}").replacing(["oauthAccount": snapshot.oauthAccount])
        try Data(try ScopedJSON(profile).replacing(["hasCompletedOnboarding": .value("true")]).utf8)
            .write(to: URL(fileURLWithPath: directory + "/.claude.json"), options: .withoutOverwriting)
        try credentials.create(data: Data(secure.utf8))
        defer { try? credentials.delete() }

        var environment = ["HOME": NSHomeDirectory(), "CLAUDE_CONFIG_DIR": directory, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        for name in ["USER", "LOGNAME", "LANG", "TMPDIR"] { environment[name] = ProcessInfo.processInfo.environment[name] }
        // The exit status does not matter: a refresh can succeed even if the request after it fails.
        _ = try? run(claudeExecutable, ["-p", "Reply with exactly: OK", "--model", "haiku"], environment, directory)

        guard let renewedRoot = String(data: try credentials.read(), encoding: .utf8) else { throw Error.claudeFailed }
        let renewed = try ClaudeLoginSnapshot.capture(secureRoot: renewedRoot, configurationRoot: profile)
        guard renewed.identity == snapshot.identity else { throw Error.identityChanged }
        // Claude refreshes the expired copy on a successful run, so an unchanged login means nothing was renewed.
        guard renewed.claudeAiOauth != snapshot.claudeAiOauth, renewed.usability == .usable else {
            throw Error.claudeFailed
        }
        return renewed
    }
}

/// `usage` prints every saved login's usage; `claude-login renew <alias>` renews one saved Claude login.
func runAsyncReport(arguments: [String], output: @escaping @Sendable (String) -> Void = { print($0) }) -> Int32 {
    let claude = ClaudeLoginAppAdapter.configured()
    let codex = CodexLoginAppAdapter.configured()
    let status = LockedStatus()
    let done = DispatchSemaphore(value: 0)
    Task {
        defer { done.signal() }
        if arguments.count == 3 {
            let result = arguments[0] == "codex-login" ? await codex.renew(alias: arguments[2]) : await claude.renew(alias: arguments[2])
            switch result {
            case .done(let text): output(text)
            case .blocked(let text): output(text); status.value = 3
            }
            return
        }
        for (title, usage) in [("Claude", await claude.usage()), ("Codex", await codex.usage())] {
            if usage.isEmpty { output("\(title): no saved logins, or login switching is off (use aic)."); continue }
            for (alias, result) in usage.sorted(by: { $0.key < $1.key }) {
                switch result {
                case .usage(let usage):
                    let windows = usage.windows.map { "\($0.label) \(Int($0.usedPercent.rounded()))%" }.joined(separator: " · ")
                    let resets = usage.resetsAvailable.map { " · \($0) resets" } ?? ""
                    output("\(title) \(alias): \(windows)\(resets)")
                case .unavailable(let reason):
                    output("\(title) \(alias): \(reason)")
                }
            }
        }
    }
    done.wait()
    return status.value
}

private final class LockedStatus: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Int32 = 0
    var value: Int32 {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
