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

/// Checks every provider once and switches the ones with automatic switching on; one line per provider.
func runAutoSwitchCheck(providers: [AutoSwitchProvider], settings: AIControlSettings,
                        output: (String) -> Void) async -> Int32 {
    var status: Int32 = 0
    let threshold = settings.autoSwitch.thresholdPercent
    for provider in providers {
        guard settings.switching(provider.kind) else {
            output("\(provider.name): automatic switching is off.")
            continue
        }
        guard let listed = await provider.accounts() else {
            output("\(provider.name): saved accounts could not be read.")
            status = 3
            continue
        }
        let usage = await provider.usage()
        switch AutoSwitchPlanner.decide(current: listed.current, accounts: listed.accounts, usage: usage,
                                        order: settings.order(provider.kind), threshold: threshold) {
        case .stay:
            output("\(provider.name): \(listed.current ?? "the current account") is below \(threshold)%.")
        case .unknownCurrent:
            output("\(provider.name): the account in use or its usage is unknown; nothing changed.")
        case .noCandidate:
            output("\(provider.name): no other account is below \(threshold)% on every limit; nothing changed.")
        case .switchTo(let next):
            let current = listed.current ?? "the current account"
            if let refusal = await provider.use(next) {
                output("\(provider.name): not switched to \(next). \(refusal)")
                status = 3
            } else {
                output("\(provider.name): switched from \(current) to \(next) (\(current) reached \(threshold)% of a usage limit).")
            }
        }
    }
    return status
}

/// `auto-switch check`, `auto-switch order claude|codex`, `auto-switch move claude|codex <alias> up|down`.
func runAutoSwitch(arguments: [String], claude: ClaudeLoginAppAdapter = .configured(),
                   codex: CodexLoginAppAdapter = .configured(), store: SettingsStore = .live,
                   output: @escaping @Sendable (String) -> Void) -> Int32 {
    let usage = "Usage: AIControl auto-switch check | order claude|codex | move claude|codex <alias> up|down"
    let providers = ["claude": AutoSwitchProvider.claude(claude), "codex": .codex(codex)]
    let result = ResultBox()
    let done = DispatchSemaphore(value: 0)
    Task {
        defer { done.signal() }
        guard let settings = try? store.load() else { output("Blocked: settings could not be read."); result.value = 3; return }
        if arguments == ["auto-switch", "check"] {
            result.value = await runAutoSwitchCheck(providers: [providers["claude"]!, providers["codex"]!],
                                                    settings: settings, output: output)
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
            guard let order = AutoSwitchPlanner.moving(command[2], up: command[3] == "up", in: names,
                                                       by: settings.order(provider.kind)) else {
                output("\(command[2]) is not a saved \(provider.name) account."); result.value = 3; return
            }
            do {
                try store.update { $0.setOrder(provider.kind, order) }
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
