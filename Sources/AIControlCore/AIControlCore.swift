import AppKit
import SwiftUI

enum CLIProvider: String, CaseIterable, Identifiable {
    case claude, codex

    var id: Self { self }
    var title: String { self == .claude ? "Claude CLI" : "Codex CLI" }
    var mark: String { self == .claude ? "CL" : "CX" }
    var switchDescription: String {
        self == .claude ? "switches Claude Code" : "switches OpenAI Codex"
    }
}

enum AccountStatus {
    case normal
    case warning(remaining: Int)
    case unavailable(label: String)

    var label: String {
        switch self {
        case .normal: return "Normal"
        case .warning(let remaining): return "\(remaining)% left"
        case .unavailable(let label): return label
        }
    }
    var symbol: String {
        switch self {
        case .normal: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .unavailable: return "xmark.octagon.fill"
        }
    }
    var color: Color {
        switch self {
        case .normal: return .green
        case .warning: return .orange
        case .unavailable: return .red
        }
    }
    var isSelectable: Bool {
        if case .unavailable = self { return false }
        return true
    }
}

struct Account: Identifiable {
    let id: String
    let name: String
    let status: AccountStatus
    let detail: String
    let usedPercent: Int?
    let resetText: String

    var usageText: String { usedPercent.map { "\($0)% used" } ?? "—" }
    func accessibilityLabel(active: Bool) -> String {
        let usage = usedPercent.map { ", \($0) percent used" } ?? ""
        return "\(name), \(status.label), \(detail)\(usage), \(resetText)\(active ? ", active" : "")"
    }
}

enum Appearance: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: Self { self }
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
    /// Menu-bar windows ignore `preferredColorScheme`, so the app appearance carries the choice.
    var appAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

enum ClaudeLoginListState: Equatable {
    case loading, unavailable, unreadable
    case loaded(ClaudeLoginAppState)
}

enum ClaudeLoginActivity: Equatable {
    case idle, loading, recovering
    case switching(String)
}

struct ClaudeLoginNotice: Equatable {
    let text: String
    let offersRecovery: Bool
}

@MainActor
final class ControlStore: ObservableObject {
    struct SwitchAction {
        let provider: CLIProvider
        let previousID: String
    }

    private let accountData: [CLIProvider: [Account]] = [
        .codex: [
            Account(id: "codex-personal", name: "Personal Plus", status: .normal,
                    detail: "Plus plan", usedPercent: 67, resetText: "Resets in 2h"),
            Account(id: "codex-consulting", name: "Consulting", status: .warning(remaining: 12),
                    detail: "Team seat", usedPercent: 88, resetText: "Resets in 1h"),
            Account(id: "codex-playground", name: "Playground",
                    status: .unavailable(label: "Usage unavailable"), detail: "Try refresh",
                    usedPercent: nil, resetText: "Last seen 1d ago")
        ]
    ]

    @Published private(set) var activeAccountIDs: [CLIProvider: String] = [.codex: "codex-personal"]
    @Published private(set) var claudeLogins: ClaudeLoginListState = .loading
    @Published private(set) var claudeActivity: ClaudeLoginActivity = .idle
    @Published private(set) var claudeNotice: ClaudeLoginNotice?
    @Published private(set) var lastSwitch: SwitchAction?
    @Published private(set) var switchMessage: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var updatedText = "Updated just now"
    @Published var isShowingSettings = false
    @Published var appearance: Appearance = .system
    @Published var automaticRefresh = true {
        didSet { configureAutomaticRefresh() }
    }
    private let refreshDelay: @Sendable () async -> Void
    private var automaticRefreshTask: Task<Void, Never>?
    private let claudeAdapter: ClaudeLoginAppAdapter

    init(refreshDelay: @escaping @Sendable () async -> Void = {
        try? await Task.sleep(nanoseconds: 700_000_000)
    }, claudeLogins: ClaudeLoginAppAdapter = .configured()) {
        self.refreshDelay = refreshDelay
        claudeAdapter = claudeLogins
        configureAutomaticRefresh()
    }

    /// Only real Claude trouble warrants the menu-bar alert; mock Codex usage never does.
    var showsMenuWarning: Bool { claudeNotice?.offersRecovery == true }
    func accounts(for provider: CLIProvider) -> [Account] { accountData[provider] ?? [] }
    func isActive(_ account: Account, for provider: CLIProvider) -> Bool {
        activeAccountIDs[provider] == account.id
    }
    func select(_ account: Account, for provider: CLIProvider) {
        guard let account = accounts(for: provider).first(where: { $0.id == account.id }),
              account.status.isSelectable,
              let previousID = activeAccountIDs[provider], previousID != account.id else { return }
        activeAccountIDs[provider] = account.id
        lastSwitch = SwitchAction(provider: provider, previousID: previousID)
        switchMessage = "✓ \(provider.title) switched to \(account.name)"
    }
    func undoLastSwitch() {
        guard let action = lastSwitch,
              let account = accounts(for: action.provider).first(where: { $0.id == action.previousID }),
              account.status.isSelectable else { return }
        activeAccountIDs[action.provider] = action.previousID
        switchMessage = "↶ \(action.provider.title) restored to \(account.name)"
        lastSwitch = nil
    }
    func canSelectClaudeLogin(_ alias: ClaudeLoginAppState.Alias) -> Bool {
        claudeActivity == .idle && !alias.requiresReLogin
    }
    @discardableResult
    func reloadClaudeLogins() -> Task<Void, Never>? {
        guard claudeActivity == .idle else { return nil }
        claudeActivity = .loading
        return Task { @MainActor in
            await applyClaudeList()
            claudeActivity = .idle
        }
    }
    @discardableResult
    func selectClaudeLogin(_ alias: String) -> Task<Void, Never>? {
        guard case .loaded(let state) = claudeLogins,
              let saved = state.aliases.first(where: { $0.name == alias }),
              canSelectClaudeLogin(saved) else { return nil }
        claudeActivity = .switching(alias)
        claudeNotice = nil
        // The adapter finishes every started switch; cancelling this task never hides its outcome.
        return Task { @MainActor [claudeAdapter] in
            claudeNotice = Self.notice(for: await claudeAdapter.use(alias: alias), alias: alias)
            await applyClaudeList()
            claudeActivity = .idle
        }
    }
    @discardableResult
    func recoverClaudeLogins() -> Task<Void, Never>? {
        guard claudeActivity == .idle else { return nil }
        claudeActivity = .recovering
        claudeNotice = nil
        return Task { @MainActor [claudeAdapter] in
            claudeNotice = Self.notice(for: await claudeAdapter.recover(), alias: nil)
            await applyClaudeList()
            claudeActivity = .idle
        }
    }
    private func applyClaudeList() async {
        switch await claudeAdapter.list() {
        case .listed(let state): claudeLogins = .loaded(state)
        case .backendUnavailable: claudeLogins = .unavailable
        default: claudeLogins = .unreadable
        }
    }
    private static func notice(for result: ClaudeLoginAppResult, alias: String?) -> ClaudeLoginNotice? {
        let name = alias ?? "The login"
        switch result {
        case .listed: return nil
        case .verifiedApplied(let applied):
            return .init(text: "Switched Claude to \(applied).", offersRecovery: false)
        case .recoveryChecked:
            return .init(text: "Recovery check finished. Choose a saved login to switch.", offersRecovery: false)
        case .refused:
            return .init(text: "Not switched. Claude or its files changed; close Claude and try again.", offersRecovery: false)
        case .claudeRunning:
            return .init(text: "\(alias == nil ? "Recovery not run" : "Not switched"). Quit every Claude Code session, then try again.",
                         offersRecovery: false)
        case .unknownAlias: return .init(text: "\(name) is no longer a saved login.", offersRecovery: false)
        case .reLoginNeeded:
            return .init(text: "\(name) needs a new login. Sign in with Claude, then save it again.", offersRecovery: false)
        case .recoveryRequired:
            return .init(text: "A previous switch did not finish. Run recovery before switching.", offersRecovery: true)
        case .backendUnavailable:
            return .init(text: "Claude login switching is not available in this build.", offersRecovery: false)
        case .postCommitCleanupUncertain:
            return .init(text: "\(name) may be applied, but cleanup was not confirmed. Run recovery to check.", offersRecovery: true)
        case .unverifiedFailure:
            return .init(text: alias == nil
                         ? "Recovery could not be verified. Credentials may still need recovery."
                         : "The switch could not be verified and credentials may have changed. Run recovery to check.",
                         offersRecovery: true)
        }
    }
    @discardableResult
    func refresh() -> Task<Void, Never>? {
        guard !isRefreshing else { return nil }
        let previousUpdatedText = updatedText
        isRefreshing = true
        updatedText = "Refreshing usage…"
        return Task { @MainActor [weak self, refreshDelay, previousUpdatedText] in
            await refreshDelay()
            guard !Task.isCancelled else {
                self?.isRefreshing = false
                self?.updatedText = previousUpdatedText
                return
            }
            self?.isRefreshing = false
            self?.updatedText = "Updated just now"
        }
    }
    private func configureAutomaticRefresh() {
        automaticRefreshTask?.cancel()
        guard automaticRefresh else { return }
        automaticRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000_000)
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }
}

/// Starts the menu-bar app.
///
/// This is the only symbol the executable target needs, so every other type in
/// this module stays internal and is reached from tests via `@testable import`.
@MainActor
public func runAIControl() {
    AIControlApp.main()
}

struct AIControlApp: App {
    @StateObject private var store = ControlStore()

    var body: some Scene {
        MenuBarExtra {
            ControlView().environmentObject(store)
        } label: {
            Label("AI Control", systemImage: store.showsMenuWarning
                  ? "exclamationmark.triangle.fill" : "terminal.fill")
        }
        .menuBarExtraStyle(.window)
    }
}

struct ControlView: View {
    @EnvironmentObject private var store: ControlStore

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.isShowingSettings { settings } else { accountList }
            if let message = store.switchMessage, !store.isShowingSettings { switchNotice(message) }
            Divider()
            footer
        }
        .frame(width: 400)
        .preferredColorScheme(store.appearance.preferredColorScheme)
        .onChange(of: store.appearance) { NSApp.appearance = $0.appAppearance }
        .onAppear {
            NSApp.appearance = store.appearance.appAppearance
            store.reloadClaudeLogins()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal.fill")
                .font(.headline)
                .foregroundStyle(.tint)
                .frame(width: 32, height: 32)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("AI Control").font(.headline)
                Text("Choose the account each CLI uses")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: { store.refresh() }) {
                if store.isRefreshing { ProgressView().controlSize(.small) }
                else { Image(systemName: "arrow.clockwise") }
            }
            .buttonStyle(.borderless)
            .frame(width: 28, height: 28)
            .disabled(store.isRefreshing)
            .accessibilityLabel(Text(store.isRefreshing
                                     ? "Refreshing Codex mock usage" : "Refresh Codex mock usage"))
            .help(store.isRefreshing ? "Refreshing Codex mock usage" : "Refresh Codex mock usage")
            Button { store.isShowingSettings.toggle() } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .frame(width: 28, height: 28)
            .accessibilityLabel(Text(store.isShowingSettings ? "Close settings" : "Open settings"))
            .help(store.isShowingSettings ? "Close settings" : "Open settings")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var accountList: some View {
        ScrollView {
            VStack(spacing: 12) {
                claudeSection
                providerSection(.codex)
            }
            .padding(12)
        }
        // A menu-bar window sizes to ideal height; without one the list can open collapsed.
        .frame(minHeight: 420, idealHeight: 520, maxHeight: 600)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("CLI accounts")
    }

    private func providerSection(_ provider: CLIProvider) -> some View {
        let accounts = store.accounts(for: provider)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(provider.mark)
                    .font(.caption2.weight(.semibold))
                    .frame(width: 24, height: 24)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.title).font(.caption.weight(.semibold))
                    Text("\(accounts.count) accounts · \(provider.switchDescription)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Label("Mock data", systemImage: "info.circle")
                    .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
            }
            VStack(spacing: 4) {
                ForEach(accounts) { account in
                    let active = store.isActive(account, for: provider)
                    Button { store.select(account, for: provider) } label: {
                        AccountRow(account: account, active: active)
                    }
                    .buttonStyle(.plain)
                    .disabled(!account.status.isSelectable)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(account.accessibilityLabel(active: active)))
                    .accessibilityHint(Text(account.status.isSelectable
                                            ? "Selects this account for \(provider.title)" : account.detail))
                }
            }
            .padding(4)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
        }
    }

    private var claudeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(CLIProvider.claude.mark)
                    .font(.caption2.weight(.semibold))
                    .frame(width: 24, height: 24)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(CLIProvider.claude.title).font(.caption.weight(.semibold))
                    Text("Saved logins · \(CLIProvider.claude.switchDescription)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Button { store.reloadClaudeLogins() } label: {
                    if store.claudeActivity == .loading { ProgressView().controlSize(.small) }
                    else { Image(systemName: "arrow.clockwise") }
                }
                .buttonStyle(.borderless)
                .frame(width: 28, height: 28)
                .disabled(store.claudeActivity != .idle)
                .accessibilityLabel(Text("Reload saved Claude logins"))
                .help("Reload saved Claude logins")
            }
            claudeContent
                .padding(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
            if let notice = store.claudeNotice { claudeNoticeView(notice) }
        }
    }

    @ViewBuilder private var claudeContent: some View {
        switch store.claudeLogins {
        case .loading:
            Label("Loading saved logins…", systemImage: "hourglass").claudeMessageStyle()
        case .unavailable:
            Label("Login switching is not available in this build.", systemImage: "lock")
                .claudeMessageStyle()
        case .unreadable:
            Label("Saved logins could not be read.", systemImage: "exclamationmark.triangle")
                .claudeMessageStyle()
        case .loaded(let state) where state.aliases.isEmpty:
            Label("No saved logins. In Terminal, sign in with Claude, then run AIControl claude-login save <alias>.",
                  systemImage: "tray").claudeMessageStyle()
        case .loaded(let state):
            VStack(spacing: 4) {
                ForEach(state.aliases, id: \.name) { alias in
                    let lastSelected = state.lastSelectedHint == alias.name
                    let switching = store.claudeActivity == .switching(alias.name)
                    Button { store.selectClaudeLogin(alias.name) } label: {
                        SavedLoginRow(alias: alias, lastSelected: lastSelected, switching: switching)
                    }
                    .buttonStyle(.plain)
                    .disabled(!store.canSelectClaudeLogin(alias))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(alias.name + (alias.requiresReLogin ? ", re-login needed" : ", saved")
                                             + (lastSelected ? ", last selected" : "")
                                             + (switching ? ", switching" : "")))
                    .accessibilityHint(Text(alias.requiresReLogin
                                            ? "Sign in with Claude, then save this login again"
                                            : "Switches Claude Code to this saved login"))
                }
            }
        }
    }

    private func claudeNoticeView(_ notice: ClaudeLoginNotice) -> some View {
        HStack(spacing: 8) {
            Label(notice.text, systemImage: notice.offersRecovery ? "exclamationmark.triangle.fill" : "info.circle")
                .font(.caption)
                .foregroundStyle(notice.offersRecovery ? Color.orange : Color.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            if notice.offersRecovery {
                Button("Run recovery") { store.recoverClaudeLogins() }
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(store.claudeActivity != .idle)
            }
        }
        .padding(8)
        .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button { store.isShowingSettings = false } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                Text("Settings").font(.headline)
            }
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    settingCopy("Appearance", help: "Preview the popover in a system theme.")
                    Picker("Appearance", selection: $store.appearance) {
                        ForEach(Appearance.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .accessibilityLabel("Appearance")
                }
                .padding(12)
                Divider()
                Toggle(isOn: $store.automaticRefresh) {
                    settingCopy("Refresh automatically", help: "Check Codex mock usage every 5 minutes.")
                }
                .toggleStyle(.switch)
                .padding(12)
            }
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
            Text("In-memory settings only")
                .font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
        }
        .padding(12)
    }

    private func settingCopy(_ title: String, help: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.body.weight(.medium))
            Text(help).font(.caption2).foregroundStyle(.secondary)
        }
    }
    private func switchNotice(_ message: String) -> some View {
        HStack(spacing: 8) {
            Text(message).font(.caption).foregroundStyle(.tint)
            Spacer()
            if store.lastSwitch != nil {
                Button("Undo", action: store.undoLastSwitch)
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(8)
        .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .accessibilityElement(children: .contain)
    }
    private var footer: some View {
        HStack(spacing: 8) {
            Label(store.updatedText, systemImage: store.isRefreshing
                  ? "arrow.clockwise" : "checkmark.circle.fill")
                .foregroundStyle(store.isRefreshing ? Color.accentColor : Color.green)
            Spacer()
            Text("Codex data is mock only").foregroundStyle(.secondary)
        }
        .font(.caption2)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

struct SavedLoginRow: View {
    let alias: ClaudeLoginAppState.Alias
    let lastSelected: Bool
    let switching: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(alias.name).font(.body.weight(.medium)).lineLimit(1)
                    if lastSelected {
                        Label("Last selected", systemImage: "clock.arrow.circlepath")
                            .font(.caption2.weight(.semibold)).foregroundStyle(.tint)
                    }
                }
                Group {
                    if alias.requiresReLogin {
                        Label("Re-login needed", systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                    } else {
                        Label("Saved", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                }
                .font(.caption2)
            }
            Spacer(minLength: 8)
            if switching {
                ProgressView().controlSize(.small)
                Text("Switching…").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .opacity(alias.requiresReLogin ? 0.62 : 1)
        .contentShape(Rectangle())
    }
}

private extension View {
    func claudeMessageStyle() -> some View {
        font(.caption).foregroundStyle(.secondary).padding(8).fixedSize(horizontal: false, vertical: true)
    }
}

struct AccountRow: View {
    let account: Account
    let active: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(account.name).font(.body.weight(.medium)).lineLimit(1)
                    if active {
                        Label("Active", systemImage: "checkmark")
                            .font(.caption2.weight(.semibold)).foregroundStyle(.tint)
                    }
                }
                HStack(spacing: 4) {
                    Label(account.status.label, systemImage: account.status.symbol)
                        .foregroundStyle(account.status.color)
                    Text("· \(account.detail)").foregroundStyle(.secondary)
                }
                .font(.caption2)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(account.usageText).font(.caption.monospacedDigit().weight(.medium))
                if let used = account.usedPercent {
                    ProgressView(value: Double(used), total: 100)
                        .progressViewStyle(.linear)
                        .tint(account.status.color)
                        .accessibilityLabel(Text("\(account.name) usage"))
                        .accessibilityValue(Text("\(used) percent"))
                } else {
                    Capsule().fill(.tertiary).frame(height: 4).accessibilityHidden(true)
                }
                Text(account.resetText)
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            .frame(width: 92)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .background(active ? Color.accentColor.opacity(0.10) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .leading) {
            if active {
                Rectangle().fill(Color.accentColor).frame(width: 3).accessibilityHidden(true)
            }
        }
        .opacity(account.status.isSelectable ? 1 : 0.62)
        .contentShape(Rectangle())
    }
}
