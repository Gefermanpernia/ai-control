import Foundation

/// Options shared by the terminal UI, the macOS menu and background checks. Everything is off by default.
struct AIControlSettings: Codable, Equatable {
    struct Refresh: Codable, Equatable {
        var enabled = false
        var intervalSeconds = AIControlSettings.minimumInterval

        init() {}
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
            intervalSeconds = max(AIControlSettings.minimumInterval,
                                  try values.decodeIfPresent(Int.self, forKey: .intervalSeconds) ?? 0)
        }
    }

    struct AutoSwitch: Codable, Equatable {
        var claude = false
        var codex = false
        var thresholdPercent = 99
        /// Refresh usage with no interface open; only used while switching is on for a provider.
        var background = false
        /// Preferred order of saved accounts; accounts not listed follow by name.
        var claudeOrder: [String] = []
        var codexOrder: [String] = []

        init() {}
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            claude = try values.decodeIfPresent(Bool.self, forKey: .claude) ?? false
            codex = try values.decodeIfPresent(Bool.self, forKey: .codex) ?? false
            let threshold = try values.decodeIfPresent(Int.self, forKey: .thresholdPercent) ?? 99
            thresholdPercent = AIControlSettings.thresholds.contains(threshold) ? threshold : 99
            background = try values.decodeIfPresent(Bool.self, forKey: .background) ?? false
            claudeOrder = Self.validNames(try values.decodeIfPresent([String].self, forKey: .claudeOrder))
            codexOrder = Self.validNames(try values.decodeIfPresent([String].self, forKey: .codexOrder))
        }

        /// Only saved-account names, once each; anything else in the file is dropped.
        static func validNames(_ names: [String]?) -> [String] {
            var seen: Set<String> = []
            return (names ?? []).filter {
                $0.range(of: #"\A[a-z][a-z0-9_-]{0,31}\z"#, options: .regularExpression) != nil && seen.insert($0).inserted
            }
        }
    }

    static let minimumInterval = 300
    static let thresholds = 50...100

    var version = 1
    var refresh = Refresh()
    var autoSwitch = AutoSwitch()

    enum Provider { case claude, codex }

    func order(_ provider: Provider) -> [String] { provider == .claude ? autoSwitch.claudeOrder : autoSwitch.codexOrder }
    func switching(_ provider: Provider) -> Bool { provider == .claude ? autoSwitch.claude : autoSwitch.codex }
    mutating func setOrder(_ provider: Provider, _ names: [String]) {
        if provider == .claude { autoSwitch.claudeOrder = names } else { autoSwitch.codexOrder = names }
    }

    var backgroundRefreshActive: Bool { autoSwitch.background && (autoSwitch.claude || autoSwitch.codex) }

    init() {}

    /// Missing keys keep their defaults, so older files and newer engines stay compatible.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decodeIfPresent(Int.self, forKey: .version) ?? 1
        refresh = try values.decodeIfPresent(Refresh.self, forKey: .refresh) ?? .init()
        autoSwitch = try values.decodeIfPresent(AutoSwitch.self, forKey: .autoSwitch) ?? .init()
    }
}

/// `settings.json` in AI Control's owner-only data directory; only the engine reads and writes it.
struct SettingsStore {
    let directory: String
    var path: String { directory + "/settings.json" }

    static var live: Self {
        .init(directory: ClaudeLiveSystem.dataDirectory(home: NSHomeDirectory(), environment: ProcessInfo.processInfo.environment))
    }

    func load() throws -> AIControlSettings {
        do {
            return try JSONDecoder().decode(AIControlSettings.self, from: ProtectedFileStore(path: path).read())
        } catch IsolatedKeychainError.missing {
            return .init()
        }
    }

    func update(_ change: (inout AIControlSettings) -> Void) throws {
        let lock = try ManagerFileLock.acquire(directory: directory + "/settings")
        defer { lock.release() }
        let file = ProtectedFileStore(path: path)
        var settings = try load()
        change(&settings)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(settings)
        do { try file.update(data: data) } catch IsolatedKeychainError.missing { try file.create(data: data) }
    }
}

extension SettingsStore {
    /// Keeps a renamed account's place in the priority order.
    func renameInOrder(_ provider: AIControlSettings.Provider, from alias: String, to newAlias: String) throws {
        guard try load().order(provider).contains(alias) else { return }
        try update { settings in
            settings.setOrder(provider, settings.order(provider).map { $0 == alias ? newAlias : $0 })
        }
    }
}

/// `settings` prints the options as JSON; `settings set <key> <value>` changes one of them.
func runSettings(arguments: [String], store: SettingsStore = .live, output: (String) -> Void) -> Int32 {
    let usage = "Usage: AIControl settings [set refresh|auto-switch-claude|auto-switch-codex|background-refresh on|off" +
        " | set refresh-interval <seconds> | set auto-switch-threshold <percent>]"
    if arguments == ["settings"] {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            output(String(decoding: try encoder.encode(try store.load()), as: UTF8.self))
            return 0
        } catch {
            output("Blocked: settings could not be read.")
            return 3
        }
    }
    guard arguments.count == 4, arguments[0] == "settings", arguments[1] == "set" else { output(usage); return 2 }
    let value = arguments[3]
    let toggle: Bool? = value == "on" ? true : value == "off" ? false : nil
    let number = Int(value)
    let change: (inout AIControlSettings) -> Void
    switch arguments[2] {
    case "refresh": guard let on = toggle else { output(usage); return 2 }; change = { $0.refresh.enabled = on }
    case "auto-switch-claude": guard let on = toggle else { output(usage); return 2 }; change = { $0.autoSwitch.claude = on }
    case "auto-switch-codex": guard let on = toggle else { output(usage); return 2 }; change = { $0.autoSwitch.codex = on }
    case "background-refresh": guard let on = toggle else { output(usage); return 2 }; change = { $0.autoSwitch.background = on }
    case "refresh-interval":
        guard let seconds = number, seconds >= AIControlSettings.minimumInterval else {
            output("The refresh interval must be a whole number of seconds, 300 or more."); return 2
        }
        change = { $0.refresh.intervalSeconds = seconds }
    case "auto-switch-threshold":
        guard let percent = number, AIControlSettings.thresholds.contains(percent) else {
            output("The threshold must be a whole percentage between 50 and 100."); return 2
        }
        change = { $0.autoSwitch.thresholdPercent = percent }
    default: output(usage); return 2
    }
    do {
        try store.update(change)
        output("Saved.")
        return 0
    } catch {
        output("Blocked: settings could not be saved.")
        return 3
    }
}
