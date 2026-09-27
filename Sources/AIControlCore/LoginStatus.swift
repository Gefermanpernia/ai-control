import Foundation

/// A versioned snapshot for terminal clients. An unavailable adapter or an unreadable provider list
/// is represented by `available: false` and an empty `logins` array; status never exposes backend errors.
/// Usage is requested only when explicitly opted in because it can renew saved logins and use the network.
struct LoginStatus: Codable {
    struct Usage: Codable {
        struct Window: Codable {
            let label: String
            let usedPercent: Double
            let resetsAt: Date?

            enum CodingKeys: String, CodingKey { case label, usedPercent, resetsAt }
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(label, forKey: .label)
                try container.encode(usedPercent, forKey: .usedPercent)
                try container.encode(resetsAt, forKey: .resetsAt)
            }
        }

        let windows: [Window]
        let resetsAvailable: Int?
        let fetchedAt: Date

        init(_ usage: LoginUsage) {
            windows = usage.windows.map { .init(label: $0.label, usedPercent: $0.usedPercent, resetsAt: $0.resetsAt) }
            resetsAvailable = usage.resetsAvailable
            fetchedAt = usage.fetchedAt
        }

        enum CodingKeys: String, CodingKey { case windows, resetsAvailable, fetchedAt }
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(windows, forKey: .windows)
            try container.encode(resetsAvailable, forKey: .resetsAvailable)
            try container.encode(fetchedAt, forKey: .fetchedAt)
        }
    }

    struct Claude: Codable {
        struct Login: Codable {
            let name: String
            let needsLogin: Bool
            let usage: Usage?
            let usageError: String?

            enum CodingKeys: String, CodingKey { case name, needsLogin, usage, usageError }
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(name, forKey: .name)
                try container.encode(needsLogin, forKey: .needsLogin)
                try container.encode(usage, forKey: .usage)
                try container.encode(usageError, forKey: .usageError)
            }
        }
        let available: Bool
        let selected: String?
        let logins: [Login]
        let installed: Bool

        enum CodingKeys: String, CodingKey { case available, selected, logins, installed }
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(available, forKey: .available)
            try container.encode(installed, forKey: .installed)
            try container.encode(selected, forKey: .selected)
            try container.encode(logins, forKey: .logins)
        }
    }

    struct Codex: Codable {
        struct Login: Codable {
            let name: String
            let email: String?
            let usage: Usage?
            let usageError: String?

            enum CodingKeys: String, CodingKey { case name, email, usage, usageError }
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(name, forKey: .name)
                try container.encode(email, forKey: .email)
                try container.encode(usage, forKey: .usage)
                try container.encode(usageError, forKey: .usageError)
            }
        }
        let available: Bool
        let inUse: String?
        let logins: [Login]
        let installed: Bool

        enum CodingKeys: String, CodingKey { case available, inUse, logins, installed }
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(available, forKey: .available)
            try container.encode(installed, forKey: .installed)
            try container.encode(inUse, forKey: .inUse)
            try container.encode(logins, forKey: .logins)
        }
    }

    let version: Int
    let claude: Claude
    let codex: Codex

    init(claude: Claude, codex: Codex) {
        version = 1
        self.claude = claude
        self.codex = codex
    }
}

/// Builds a provider snapshot without reading usage or invoking renewal unless `includeUsage` is true.
/// Which provider CLIs this system has, so interfaces can hide the ones the user does not use.
struct InstalledCLIs {
    let claude: Bool
    let codex: Bool

    static var live: Self {
        let launcher = NSHomeDirectory() + "/.local/bin/claude"
        return .init(claude: FileManager.default.isExecutableFile(atPath: launcher) || ExecutableLookup.live(named: "claude") != nil,
                     codex: ExecutableLookup.live(named: "codex") != nil)
    }
}

func loginStatus(claude: ClaudeLoginAppAdapter, codex: CodexLoginAppAdapter, includeUsage: Bool,
                 installed: InstalledCLIs = .init(claude: true, codex: true)) async -> LoginStatus {
    let claudeList = await claude.list()
    let codexList = await codex.list()
    let claudeUsage = includeUsage ? await claude.usage() : [:]
    let codexUsage = includeUsage ? await codex.usage() : [:]

    let claudeState: LoginStatus.Claude
    if case .listed(let listing) = claudeList {
        claudeState = .init(available: true, selected: listing.lastSelectedHint,
                            logins: listing.aliases.map { alias in
            let (usage, error) = statusUsage(claudeUsage[alias.name])
            return .init(name: alias.name, needsLogin: alias.requiresReLogin, usage: usage, usageError: error)
        }, installed: installed.claude)
    } else {
        claudeState = .init(available: false, selected: nil, logins: [], installed: installed.claude)
    }
    let codexState: LoginStatus.Codex
    if case .listed(let listing) = codexList {
        codexState = .init(available: true, inUse: listing.inUse, logins: listing.logins.map { login in
            let (usage, error) = statusUsage(codexUsage[login.name])
            return .init(name: login.name, email: login.email, usage: usage, usageError: error)
        }, installed: installed.codex)
    } else {
        codexState = .init(available: false, inUse: nil, logins: [], installed: installed.codex)
    }
    return .init(claude: claudeState, codex: codexState)
}

private func statusUsage(_ result: LoginUsageResult?) -> (LoginStatus.Usage?, String?) {
    switch result {
    case .usage(let usage): return (LoginStatus.Usage(usage), nil)
    case .unavailable(let reason): return (nil, reason)
    case nil: return (nil, nil)
    }
}
