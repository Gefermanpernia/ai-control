import Foundation
import Testing
@testable import AIControlCore

struct AutoSwitchTests {
    private func usage(_ fiveHour: Double, _ week: Double) -> LoginUsageResult {
        .usage(.init(windows: [.init(label: "5h", usedPercent: fiveHour, resetsAt: nil),
                               .init(label: "Week", usedPercent: week, resetsAt: nil)],
                     resetsAvailable: nil, fetchedAt: Date(timeIntervalSince1970: 0)))
    }

    private func account(_ name: String, usable: Bool = true) -> AutoSwitchPlanner.Account {
        .init(name: name, usable: usable)
    }

    // MARK: - Decision

    @Test("Below the threshold on every window, the current account stays")
    func staysBelowThreshold() {
        let decision = AutoSwitchPlanner.decide(
            current: "work", accounts: [account("home"), account("work")],
            usage: ["work": usage(98, 60), "home": usage(0, 0)], order: [], threshold: 99)
        #expect(decision == .stay)
    }

    @Test("A 5-hour window at the threshold switches to the first usable account in priority order")
    func switchesOnFiveHour() {
        let decision = AutoSwitchPlanner.decide(
            current: "work", accounts: [account("alpha"), account("home"), account("work")],
            usage: ["work": usage(99, 40), "alpha": usage(0, 0), "home": usage(10, 10)],
            order: ["work", "home", "alpha"], threshold: 99)
        #expect(decision == .switchTo("home"))
    }

    @Test("A spent weekly window makes an account unusable even with 5-hour room left")
    func weeklyOutweighsFiveHour() {
        let decision = AutoSwitchPlanner.decide(
            current: "work", accounts: [account("home"), account("spare"), account("work")],
            usage: ["work": usage(5, 99), "home": usage(0, 100), "spare": usage(50, 30)],
            order: ["work", "home", "spare"], threshold: 99)
        #expect(decision == .switchTo("spare"))
    }

    @Test("Accounts that need sign-in, lack usage, or are also spent are skipped; none left means no switch")
    func skipsUnusableCandidates() {
        let accounts = [account("home", usable: false), account("spare"), account("old"), account("work")]
        let decision = AutoSwitchPlanner.decide(
            current: "work", accounts: accounts,
            usage: ["work": usage(100, 50), "home": usage(0, 0), "old": usage(0, 99)], order: [], threshold: 99)
        #expect(decision == .noCandidate)
    }

    @Test("Nothing happens without a known current account or its usage")
    func unknownCurrent() {
        let accounts = [account("home"), account("work")]
        #expect(AutoSwitchPlanner.decide(current: nil, accounts: accounts, usage: ["home": usage(0, 0)],
                                         order: [], threshold: 99) == .unknownCurrent)
        #expect(AutoSwitchPlanner.decide(current: "work", accounts: accounts,
                                         usage: ["work": .unavailable("offline"), "home": usage(0, 0)],
                                         order: [], threshold: 99) == .unknownCurrent)
    }

    @Test("After a switch the new account is below the threshold, so the next check stays: no loop")
    func noLoop() {
        let accounts = [account("home"), account("work")]
        let usage = ["work": usage(99, 10), "home": usage(10, 10)]
        #expect(AutoSwitchPlanner.decide(current: "work", accounts: accounts, usage: usage, order: [], threshold: 99)
                == .switchTo("home"))
        #expect(AutoSwitchPlanner.decide(current: "home", accounts: accounts, usage: usage, order: [], threshold: 99)
                == .stay)
    }

    // MARK: - Priority order

    @Test("Saved order comes first, then the other accounts by name; stale names are ignored")
    func effectiveOrder() {
        #expect(AutoSwitchPlanner.ordered(["alpha", "home", "work"], by: ["work", "gone", "home"])
                == ["work", "home", "alpha"])
        #expect(AutoSwitchPlanner.ordered(["b", "a"], by: []) == ["a", "b"])
    }

    @Test("Moving an account up or down swaps it with its neighbour; the ends stay put")
    func moves() {
        let names = ["alpha", "home", "work"]
        #expect(AutoSwitchPlanner.moving("work", up: true, in: names, by: []) == ["alpha", "work", "home"])
        #expect(AutoSwitchPlanner.moving("alpha", up: true, in: names, by: []) == ["alpha", "home", "work"])
        #expect(AutoSwitchPlanner.moving("alpha", up: false, in: names, by: []) == ["home", "alpha", "work"])
        #expect(AutoSwitchPlanner.moving("missing", up: false, in: names, by: []) == nil)
    }

    // MARK: - Check command

    private final class Log: @unchecked Sendable { var lines: [String] = []; var used: [String] = []; var fetched = 0 }

    private func provider(_ log: Log, current: String?, usage: [String: LoginUsageResult],
                          useResult: String? = nil) -> AutoSwitchProvider {
        AutoSwitchProvider(
            name: "Claude", kind: .claude,
            accounts: { (current, [.init(name: "home", usable: true), .init(name: "work", usable: true)]) },
            usage: { log.fetched += 1; return usage },
            use: { name in log.used.append(name); return useResult })
    }

    private func settings(claude: Bool, threshold: Int = 99) -> AIControlSettings {
        var settings = AIControlSettings()
        settings.autoSwitch.claude = claude
        settings.autoSwitch.thresholdPercent = threshold
        return settings
    }

    @Test("Check switches an enabled provider and reports it")
    func checkSwitches() async {
        let log = Log()
        let code = await runAutoSwitchCheck(
            providers: [provider(log, current: "work", usage: ["work": usage(99, 1), "home": usage(1, 1)])],
            settings: settings(claude: true)) { log.lines.append($0) }
        #expect(code == 0)
        #expect(log.used == ["home"])
        #expect(log.lines == ["Claude: switched from work to home (work reached 99% of a usage limit)."])
    }

    @Test("Check never fetches usage or switches a provider whose automatic switching is off")
    func checkSkipsDisabled() async {
        let log = Log()
        let code = await runAutoSwitchCheck(
            providers: [provider(log, current: "work", usage: ["work": usage(100, 100), "home": usage(0, 0)])],
            settings: settings(claude: false)) { log.lines.append($0) }
        #expect(code == 0)
        #expect(log.fetched == 0 && log.used.isEmpty)
        #expect(log.lines == ["Claude: automatic switching is off."])
    }

    @Test("A refused switch is reported and exits with 3")
    func checkReportsRefusal() async {
        let log = Log()
        let code = await runAutoSwitchCheck(
            providers: [provider(log, current: "work", usage: ["work": usage(99, 1), "home": usage(1, 1)],
                                 useResult: "Blocked: another change is in progress.")],
            settings: settings(claude: true)) { log.lines.append($0) }
        #expect(code == 3)
        #expect(log.lines == ["Claude: not switched to home. Blocked: another change is in progress."])
    }

    @Test("A background check does nothing unless background refresh and switching are both on")
    func backgroundCheckNeedsBothOptions() async {
        let log = Log()
        var settings = settings(claude: true)
        let providers = [provider(log, current: "work", usage: ["work": usage(99, 1), "home": usage(1, 1)])]
        #expect(await runAutoSwitchCheck(providers: providers, settings: settings, background: true) { log.lines.append($0) } == 0)
        #expect(log.fetched == 0 && log.used.isEmpty)
        #expect(log.lines == ["Background checks are off."])
        settings.autoSwitch.background = true
        #expect(await runAutoSwitchCheck(providers: providers, settings: settings, background: true) { log.lines.append($0) } == 0)
        #expect(log.used == ["home"])
    }

    // MARK: - Stored order

    @Test("The order is stored in the settings, keeps only valid names, and follows a rename")
    func storedOrder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("order-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SettingsStore(directory: root.path)
        try store.update { $0.autoSwitch.claudeOrder = ["work", "home"] }
        try store.renameInOrder(.claude, from: "work", to: "office")
        #expect(try store.load().autoSwitch.claudeOrder == ["office", "home"])
        try store.renameInOrder(.codex, from: "work", to: "office")
        #expect(try store.load().autoSwitch.codexOrder.isEmpty)

        try FileManager.default.createDirectory(atPath: root.path, withIntermediateDirectories: true)
        try Data(#"{"autoSwitch":{"claudeOrder":["ok","Bad!",""]}}"#.utf8).write(to: URL(fileURLWithPath: store.path))
        #expect(try store.load().autoSwitch.claudeOrder == ["ok"])
    }
}
