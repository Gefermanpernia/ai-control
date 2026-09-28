#if os(macOS)
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

    /// Desktop apps whose icon represents the provider, in order of preference.
    var appBundleIdentifiers: [String] {
        self == .claude ? ["com.anthropic.claudefordesktop"] : ["com.openai.codex", "com.openai.chat"]
    }

    /// The icon of the provider's installed app. AI Control ships no provider logos; without the app,
    /// the section shows its monogram instead.
    func installedAppIcon(workspace: NSWorkspace = .shared) -> NSImage? {
        appBundleIdentifiers.lazy.compactMap { workspace.urlForApplication(withBundleIdentifier: $0) }
            .first.map { workspace.icon(forFile: $0.path) }
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
    case idle, loading, recovering, signingIn
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
    @Published private(set) var claudeUsage: [String: LoginUsageResult] = [:]
    @Published private(set) var codexUsage: [String: LoginUsageResult] = [:]
    @Published private(set) var monitors: [LoginStatus.Monitor] = []
    @Published private(set) var isLoadingMonitors = false
    @Published private(set) var isLoadingClaudeUsage = false
    @Published private(set) var isLoadingCodexUsage = false
    @Published var isShowingSettings = false
    @Published var appearance: Appearance = .system
    private let claudeAdapter: ClaudeLoginAppAdapter
    private let codexAdapter: CodexLoginAppAdapter
    private let monitorSource: UsageMonitors
    let providerIcons: [CLIProvider: NSImage]

    init(
        claudeLogins: ClaudeLoginAppAdapter = .configured(), codexLogins: CodexLoginAppAdapter = .configured(),
        appIcon: (CLIProvider) -> NSImage? = { $0.installedAppIcon() },
        monitors: UsageMonitors = .live
    ) {
        claudeAdapter = claudeLogins
        codexAdapter = codexLogins
        monitorSource = monitors
        providerIcons = Dictionary(uniqueKeysWithValues: CLIProvider.allCases.compactMap { provider in
            appIcon(provider).map { (provider, $0) }
        })
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
    private var lastOpened: Date?
    private var isDemo = false

    /// Example accounts for screenshots; a demo store never loads or changes real logins.
    static func demo(now: Date = Date(), monitors: UsageMonitors = .live) -> ControlStore {
        // Screenshots stay free of provider logos, so the demo never shows installed app icons.
        let store = ControlStore(claudeLogins: ClaudeLoginAppAdapter(), codexLogins: CodexLoginAppAdapter(),
                                 appIcon: { _ in nil }, monitors: monitors)
        store.isDemo = true
        func usage(_ windows: [(String, Double, Double)], resets: Int? = nil) -> LoginUsageResult {
            .usage(.init(windows: windows.map { .init(label: $0.0, usedPercent: $0.1, resetsAt: now.addingTimeInterval($0.2 * 3600)) },
                         resetsAvailable: resets, fetchedAt: now))
        }
        store.claudeLogins = .loaded(.init(aliases: [
            .init(name: "client", requiresReLogin: false), .init(name: "personal", requiresReLogin: false),
            .init(name: "work", requiresReLogin: false)
        ], lastSelectedHint: "work"))
        store.claudeUsage = [
            "client": usage([("5h", 91, 1.5), ("Week", 74, 50)]),
            "personal": usage([("5h", 8, 3), ("Week", 21, 100)]),
            "work": usage([("5h", 42, 2), ("Week", 63, 75)])
        ]
        store.codexLogins = .loaded(.init(logins: [
            .init(name: "personal", email: "personal@example.com"), .init(name: "work", email: "work@example.com")
        ], inUse: "work"))
        store.codexUsage = [
            "personal": usage([("Week", 4, 140)], resets: 3),
            "work": usage([("5h", 12, 4), ("Week", 35, 90)], resets: 2)
        ]
        return store
    }

    /// Loads saved logins and their usage when the window opens; usage is never fetched in the background.
    func windowOpened(now: Date = Date()) {
        guard !isDemo else { return }
        reloadClaudeLogins()
        reloadCodexLogins()
        if let lastOpened, now.timeIntervalSince(lastOpened) < 30 { return }
        lastOpened = now
        refreshClaudeUsage()
        refreshCodexUsage()
        refreshMonitors()
    }
    @discardableResult
    func refreshMonitors() -> Task<Void, Never>? {
        guard !isDemo, !isLoadingMonitors else { return nil }
        isLoadingMonitors = true
        return Task { @MainActor [monitorSource] in
            monitors = await monitorSource.monitors(includeUsage: true)
            isLoadingMonitors = false
        }
    }
    @discardableResult
    func refreshClaudeUsage() -> Task<Void, Never>? {
        guard !isLoadingClaudeUsage else { return nil }
        isLoadingClaudeUsage = true
        return Task { @MainActor [claudeAdapter] in
            claudeUsage = await claudeAdapter.usage()
            isLoadingClaudeUsage = false
        }
    }
    @discardableResult
    func refreshCodexUsage() -> Task<Void, Never>? {
        guard !isLoadingCodexUsage else { return nil }
        isLoadingCodexUsage = true
        return Task { @MainActor [codexAdapter] in
            codexUsage = await codexAdapter.usage()
            isLoadingCodexUsage = false
        }
    }
    @discardableResult
    func addClaudeLogin(name: String, email: String?) -> Task<Void, Never>? {
        guard claudeActivity == .idle else { return nil }
        claudeActivity = .signingIn
        claudeNotice = nil
        let email = email.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        return Task { @MainActor [claudeAdapter] in
            claudeNotice = Self.notice(for: await claudeAdapter.add(alias: name, email: email))
            await applyClaudeList()
            claudeActivity = .idle
        }
    }
    @discardableResult
    func renameClaudeLogin(_ alias: String, to newAlias: String) -> Task<Void, Never>? {
        guard claudeActivity == .idle else { return nil }
        claudeActivity = .loading
        return Task { @MainActor [claudeAdapter] in
            let result = await claudeAdapter.rename(alias: alias, to: newAlias)
            if case .done = result { claudeUsage[newAlias] = claudeUsage.removeValue(forKey: alias) }
            claudeNotice = Self.notice(for: result)
            await applyClaudeList()
            claudeActivity = .idle
        }
    }
    @discardableResult
    func addCodexLogin(name: String) -> Task<Void, Never>? {
        guard codexActivity == .idle else { return nil }
        codexActivity = .signingIn
        codexNotice = nil
        return Task { @MainActor [codexAdapter] in
            codexNotice = Self.notice(for: await codexAdapter.add(alias: name))
            await applyCodexList()
            codexActivity = .idle
        }
    }
    @discardableResult
    func renameCodexLogin(_ alias: String, to newAlias: String) -> Task<Void, Never>? {
        guard codexActivity == .idle else { return nil }
        codexActivity = .loading
        return Task { @MainActor [codexAdapter] in
            let result = await codexAdapter.rename(alias: alias, to: newAlias)
            if case .done = result { codexUsage[newAlias] = codexUsage.removeValue(forKey: alias) }
            codexNotice = Self.notice(for: result)
            await applyCodexList()
            codexActivity = .idle
        }
    }
    private static func notice(for result: LoginEditResult) -> ClaudeLoginNotice {
        switch result {
        case .done(let text), .blocked(let text): return .init(text: text, offersRecovery: false)
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
                codexNotice = .init(text: "Switched Codex to \(name).", offersRecovery: false)
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
    private struct RenameTarget: Equatable {
        let provider: CLIProvider
        let alias: String
    }

    @EnvironmentObject private var store: ControlStore
    @State private var adding: CLIProvider?

    init(adding: CLIProvider? = nil) { _adding = State(initialValue: adding) }
    @State private var newName = ""
    @State private var newEmail = ""
    @State private var renaming: RenameTarget?
    @State private var renameDraft = ""
    @State private var contentHeight: CGFloat = 360

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
            store.windowOpened()
        }
        // The menu-bar window is reused, so each time it opens it becomes key again.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            store.windowOpened()
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
                loginSection(.claude, loading: store.claudeActivity == .loading || store.isLoadingClaudeUsage,
                             canAdd: store.claudeActivity == .idle, reload: { store.reloadClaudeLogins(); store.refreshClaudeUsage(); store.refreshMonitors() }) {
                    claudeContent
                    signInArea(.claude)
                } notice: {
                    store.claudeNotice.map { noticeView($0, recover: { store.recoverClaudeLogins() }) }
                }
                loginSection(.codex, loading: store.codexActivity == .loading || store.isLoadingCodexUsage,
                             canAdd: store.codexActivity == .idle, reload: { store.reloadCodexLogins(); store.refreshCodexUsage(); store.refreshMonitors() }) {
                    codexContent
                    signInArea(.codex)
                } notice: {
                    store.codexNotice.map { noticeView($0, recover: nil) }
                }
                if !store.monitors.isEmpty { monitorSection }
            }
            .padding(12)
            .background(GeometryReader { Color.clear.preference(key: ContentHeightKey.self, value: $0.size.height) })
        }
        // The window fits its content up to a limit; beyond it the list scrolls.
        .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
        .frame(height: min(max(contentHeight, 160), 720))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("CLI accounts")
    }

    private func loginSection<Content: View, Notice: View>(
        _ provider: CLIProvider, loading: Bool, canAdd: Bool, reload: @escaping () -> Void,
        @ViewBuilder content: () -> Content, @ViewBuilder notice: () -> Notice
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Group {
                    if let icon = store.providerIcons[provider] {
                        Image(nsImage: icon).resizable().interpolation(.high).frame(width: 24, height: 24)
                    } else {
                        Text(provider.mark)
                            .font(.caption2.weight(.semibold))
                            .frame(width: 24, height: 24)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.title).font(.caption.weight(.semibold))
                    Text("Saved logins · \(provider.switchDescription)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    newName = ""
                    newEmail = ""
                    adding = adding == provider ? nil : provider
                } label: { Image(systemName: "plus") }
                .buttonStyle(.borderless)
                .frame(width: 28, height: 28)
                .disabled(!canAdd)
                .accessibilityLabel(Text("Add a \(provider.title) account"))
                .help("Add a \(provider.title) account")
                Button(action: reload) {
                    if loading { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") }
                }
                .buttonStyle(.borderless)
                .frame(width: 28, height: 28)
                .disabled(loading)
                .accessibilityLabel(Text("Reload saved \(provider.title) logins and usage"))
                .help("Reload saved \(provider.title) logins and usage")
            }
            VStack(spacing: 4) { content() }
                .padding(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
            notice()
        }
    }

    private var monitorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Monitors").font(.caption.weight(.semibold))
                Spacer()
                if store.isLoadingMonitors { ProgressView().controlSize(.small).accessibilityLabel("Loading monitors") }
            }
            VStack(spacing: 4) {
                ForEach(store.monitors, id: \.id) { monitor in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(monitor.name).font(.body.weight(.medium))
                        if let error = monitor.error {
                            Text(error).font(.caption2).foregroundStyle(.secondary)
                        }
                        if let windows = monitor.usage?.windows {
                            ForEach(windows, id: \.label) { window in
                                UsageWindowBar(label: window.label, usedPercent: window.usedPercent, resetsAt: window.resetsAt)
                            }
                        }
                        if let models = monitor.models {
                            if models.isEmpty {
                                Text("No usage this month").font(.caption2).foregroundStyle(.secondary)
                            } else {
                                ForEach(models, id: \.model) { model in
                                    if let percent = model.usedPercent {
                                        UsageWindowBar(label: model.model, usedPercent: percent, resetsAt: model.resetsAt)
                                    } else {
                                        Text("\(model.model) · \(TokenCountFormatter.compact(model.totalTokens)) tokens")
                                            .font(.caption2).foregroundStyle(.secondary)
                                            .accessibilityLabel("\(model.model), \(TokenCountFormatter.compact(model.totalTokens)) tokens")
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(monitor.name)
                }
            }
            .padding(4)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
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
                    if renaming == RenameTarget(provider: .claude, alias: alias.name) {
                        renameField(.claude, alias: alias.name)
                    } else {
                        claudeRow(alias, selected: state.lastSelectedHint == alias.name)
                    }
                }
            }
        }
    }

    private func claudeRow(_ alias: ClaudeLoginAppState.Alias, selected: Bool) -> some View {
        let switching = store.claudeActivity == .switching(alias.name)
        let status = alias.requiresReLogin ? ", re-login needed" : ", saved"
        return Button { store.selectClaudeLogin(alias.name) } label: {
            SavedLoginRow(
                name: alias.name, detail: alias.requiresReLogin ? "Re-login needed" : "Saved",
                symbol: alias.requiresReLogin ? "xmark.octagon.fill" : "checkmark.circle.fill",
                tint: alias.requiresReLogin ? .red : .green, selectedLabel: selected ? "Selected" : nil,
                switching: switching, dimmed: alias.requiresReLogin, usage: store.claudeUsage[alias.name]
            )
        }
        .buttonStyle(.plain)
        .disabled(!store.canSelectClaudeLogin(alias))
        .contextMenu { renameButton(.claude, alias: alias.name) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(alias.name + status + (selected ? ", selected" : "") + (switching ? ", switching" : "")))
        .accessibilityHint(Text(alias.requiresReLogin
                                ? "Sign in with Claude, then save this login again"
                                : "Switches Claude Code to this saved login"))
        .accessibilityAction(named: Text("Rename")) { startRenaming(.claude, alias: alias.name) }
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
                ForEach(listing.logins, id: \.name) { login in
                    if renaming == RenameTarget(provider: .codex, alias: login.name) {
                        renameField(.codex, alias: login.name)
                    } else {
                        codexRow(login, inUse: listing.inUse == login.name)
                    }
                }
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
                selectedLabel: inUse ? "In use" : nil, switching: switching, dimmed: false, usage: store.codexUsage[login.name]
            )
        }
        .buttonStyle(.plain)
        // Clicking the login already in use does nothing; disabling it would only dim the row.
        .disabled(store.codexActivity != .idle)
        .contextMenu { renameButton(.codex, alias: login.name) }
        .accessibilityAction(named: Text("Rename")) { startRenaming(.codex, alias: login.name) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(login.name), \(email)\(state)"))
        .accessibilityHint(Text("Switches Codex to this saved login"))
    }

    private func renameButton(_ provider: CLIProvider, alias: String) -> some View {
        Button("Rename…") { startRenaming(provider, alias: alias) }
    }

    private func startRenaming(_ provider: CLIProvider, alias: String) {
        renameDraft = alias
        renaming = RenameTarget(provider: provider, alias: alias)
    }

    private func renameField(_ provider: CLIProvider, alias: String) -> some View {
        HStack(spacing: 8) {
            TextField("New name", text: $renameDraft)
                .textFieldStyle(.roundedBorder)
                .onSubmit { commitRename(provider, alias: alias) }
                .accessibilityLabel(Text("New name for \(alias)"))
            Button("Save") { commitRename(provider, alias: alias) }
                .buttonStyle(.borderedProminent).controlSize(.small)
                .disabled(renameDraft.isEmpty || renameDraft == alias)
            Button("Cancel") { renaming = nil }.buttonStyle(.bordered).controlSize(.small)
        }
        .padding(8)
    }

    private func commitRename(_ provider: CLIProvider, alias: String) {
        guard !renameDraft.isEmpty, renameDraft != alias else { return }
        if provider == .claude { store.renameClaudeLogin(alias, to: renameDraft) } else { store.renameCodexLogin(alias, to: renameDraft) }
        renaming = nil
    }

    /// The add form while the user names the account, then a waiting row while the browser sign-in runs.
    @ViewBuilder private func signInArea(_ provider: CLIProvider) -> some View {
        let activity = provider == .claude ? store.claudeActivity : store.codexActivity
        if activity == .signingIn {
            Label("Finish signing in in your browser…", systemImage: "safari")
                .loginMessageStyle()
        } else if adding == provider {
            VStack(alignment: .leading, spacing: 6) {
                TextField("Name, e.g. work", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(Text("Name for the new \(provider.title) account"))
                if provider == .claude {
                    TextField("Email (optional)", text: $newEmail)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(Text("Email for the new Claude account"))
                }
                HStack {
                    Text("Your browser opens to sign in.").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") { adding = nil }.buttonStyle(.bordered).controlSize(.small)
                    Button("Sign in") {
                        if provider == .claude { store.addClaudeLogin(name: newName, email: newEmail) } else { store.addCodexLogin(name: newName) }
                        adding = nil
                    }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .disabled(newName.isEmpty)
                }
            }
            .padding(8)
        }
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
            Button("Quit AI Control") { NSApp.terminate(nil) }
                .buttonStyle(.bordered)
                .keyboardShortcut("q")
        }
        .padding(12)
    }

    private var footer: some View {
        Text("Open sessions keep working after a switch")
            .font(.caption2).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct SavedLoginRow: View {
    let name: String
    let detail: String
    let symbol: String
    let tint: Color
    let selectedLabel: String?
    let switching: Bool
    let dimmed: Bool
    var usage: LoginUsageResult? = nil

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
                HStack {
                    Label(detail, systemImage: symbol).foregroundStyle(tint).font(.caption2).lineLimit(1)
                    Spacer(minLength: 8)
                    if case .usage(let usage) = usage, let resets = usage.resetsAvailable {
                        Label("\(resets) reset\(resets == 1 ? "" : "s")", systemImage: "arrow.counterclockwise")
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                            .accessibilityLabel(Text("\(resets) rate-limit resets available"))
                    }
                }
                usageView
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

extension SavedLoginRow {
    /// Windows sit in fixed columns so bars line up across rows; a missing window leaves its column empty.
    @ViewBuilder var usageView: some View {
        switch usage {
        case .usage(let usage):
            let known = ["5h", "Week"]
            let extra = usage.windows.map(\.label).filter { !known.contains($0) }
            HStack(alignment: .top, spacing: 16) {
                ForEach(known + extra, id: \.self) { label in
                    Group {
                        if let window = usage.windows.first(where: { $0.label == label }) {
                            UsageWindowBar(label: window.label, usedPercent: window.usedPercent, resetsAt: window.resetsAt)
                        } else { Color.clear }
                    }
                    .frame(width: 138, alignment: .leading)
                }
            }
        case .unavailable(let reason):
            Text(reason).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
        case nil:
            EmptyView()
        }
    }

}

struct TokenCountFormatter {
    static func compact(_ tokens: Int) -> String {
        for (threshold, unit) in [(1_000_000_000, "B"), (1_000_000, "M"), (1_000, "K")] where tokens >= threshold {
            let value = Double(tokens) / Double(threshold)
            return String(format: value < 10 && value.rounded() != value ? "%.1f%@" : "%.0f%@", value, unit)
        }
        return String(tokens)
    }
}

private struct UsageWindowBar: View {
    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE j:mm")
        return formatter
    }()

    let label: String
    let usedPercent: Double
    let resetsAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(label) \(Int(usedPercent.rounded()))%\(Self.reset(resetsAt))")
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.85)
            // A drawn bar keeps its color when the menu is not the key window, unlike the native indicator.
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.2))
                    Capsule()
                        .fill(usedPercent >= 90 ? Color.red : usedPercent >= 70 ? Color.orange : Color.accentColor)
                        .frame(width: max(4, proxy.size.width * min(max(usedPercent, 0), 100) / 100))
                }
            }
            .frame(height: 5)
            .accessibilityElement()
            .accessibilityLabel(Text("\(label) usage"))
            .accessibilityValue(Text("\(Int(usedPercent.rounded())) percent"))
        }
    }

    private static func reset(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = Calendar.current.isDate(date, inSameDayAs: Date()) ? time : day
        return " · " + formatter.string(from: date)
    }
}

private extension View {
    func loginMessageStyle() -> some View {
        font(.caption).foregroundStyle(.secondary).padding(8).fixedSize(horizontal: false, vertical: true)
    }
}
#endif
