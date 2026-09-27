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
