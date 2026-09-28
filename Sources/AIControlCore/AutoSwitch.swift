import Foundation

/// Decides whether to move off an account that reached a usage limit, and to which saved account.
///
/// An account is spent when any of its windows (5-hour or weekly) is at or above the threshold: a spent
/// weekly window makes the account unusable even with 5-hour room left. Only accounts with known usage below
/// the threshold on every window, and that need no sign-in, are candidates, so a switch never lands on an
/// account that would switch straight back.
enum AutoSwitchPlanner {
    struct Account: Equatable, Sendable {
        let name: String
        let usable: Bool
    }

    enum Decision: Equatable {
        case stay, switchTo(String), noCandidate, unknownCurrent
    }

    static func spent(_ usage: LoginUsage, threshold: Int) -> Bool {
        usage.windows.contains { $0.usedPercent >= Double(threshold) }
    }

    static func decide(current: String?, accounts: [Account], usage: [String: LoginUsageResult],
                       order: [String], threshold: Int) -> Decision {
        guard let current, case .usage(let live) = usage[current] else { return .unknownCurrent }
        guard spent(live, threshold: threshold) else { return .stay }
        let usable = Set(accounts.filter(\.usable).map(\.name))
        let next = ordered(accounts.map(\.name), by: order).first { name in
            guard name != current, usable.contains(name), case .usage(let candidate) = usage[name] else { return false }
            return !spent(candidate, threshold: threshold)
        }
        return next.map(Decision.switchTo) ?? .noCandidate
    }

    /// The saved order first, then the remaining accounts by name; names no longer saved are ignored.
    static func ordered(_ names: [String], by order: [String]) -> [String] {
        let saved = Set(names)
        let listed = order.filter(saved.contains)
        return listed + names.filter { !listed.contains($0) }.sorted()
    }

    /// The whole order after moving `name` one place; nil when it is not a saved account.
    static func moving(_ name: String, up: Bool, in names: [String], by order: [String]) -> [String]? {
        var list = ordered(names, by: order)
        guard let index = list.firstIndex(of: name) else { return nil }
        let target = up ? index - 1 : index + 1
        if list.indices.contains(target) { list.swapAt(index, target) }
        return list
    }
}

/// One provider as the automatic switch sees it; live values come from the login adapters.
struct AutoSwitchProvider: Sendable {
    let name: String
    let kind: AIControlSettings.Provider
    /// The account in use (nil when unknown) and every saved account.
    let accounts: @Sendable () async -> (current: String?, accounts: [AutoSwitchPlanner.Account])?
    let usage: @Sendable () async -> [String: LoginUsageResult]
    /// Switches and returns nil, or returns why it did not.
    let use: @Sendable (String) async -> String?

    static func claude(_ adapter: ClaudeLoginAppAdapter) -> Self {
        .init(name: "Claude", kind: .claude,
              accounts: {
                  guard case .listed(let state) = await adapter.list() else { return nil }
                  return (state.lastSelectedHint, state.aliases.map { .init(name: $0.name, usable: !$0.requiresReLogin) })
              },
              usage: { await adapter.usage() },
              use: { name in
                  if case .verifiedApplied = await adapter.use(alias: name) { return nil }
                  return "Claude or its files changed, or a switch is already running."
              })
    }

    static func codex(_ adapter: CodexLoginAppAdapter) -> Self {
        .init(name: "Codex", kind: .codex,
              accounts: {
                  guard case .listed(let listing) = await adapter.list() else { return nil }
                  return (listing.inUse, listing.logins.map { .init(name: $0.name, usable: true) })
              },
              usage: { await adapter.usage() },
              use: { name in
                  switch await adapter.use(alias: name) {
                  case .switched: return nil
                  case .blocked(let message): return message
                  default: return "Codex login switching is not available."
                  }
              })
    }
}

/// What one provider's automatic switch check did. `line` is exactly what `aic auto-switch check` prints for
/// it, so interfaces can decide on `outcome` without parsing the text.
struct AutoSwitchReport: Equatable, Sendable {
    enum Outcome: Equatable, Sendable {
        case off, unreadable, stay, unknownCurrent, noCandidate
        case switched(to: String)
        case refused(to: String)
    }
    let kind: AIControlSettings.Provider
    let outcome: Outcome
    let line: String
}

/// Checks one provider and switches it when its automatic switching is on and the account in use is spent.
func checkAutoSwitch(_ provider: AutoSwitchProvider, settings: AIControlSettings) async -> AutoSwitchReport {
    func report(_ outcome: AutoSwitchReport.Outcome, _ text: String) -> AutoSwitchReport {
        .init(kind: provider.kind, outcome: outcome, line: "\(provider.name): \(text)")
    }
    guard settings.switching(provider.kind) else { return report(.off, "automatic switching is off.") }
    guard let listed = await provider.accounts() else { return report(.unreadable, "saved accounts could not be read.") }
    let threshold = settings.autoSwitch.thresholdPercent
    let usage = await provider.usage()
    switch AutoSwitchPlanner.decide(current: listed.current, accounts: listed.accounts, usage: usage,
                                    order: settings.order(provider.kind), threshold: threshold) {
    case .stay:
        return report(.stay, "\(listed.current ?? "the current account") is below \(threshold)%.")
    case .unknownCurrent:
        return report(.unknownCurrent, "the account in use or its usage is unknown; nothing changed.")
    case .noCandidate:
        return report(.noCandidate, "no other account is below \(threshold)% on every limit; nothing changed.")
    case .switchTo(let next):
        let current = listed.current ?? "the current account"
        if let refusal = await provider.use(next) {
            return report(.refused(to: next), "not switched to \(next). \(refusal)")
        }
        return report(.switched(to: next),
                      "switched from \(current) to \(next) (\(current) reached \(threshold)% of a usage limit).")
    }
}

/// Checks every provider once and switches the ones with automatic switching on; one line per provider.
/// A background check (a timer with no interface open) runs only while background refresh is on too.
func runAutoSwitchCheck(providers: [AutoSwitchProvider], settings: AIControlSettings, background: Bool = false,
                        output: (String) -> Void) async -> Int32 {
    if background, !settings.backgroundRefreshActive {
        output("Background checks are off.")
        return 0
    }
    var status: Int32 = 0
    for provider in providers {
        let report = await checkAutoSwitch(provider, settings: settings)
        output(report.line)
        switch report.outcome {
        case .unreadable, .refused: status = 3
        default: break
        }
    }
    return status
}

/// Moves a saved account one place up or down in the priority order and saves it. It only reads and writes
/// the settings, never a login adapter, so the menu can call it on the main actor with the accounts it shows.
/// Returns the new order, or nil when `alias` is not among `names` (nothing is written then).
func movePriority(_ kind: AIControlSettings.Provider, alias: String, up: Bool, in names: [String],
                  store: SettingsStore) throws -> [String]? {
    guard names.contains(alias) else { return nil }
    var order: [String]?
    try store.update { settings in
        order = AutoSwitchPlanner.moving(alias, up: up, in: names, by: settings.order(kind))
        if let order { settings.setOrder(kind, order) }
    }
    return order
}

/// `auto-switch check [--background]`, `auto-switch order claude|codex`,
/// `auto-switch move claude|codex <alias> up|down`.
func runAutoSwitch(arguments: [String], claude: ClaudeLoginAppAdapter = .configured(),
                   codex: CodexLoginAppAdapter = .configured(), store: SettingsStore = .live,
                   output: @escaping @Sendable (String) -> Void) -> Int32 {
    let usage = "Usage: AIControl auto-switch check [--background] | order claude|codex | move claude|codex <alias> up|down"
    let providers = ["claude": AutoSwitchProvider.claude(claude), "codex": .codex(codex)]
    let result = ResultBox()
    let done = DispatchSemaphore(value: 0)
    Task {
        defer { done.signal() }
        guard let settings = try? store.load() else { output("Blocked: settings could not be read."); result.value = 3; return }
        if arguments == ["auto-switch", "check"] || arguments == ["auto-switch", "check", "--background"] {
            result.value = await runAutoSwitchCheck(providers: [providers["claude"]!, providers["codex"]!],
                                                    settings: settings, background: arguments.count == 3, output: output)
            return
        }
        guard arguments.count >= 3, arguments[0] == "auto-switch", let provider = providers[arguments[2]] else {
            output(usage); result.value = 2; return
        }
        guard let names = await provider.accounts()?.accounts.map(\.name) else {
            output("Blocked: saved accounts could not be read."); result.value = 3; return
        }
        switch Array(arguments[1...]) {
        case let command where command.count == 2 && command[0] == "order":
            AutoSwitchPlanner.ordered(names, by: settings.order(provider.kind)).forEach(output)
        case let command where command.count == 4 && command[0] == "move" && ["up", "down"].contains(command[3]):
            do {
                guard let order = try movePriority(provider.kind, alias: command[2], up: command[3] == "up",
                                                   in: names, store: store) else {
                    output("\(command[2]) is not a saved \(provider.name) account."); result.value = 3; return
                }
                order.forEach(output)
            } catch { output("Blocked: settings could not be saved."); result.value = 3 }
        default:
            output(usage); result.value = 2
        }
    }
    done.wait()
    return result.value
}

private final class ResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Int32 = 0
    var value: Int32 {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
