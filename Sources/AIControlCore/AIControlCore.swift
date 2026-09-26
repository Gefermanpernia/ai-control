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

enum CodexLoginListState: Equatable {
    case loading, unavailable, unreadable
    case loaded(CodexLoginListing)
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
    @Published private(set) var claudeLogins: ClaudeLoginListState = .loading
    @Published private(set) var claudeActivity: ClaudeLoginActivity = .idle
    @Published private(set) var claudeNotice: ClaudeLoginNotice?
    @Published private(set) var codexLogins: CodexLoginListState = .loading
    @Published private(set) var codexActivity: ClaudeLoginActivity = .idle
    @Published private(set) var codexNotice: ClaudeLoginNotice?
    @Published var isShowingSettings = false
    @Published var appearance: Appearance = .system
    private let claudeAdapter: ClaudeLoginAppAdapter
    private let codexAdapter: CodexLoginAppAdapter

    init(claudeLogins: ClaudeLoginAppAdapter = .configured(), codexLogins: CodexLoginAppAdapter = .configured()) {
        claudeAdapter = claudeLogins
        codexAdapter = codexLogins
    }

    /// Only real Claude trouble warrants the menu-bar alert; mock Codex usage never does.
    var showsMenuWarning: Bool { claudeNotice?.offersRecovery == true }
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
    func canSelectCodexLogin(_ login: CodexLoginListing.Login) -> Bool {
        guard codexActivity == .idle, case .loaded(let listing) = codexLogins else { return false }
        return listing.inUse != login.name
    }
    @discardableResult
    func reloadCodexLogins() -> Task<Void, Never>? {
        guard codexActivity == .idle else { return nil }
        codexActivity = .loading
        return Task { @MainActor in
            await applyCodexList()
            codexActivity = .idle
        }
    }
    @discardableResult
    func selectCodexLogin(_ alias: String) -> Task<Void, Never>? {
        guard case .loaded(let listing) = codexLogins,
              let login = listing.logins.first(where: { $0.name == alias }),
              canSelectCodexLogin(login) else { return nil }
        codexActivity = .switching(alias)
        codexNotice = nil
        return Task { @MainActor [codexAdapter] in
            switch await codexAdapter.use(alias: alias) {
            case .switched(let name):
                codexNotice = .init(text: "Switched Codex to \(name). Restart open Codex sessions to use it.", offersRecovery: false)
            case .blocked(let message):
                codexNotice = .init(text: message, offersRecovery: false)
            case .unavailable:
                codexNotice = .init(text: "Codex login switching is not available in this build.", offersRecovery: false)
            case .listed:
                break
            }
            await applyCodexList()
            codexActivity = .idle
        }
    }
    private func applyCodexList() async {
        switch await codexAdapter.list() {
        case .listed(let listing): codexLogins = .loaded(listing)
        case .unavailable: codexLogins = .unavailable
        default: codexLogins = .unreadable
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
            Divider()
            footer
        }
        .frame(width: 400)
        .preferredColorScheme(store.appearance.preferredColorScheme)
        .onChange(of: store.appearance) { NSApp.appearance = $0.appAppearance }
        .onAppear {
            NSApp.appearance = store.appearance.appAppearance
            store.reloadClaudeLogins()
            store.reloadCodexLogins()
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
                loginSection(.claude, loading: store.claudeActivity == .loading, reload: { store.reloadClaudeLogins() }) {
                    claudeContent
                } notice: {
                    store.claudeNotice.map { noticeView($0, recover: { store.recoverClaudeLogins() }) }
                }
                loginSection(.codex, loading: store.codexActivity == .loading, reload: { store.reloadCodexLogins() }) {
                    codexContent
                } notice: {
                    store.codexNotice.map { noticeView($0, recover: nil) }
                }
            }
            .padding(12)
        }
        // A menu-bar window sizes to ideal height; without one the list can open collapsed.
        .frame(minHeight: 360, idealHeight: 440, maxHeight: 600)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("CLI accounts")
    }

    private func loginSection<Content: View, Notice: View>(
        _ provider: CLIProvider, loading: Bool, reload: @escaping () -> Void,
        @ViewBuilder content: () -> Content, @ViewBuilder notice: () -> Notice
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(provider.mark)
                    .font(.caption2.weight(.semibold))
                    .frame(width: 24, height: 24)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.title).font(.caption.weight(.semibold))
                    Text("Saved logins · \(provider.switchDescription)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: reload) {
                    if loading { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") }
                }
                .buttonStyle(.borderless)
                .frame(width: 28, height: 28)
                .disabled(loading)
                .accessibilityLabel(Text("Reload saved \(provider.title) logins"))
                .help("Reload saved \(provider.title) logins")
            }
            content()
                .padding(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
            notice()
        }
    }

    @ViewBuilder private var claudeContent: some View {
        switch store.claudeLogins {
        case .loading:
            Label("Loading saved logins…", systemImage: "hourglass").loginMessageStyle()
        case .unavailable:
            Label("Login switching is off. Start AI Control with aic.", systemImage: "lock").loginMessageStyle()
        case .unreadable:
            Label("Saved logins could not be read.", systemImage: "exclamationmark.triangle").loginMessageStyle()
        case .loaded(let state) where state.aliases.isEmpty:
            Label("No saved logins. Sign in with Claude, then run aic save <name>.", systemImage: "tray")
                .loginMessageStyle()
        case .loaded(let state):
            VStack(spacing: 4) {
                ForEach(state.aliases, id: \.name) { alias in
                    let selected = state.lastSelectedHint == alias.name
                    let switching = store.claudeActivity == .switching(alias.name)
                    Button { store.selectClaudeLogin(alias.name) } label: {
                        SavedLoginRow(
                            name: alias.name, detail: alias.requiresReLogin ? "Re-login needed" : "Saved",
                            symbol: alias.requiresReLogin ? "xmark.octagon.fill" : "checkmark.circle.fill",
                            tint: alias.requiresReLogin ? .red : .green, selectedLabel: selected ? "Selected" : nil,
                            switching: switching, dimmed: alias.requiresReLogin
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!store.canSelectClaudeLogin(alias))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(alias.name + (alias.requiresReLogin ? ", re-login needed" : ", saved")
                                             + (selected ? ", selected" : "") + (switching ? ", switching" : "")))
                    .accessibilityHint(Text(alias.requiresReLogin
                                            ? "Sign in with Claude, then save this login again"
                                            : "Switches Claude Code to this saved login"))
                }
            }
        }
    }

    @ViewBuilder private var codexContent: some View {
        switch store.codexLogins {
        case .loading:
            Label("Loading saved logins…", systemImage: "hourglass").loginMessageStyle()
        case .unavailable:
            Label("Login switching is off. Start AI Control with aic.", systemImage: "lock").loginMessageStyle()
        case .unreadable:
            Label("Saved logins could not be read.", systemImage: "exclamationmark.triangle").loginMessageStyle()
        case .loaded(let listing) where listing.logins.isEmpty:
            Label("No saved logins. Run codex login, then aic codex save <name>.", systemImage: "tray")
                .loginMessageStyle()
        case .loaded(let listing):
            VStack(spacing: 4) {
                ForEach(listing.logins, id: \.name) { login in codexRow(login, inUse: listing.inUse == login.name) }
            }
        }
    }

    private func codexRow(_ login: CodexLoginListing.Login, inUse: Bool) -> some View {
        let switching = store.codexActivity == .switching(login.name)
        let email = login.email ?? "Unknown email"
        let state = (inUse ? ", in use" : "") + (switching ? ", switching" : "")
        return Button { store.selectCodexLogin(login.name) } label: {
            SavedLoginRow(
                name: login.name, detail: email, symbol: "person.crop.circle", tint: .secondary,
                selectedLabel: inUse ? "In use" : nil, switching: switching, dimmed: false
            )
        }
        .buttonStyle(.plain)
        .disabled(!store.canSelectCodexLogin(login))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(login.name), \(email)\(state)"))
        .accessibilityHint(Text("Switches Codex to this saved login"))
    }

    private func noticeView(_ notice: ClaudeLoginNotice, recover: (() -> Void)?) -> some View {
        HStack(spacing: 8) {
            Label(notice.text, systemImage: notice.offersRecovery ? "exclamationmark.triangle.fill" : "info.circle")
                .font(.caption)
                .foregroundStyle(notice.offersRecovery ? Color.orange : Color.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            if notice.offersRecovery, let recover {
                Button("Run recovery", action: recover)
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
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Appearance").font(.body.weight(.medium))
                    Text("Preview the popover in a system theme.").font(.caption2).foregroundStyle(.secondary)
                }
                Picker("Appearance", selection: $store.appearance) {
                    ForEach(Appearance.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Appearance")
            }
            .padding(12)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
        }
        .padding(12)
    }

    private var footer: some View {
        Text("Claude sessions follow a switch · Restart open Codex sessions")
            .font(.caption2).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
    }
}

struct SavedLoginRow: View {
    let name: String
    let detail: String
    let symbol: String
    let tint: Color
    let selectedLabel: String?
    let switching: Bool
    let dimmed: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(name).font(.body.weight(.medium)).lineLimit(1)
                    if let selectedLabel {
                        Label(selectedLabel, systemImage: "checkmark")
                            .font(.caption2.weight(.semibold)).foregroundStyle(.tint)
                    }
                }
                Label(detail, systemImage: symbol).foregroundStyle(tint).font(.caption2).lineLimit(1)
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
        .background(selectedLabel != nil ? Color.accentColor.opacity(0.10) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .opacity(dimmed ? 0.62 : 1)
        .contentShape(Rectangle())
    }
}

private extension View {
    func loginMessageStyle() -> some View {
        font(.caption).foregroundStyle(.secondary).padding(8).fixedSize(horizontal: false, vertical: true)
    }
}
