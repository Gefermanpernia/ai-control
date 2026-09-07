import Foundation

struct ClaudeLoginIdentity: Equatable, Sendable {
    let accountUUID: String
    let organizationUUID: String?
}

enum ClaudeLoginUsability: Equatable, Sendable {
    case usable
    case reLoginNeeded
}

struct ClaudeLoginSnapshot: Equatable, Sendable {
    enum Error: Swift.Error { case missingAccount, ambiguousIdentity, identityDisagreement }

    let claudeAiOauth: JSONPresence
    let oauthAccount: JSONPresence
    let organizationUUID: JSONPresence
    let trustedDeviceToken: JSONPresence
    let identity: ClaudeLoginIdentity
    let usability: ClaudeLoginUsability

    static func capture(secureRoot: String, configurationRoot: String) throws -> Self {
        let secure = try ScopedJSON(secureRoot)
        let configuration = try ScopedJSON(configurationRoot)
        let credentials = secure.presence(of: "claudeAiOauth")
        let account = configuration.presence(of: "oauthAccount")
        guard case .value(let accountRaw) = account else { throw Error.missingAccount }
        let accountObject = try ScopedJSON(accountRaw)
        guard let accountUUID = string(accountObject.presence(of: "accountUuid")), !accountUUID.isEmpty else {
            throw Error.ambiguousIdentity
        }
        let accountOrganization = string(accountObject.presence(of: "organizationUuid"))
        let secureOrganization = secure.presence(of: "organizationUuid")
        if let secureValue = string(secureOrganization), secureValue != accountOrganization {
            throw Error.identityDisagreement
        }
        return Self(
            claudeAiOauth: credentials,
            oauthAccount: account,
            organizationUUID: secureOrganization,
            trustedDeviceToken: secure.presence(of: "trustedDeviceToken"),
            identity: .init(accountUUID: accountUUID, organizationUUID: accountOrganization),
            usability: isDead(credentials) ? .reLoginNeeded : .usable
        )
    }

    private static func string(_ presence: JSONPresence) -> String? {
        guard case .value(let raw) = presence,
              let data = raw.data(using: .utf8),
              let value = try? JSONDecoder().decode(String.self, from: data) else { return nil }
        return value
    }

    private static func isDead(_ presence: JSONPresence) -> Bool {
        guard case .value(let raw) = presence, let object = try? ScopedJSON(raw) else { return true }
        return string(object.presence(of: "accessToken")) == ""
            || string(object.presence(of: "refreshToken")) == ""
            || object.presence(of: "expiresAt") == .value("0")
    }
}
