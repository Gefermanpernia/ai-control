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
        var result: [LoginStatus.Monitor] = []
        if let key = opencodeGoKey() {
            result.append(await opencodeGoMonitor(key: key, includeUsage: includeUsage))
        }
        if let key = environment["NAN_API_KEY"], !key.isEmpty {
            result.append(await nanMonitor(key: key, includeUsage: includeUsage))
        }
        return result
    }

    private func opencodeGoMonitor(key: String, includeUsage: Bool) async -> LoginStatus.Monitor {
        guard includeUsage else { return .init(id: "opencode-go", name: "OpenCode Go", usage: nil, error: nil) }
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
        return .init(id: "opencode-go", name: "OpenCode Go", usage: usage, error: message)
    }

    // NaN Models page (nan.builders/docs/models), checked 2026-09-27; NaN rotates models quarterly.
    private static let nanMonthlyQuotas = [
        "deepseek-v4-flash": 3_000_000_000,
        "glm5.3-flash": 2_000_000_000,
        "mimo-v2.5": 1_000_000_000,
        "mimo-v2.6-flash": 1_000_000_000,
        "qwen3.8-flash": 500_000_000
    ]

    private struct NaNReport: Decodable {
        struct Totals: Decodable {
            // Only the fields shown are required, so extra or missing counters do not break parsing.
            struct Model: Decodable {
                let model: String
                let totalTokens: Int

                enum CodingKeys: String, CodingKey { case model, totalTokens = "total_tokens" }
            }
            let byModel: [Model]
            enum CodingKeys: String, CodingKey { case byModel = "by_model" }
        }
        let totals: Totals
    }

    private func nanMonitor(key: String, includeUsage: Bool) async -> LoginStatus.Monitor {
        guard includeUsage else { return .init(id: "nan", name: "NaN", usage: nil, error: nil) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = now()
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: today))!
        let reset = calendar.date(byAdding: .month, value: 1, to: start)!
        let dateFormatter = DateFormatter()
        dateFormatter.calendar = calendar
        dateFormatter.timeZone = calendar.timeZone
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        var components = URLComponents(string: "https://api.nan.builders/v1/usage")!
        components.percentEncodedQuery = "start_date=\(dateFormatter.string(from: start))&end_date=\(dateFormatter.string(from: today))&limit=1"
        var request = URLRequest(url: components.url!, timeoutInterval: 15)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        do {
            let (status, body) = try await fetch(request)
            switch status {
            case 200:
                guard let report = try? JSONDecoder().decode(NaNReport.self, from: body) else {
                    return .init(id: "nan", name: "NaN", usage: nil, error: "NaN usage could not be read.")
                }
                let models: [LoginStatus.ModelUsage] = report.totals.byModel.filter { $0.totalTokens > 0 }.map { item in
                    let quota = Self.nanMonthlyQuotas[item.model]
                    let percent: Double? = quota.map { Double(item.totalTokens) / Double($0) * 100 }
                    let resetAt: Date? = quota == nil ? nil : reset
                    return .init(model: item.model, totalTokens: item.totalTokens,
                                 quotaTokens: quota, usedPercent: percent, resetsAt: resetAt)
                }.sorted { $0.totalTokens == $1.totalTokens ? $0.model < $1.model : $0.totalTokens > $1.totalTokens }
                return .init(id: "nan", name: "NaN", usage: nil, models: models, error: nil)
            case 401:
                return .init(id: "nan", name: "NaN", usage: nil, error: "The NaN key was rejected.")
            case 429:
                return .init(id: "nan", name: "NaN", usage: nil, error: "NaN usage is rate limited; try again shortly.")
            default:
                return .init(id: "nan", name: "NaN", usage: nil, error: "NaN usage is unavailable.")
            }
        } catch {
            return .init(id: "nan", name: "NaN", usage: nil, error: "NaN usage is unavailable.")
        }
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
