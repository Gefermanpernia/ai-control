import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import AIControlCore

private struct MonitorFailure: Error {}

struct UsageMonitorsTests {
    private let secret = "secret-never-print-me"
    private let now = Date(timeIntervalSince1970: 0)

    private func service(environment: [String: String] = [:], file: Data? = nil,
                         fetch: @escaping (URLRequest) async throws -> (Int, Data) = { _ in throw MonitorFailure() }) -> UsageMonitors {
        UsageMonitors(environment: environment, readFile: { _ in
            guard let file else { throw MonitorFailure() }
            return file
        }, fetch: fetch, now: { now })
    }

    private func entry(_ key: String, type: String = "api") -> Data {
        Data(#"{"opencode-go":{"type":"\#(type)","key":"\#(key)"}}"#.utf8)
    }

    @Test("Key discovery respects XDG file, env override, and invalid input")
    func discovery() async {
        let file = entry(secret)
        let fromFile = UsageMonitors(environment: ["XDG_DATA_HOME": "/fixture"], readFile: { path in
            #expect(path == "/fixture/opencode/auth.json")
            return file
        }, fetch: { _ in throw MonitorFailure() }, now: { now })
        #expect(await fromFile.monitors(includeUsage: false).map(\.id) == ["opencode-go"])
        let fromEnv = UsageMonitors(environment: ["OPENCODE_AUTH_CONTENT": String(decoding: file, as: UTF8.self)],
            readFile: { _ in Issue.record("env should bypass file"); throw MonitorFailure() },
            fetch: { request in
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(secret)")
                return (401, Data())
            }, now: { now })
        #expect(await fromEnv.monitors(includeUsage: true).first?.error == "The OpenCode Go key was rejected.")
        for invalid in [service(), service(file: Data("{".utf8)), service(file: entry(secret, type: "oauth")),
                        service(environment: ["OPENCODE_AUTH_CONTENT": "broken"], file: file)] {
            #expect(await invalid.monitors(includeUsage: false).isEmpty)
        }
    }

    @Test("Request and response retain only valid ordered windows, dropping zero reset placeholders")
    func windows() async throws {
        let payload = Data(#"{"usage":{"monthly":{"status":"ok","percent":75,"resetsAt":"2026-09-13T16:27:38Z"},"rolling":{"status":"ok","percent":0,"resetsAt":"2026-08-13T16:27:38.287Z"},"weekly":{"status":"ok","percent":42,"resetsAt":"2026-08-20T16:27:38Z"}}}"#.utf8)
        let subject = service(file: entry(secret), fetch: { request in
            #expect(request.url?.absoluteString == "https://opencode.ai/zen/go/v1/usage")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(secret)")
            #expect(request.timeoutInterval == 15)
            return (200, payload)
        })
        let monitor = try #require(await subject.monitors(includeUsage: true).first)
        let usage = try #require(monitor.usage)
        #expect(usage.windows.map(\.label) == ["5h", "Week", "Month"])
        #expect(usage.windows.map(\.usedPercent) == [0, 42, 75])
        #expect(usage.windows[0].resetsAt == nil)
        #expect(usage.windows[1].resetsAt != nil)
        #expect(usage.fetchedAt == now)
        #expect(monitor.error == nil)
    }

    @Test("Reshaped responses skip windows without a numeric percent and reject empty usage")
    func reshaped() async {
        let partial = service(file: entry(secret), fetch: { _ in
            (200, Data(#"{"usage":{"rolling":{"status":"pending","percent":4},"weekly":{"status":"ok","percent":8},"monthly":{"status":"ok","percent":"10"}}}"#.utf8))
        })
        #expect(await partial.monitors(includeUsage: true).first?.usage?.windows.map(\.label) == ["5h", "Week"])
        let empty = service(file: entry(secret), fetch: { _ in (200, Data(#"{"usage":{}}"#.utf8)) })
        #expect(await empty.monitors(includeUsage: true).first?.error == "OpenCode Go usage could not be read.")
    }

    @Test("An exhausted window stays visible whatever its status")
    func exhausted() async throws {
        let subject = service(file: entry(secret), fetch: { _ in
            (200, Data(#"{"usage":{"rolling":{"status":"rate_limited","percent":100,"resetsAt":"2026-08-13T16:27:38Z"},"weekly":{"status":"ok","percent":60,"resetsAt":"2026-08-20T16:27:38Z"}}}"#.utf8))
        })
        let usage = try #require(await subject.monitors(includeUsage: true).first?.usage)
        #expect(usage.windows.map(\.label) == ["5h", "Week"])
        #expect(usage.windows[0].usedPercent == 100)
        #expect(usage.windows[0].resetsAt != nil)
    }

    @Test("NaN key is environment-only and opt-in never fetches without usage")
    func nanDiscovery() async {
        for value in [nil, ""] as [String?] {
            let subject = service(environment: value.map { ["NAN_API_KEY": $0] } ?? [:])
            #expect(await subject.monitors(includeUsage: true).isEmpty)
        }
        let subject = service(environment: ["NAN_API_KEY": secret], fetch: { _ in
            Issue.record("unexpected NaN fetch")
            throw MonitorFailure()
        })
        let monitors = await subject.monitors(includeUsage: false)
        #expect(monitors.map(\.id) == ["nan"])
        #expect(monitors.first?.models == nil && monitors.first?.error == nil)
    }

    @Test("NaN requests UTC month boundaries and sorts nonzero models with only published quotas")
    func nanModels() async throws {
        let instant = try #require(ISO8601DateFormatter().date(from: "2026-09-27T12:00:00Z"))
        let body = Data(#"{"totals":{"by_model":[{"model":"glm5.3","prompt_tokens":1,"completion_tokens":1,"total_tokens":40,"api_requests":1},{"model":"qwen3.8-flash","prompt_tokens":2,"completion_tokens":3,"total_tokens":250000000,"api_requests":1},{"model":"unknown","prompt_tokens":5,"completion_tokens":0,"total_tokens":40,"api_requests":1},{"model":"deepseek-v4-flash","prompt_tokens":0,"completion_tokens":0,"total_tokens":0,"api_requests":0}]},"data":[],"has_more":true,"next_cursor":"ignored"}"#.utf8)
        let subject = UsageMonitors(environment: ["NAN_API_KEY": secret], readFile: { _ in throw MonitorFailure() },
            fetch: { request in
                #expect(request.url?.absoluteString == "https://api.nan.builders/v1/usage?start_date=2026-09-01&end_date=2026-09-27&limit=1")
                #expect(request.httpMethod == "GET")
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(secret)")
                #expect(request.timeoutInterval == 15)
                return (200, body)
            }, now: { instant })
        let monitor = try #require(await subject.monitors(includeUsage: true).first)
        #expect(monitor.usage == nil && monitor.error == nil)
        let models = try #require(monitor.models)
        #expect(models.map(\.model) == ["qwen3.8-flash", "glm5.3", "unknown"])
        #expect(models[0].totalTokens == 250000000)
        #expect(models[0].quotaTokens == 500000000)
        #expect(models[0].usedPercent == 50)
        #expect(models[0].resetsAt == ISO8601DateFormatter().date(from: "2026-10-01T00:00:00Z"))
        #expect(models[1].quotaTokens == nil && models[1].usedPercent == nil && models[1].resetsAt == nil)
        #expect(models[2].quotaTokens == nil && models[2].usedPercent == nil && models[2].resetsAt == nil)
    }

    @Test("NaN December usage resets in January and empty model lists are valid")
    func nanCalendar() async throws {
        let instant = try #require(ISO8601DateFormatter().date(from: "2026-12-31T23:59:00Z"))
        let subject = UsageMonitors(environment: ["NAN_API_KEY": secret], readFile: { _ in throw MonitorFailure() },
            fetch: { request in
                #expect(request.url?.query == "start_date=2026-12-01&end_date=2026-12-31&limit=1")
                return (200, Data(#"{"totals":{"by_model":[{"model":"mimo-v2.5","total_tokens":1000000000,"prompt_tokens":0,"completion_tokens":0,"api_requests":1}]}}"#.utf8))
            }, now: { instant })
        let model = try #require(await subject.monitors(includeUsage: true).first?.models?.first)
        #expect(model.usedPercent == 100)
        #expect(model.resetsAt == ISO8601DateFormatter().date(from: "2027-01-01T00:00:00Z"))
        let empty = service(environment: ["NAN_API_KEY": secret], fetch: { _ in
            (200, Data(#"{"totals":{"by_model":[]}}"#.utf8))
        })
        let monitor = try #require(await empty.monitors(includeUsage: true).first)
        #expect(monitor.models?.isEmpty == true && monitor.error == nil)
    }

    @Test("NaN failures are safe and never reflect response bodies or credentials")
    func nanFailures() async {
        for (code, body, message) in [
            (401, Data(secret.utf8), "The NaN key was rejected."),
            (429, Data(secret.utf8), "NaN usage is rate limited; try again shortly."),
            (500, Data(secret.utf8), "NaN usage is unavailable."),
            (200, Data(#"{"totals":{"by_model":[{"model":"bad","total_tokens":"1"}]}}"#.utf8), "NaN usage could not be read.")
        ] {
            let subject = service(environment: ["NAN_API_KEY": secret], fetch: { _ in (code, body) })
            let monitor = await subject.monitors(includeUsage: true).first
            #expect(monitor?.models == nil && monitor?.error == message)
            #expect(monitor?.error?.contains(secret) == false)
        }
        #expect(await service(environment: ["NAN_API_KEY": secret]).monitors(includeUsage: true).first?.error == "NaN usage is unavailable.")
    }

    @Test("HTTP failures and network failures use safe exact errors")
    func failures() async {
        for (code, message) in [(401, "The OpenCode Go key was rejected."),
                                (403, "This OpenCode Go key has no Go subscription."),
                                (500, "OpenCode Go usage is unavailable.")] {
            let subject = service(file: entry(secret), fetch: { _ in (code, Data(secret.utf8)) })
            let monitor = await subject.monitors(includeUsage: true).first
            #expect(monitor?.usage == nil)
            #expect(monitor?.error == message)
            #expect(monitor?.error?.contains(secret) == false)
        }
        let network = service(file: entry(secret))
        #expect(await network.monitors(includeUsage: true).first?.error == "OpenCode Go usage is unavailable.")
    }
}
