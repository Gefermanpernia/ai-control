import Foundation
import CoreFoundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Read-only usage for API-key subscriptions; credentials remain local to the request.
struct UsageMonitors {
    let environment: [String: String]
    let readFile: (String) throws -> Data
    let fetch: (URLRequest) async throws -> (Int, Data)
    let now: () -> Date

    static var live: Self {
        .init(environment: ProcessInfo.processInfo.environment,
              readFile: { try Data(contentsOf: URL(fileURLWithPath: $0)) },
              fetch: { request in
                  let (data, response) = try await URLSession.shared.data(for: request)
                  return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
              }, now: Date.init)
    }

    func monitors(includeUsage: Bool) async -> [LoginStatus.Monitor] {
        guard let key = opencodeGoKey() else { return [] }
        guard includeUsage else { return [.init(id: "opencode-go", name: "OpenCode Go", usage: nil, error: nil)] }
        var request = URLRequest(url: URL(string: "https://opencode.ai/zen/go/v1/usage")!, timeoutInterval: 15)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let usage: LoginStatus.Usage?
        let message: String?
        do {
            let (status, body) = try await fetch(request)
            switch status {
            case 200:
                if let parsed = Self.parse(body, fetchedAt: now()) {
                    usage = LoginStatus.Usage(parsed)
                    message = nil
                } else {
                    usage = nil
                    message = "OpenCode Go usage could not be read."
                }
            case 401:
                usage = nil
                message = "The OpenCode Go key was rejected."
            case 403:
                usage = nil
                message = "This OpenCode Go key has no Go subscription."
            default:
                usage = nil
                message = "OpenCode Go usage is unavailable."
            }
        } catch {
            usage = nil
            message = "OpenCode Go usage is unavailable."
        }
        return [.init(id: "opencode-go", name: "OpenCode Go", usage: usage, error: message)]
    }

    private func opencodeGoKey() -> String? {
        let data: Data
        if let content = environment["OPENCODE_AUTH_CONTENT"] {
            data = Data(content.utf8)
        } else {
            let home = environment["HOME"] ?? NSHomeDirectory()
            let dataHome = environment["XDG_DATA_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? home + "/.local/share"
            guard let file = try? readFile(dataHome + "/opencode/auth.json") else { return nil }
            data = file
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entry = root["opencode-go"] as? [String: Any],
              entry["type"] as? String == "api",
              let key = entry["key"] as? String, !key.isEmpty else { return nil }
        return key
    }

    private static func parse(_ data: Data, fetchedAt: Date) -> LoginUsage? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let usage = root["usage"] as? [String: Any] else { return nil }
        let windows: [LoginUsage.Window] = [("rolling", "5h"), ("weekly", "Week"), ("monthly", "Month")].compactMap { key, label in
            // Any status counts: an exhausted window may report something other than "ok" and must stay visible.
            guard let item = usage[key] as? [String: Any],
                  let percent = item["percent"] as? NSNumber,
                  CFGetTypeID(percent) != CFBooleanGetTypeID(), percent.doubleValue.isFinite else { return nil }
            let reset: Date?
            if percent.doubleValue == 0 {
                reset = nil
            } else if let text = item["resetsAt"] as? String {
                let whole = text.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
                reset = ISO8601DateFormatter().date(from: whole)
            } else {
                reset = nil
            }
            return .init(label: label, usedPercent: percent.doubleValue, resetsAt: reset)
        }
        guard !windows.isEmpty else { return nil }
        return .init(windows: windows, resetsAvailable: nil, fetchedAt: fetchedAt)
    }
}
