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
}

@MainActor
final class ControlStore: ObservableObject {
    struct SwitchAction {
        let provider: CLIProvider
        let previousID: String
    }

    private let accountData: [CLIProvider: [Account]] = [
        .claude: [
            Account(id: "claude-work", name: "Maya Work", status: .normal,
                    detail: "Pro plan", usedPercent: 42, resetText: "Resets in 4h"),
            Account(id: "claude-personal", name: "Personal", status: .warning(remaining: 9),
                    detail: "Max plan", usedPercent: 91, resetText: "Resets in 42m"),
            Account(id: "claude-lab", name: "Lab Sandbox",
                    status: .unavailable(label: "Unavailable"), detail: "Reconnect in Settings",
                    usedPercent: nil, resetText: "Not checked")
        ],
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

    @Published private(set) var activeAccountIDs: [CLIProvider: String] = [
        .claude: "claude-work", .codex: "codex-personal"
    ]
    @Published private(set) var lastSwitch: SwitchAction?
    @Published private(set) var switchMessage: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var updatedText = "Updated just now"
    @Published var isShowingSettings = false
    @Published var appearance: Appearance = .system
    @Published var automaticRefresh = true {
        didSet { configureAutomaticRefresh() }
    }
    @Published var limitWarnings = true
    private let refreshDelay: @Sendable () async -> Void
    private var automaticRefreshTask: Task<Void, Never>?

    init(refreshDelay: @escaping @Sendable () async -> Void = {
        try? await Task.sleep(nanoseconds: 700_000_000)
    }) {
        self.refreshDelay = refreshDelay
        configureAutomaticRefresh()
    }

    var showsMenuWarning: Bool {
        limitWarnings && accountData.values.joined().contains {
            if case .warning = $0.status { return true }
            return false
        }
    }
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
    @discardableResult
    func refresh() -> Task<Void, Never>? {
        guard !isRefreshing else { return nil }
        isRefreshing = true
        updatedText = "Refreshing usage…"
        return Task { @MainActor [weak self, refreshDelay] in
            await refreshDelay()
            guard !Task.isCancelled else { return }
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
                                     ? "Refreshing account usage" : "Refresh account usage"))
            .help(store.isRefreshing ? "Refreshing account usage" : "Refresh account usage")
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
                ForEach(CLIProvider.allCases) { provider in providerSection(provider) }
            }
            .padding(12)
        }
        .frame(maxHeight: 600)
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
                Label("Ready", systemImage: "checkmark.circle.fill")
                    .font(.caption2.weight(.medium)).foregroundStyle(.green)
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
                    settingCopy("Refresh automatically", help: "Check usage every 5 minutes.")
                }
                .toggleStyle(.switch)
                .padding(12)
                Divider()
                Toggle(isOn: $store.limitWarnings) {
                    settingCopy("Limit warnings", help: "Show a menu-bar alert below 15%.")
                }
                .toggleStyle(.switch)
                .padding(12)
            }
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
            Text("In-memory settings only · No credentials are read or stored")
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
            Text("Mock data only").foregroundStyle(.secondary)
        }
        .font(.caption2)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
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
