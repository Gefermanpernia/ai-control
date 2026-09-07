import Testing
@testable import AIControlCore

struct ClaudeLoginManagerTests {
    @Test("Scoped JSON rejects duplicate keys at any depth")
    func rejectsDuplicateKeys() {
        #expect(throws: ScopedJSON.Error.self) {
            try ScopedJSON(#"{"owned":{"token":"one","token":"two"}}"#)
        }
    }

    @Test("Scoped JSON rejects malformed input")
    func rejectsMalformedJSON() {
        #expect(throws: ScopedJSON.Error.self) {
            try ScopedJSON(#"{"owned":[1,]}"#)
        }
    }

    @Test("Replacing an owned field preserves unrelated bytes and large integers")
    func preservesUnownedRawJSON() throws {
        let original = #"{"sentinel":{"future":true},"huge":900719925474099312345,"owned":{"old":1}}"#
        let document = try ScopedJSON(original)

        let edited = try document.replacing(["owned": .value(#"{"new":2}"#)])

        #expect(edited == #"{"sentinel":{"future":true},"huge":900719925474099312345,"owned":{"new":2}}"#)
    }

    @Test("Scoped JSON distinguishes missing, null, and present fields")
    func distinguishesPresence() throws {
        let document = try ScopedJSON(#"{"nullField":null,"valueField":{"x":1}}"#)

        #expect(document.presence(of: "missingField") == .missing)
        #expect(document.presence(of: "nullField") == .null)
        #expect(document.presence(of: "valueField") == .value(#"{"x":1}"#))
    }

    @Test("Removing and adding owned fields leaves sentinels unchanged")
    func appliesOwnedPresenceWithoutTouchingSentinels() throws {
        let document = try ScopedJSON(#"{"sentinel":"keep","remove":7}"#)

        let edited = try document.replacing(["remove": .missing, "added": .null])

        #expect(edited == #"{"sentinel":"keep","added":null}"#)
    }

    @Test("Snapshot preserves opaque account and credential subtrees")
    func preservesOpaqueSnapshotSubtrees() throws {
        let snapshot = try ClaudeLoginSnapshot.capture(
            secureRoot: #"{"claudeAiOauth":{"accessToken":"SYNTHETIC","refreshToken":"ROTATED","future":900719925474099312345}}"#,
            configurationRoot: #"{"oauthAccount":{"accountUuid":"account-a","organizationUuid":"org-a","future":{"keep":true}}}"#
        )

        #expect(snapshot.claudeAiOauth == .value(#"{"accessToken":"SYNTHETIC","refreshToken":"ROTATED","future":900719925474099312345}"#))
        #expect(snapshot.oauthAccount == .value(#"{"accountUuid":"account-a","organizationUuid":"org-a","future":{"keep":true}}"#))
        #expect(snapshot.identity == ClaudeLoginIdentity(accountUUID: "account-a", organizationUUID: "org-a"))
        #expect(snapshot.usability == .usable)
    }

    @Test("Snapshot retains optional secure-field presence")
    func retainsOptionalSecureFieldPresence() throws {
        let snapshot = try ClaudeLoginSnapshot.capture(
            secureRoot: #"{"claudeAiOauth":{"accessToken":"A","refreshToken":"R"},"organizationUuid":null}"#,
            configurationRoot: #"{"oauthAccount":{"accountUuid":"account-a"}}"#
        )

        #expect(snapshot.organizationUUID == .null)
        #expect(snapshot.trustedDeviceToken == .missing)
    }

    @Test("Snapshot rejects disagreeing secure and account identities")
    func rejectsIdentityDisagreement() {
        #expect(throws: ClaudeLoginSnapshot.Error.self) {
            try ClaudeLoginSnapshot.capture(
                secureRoot: #"{"claudeAiOauth":{"accessToken":"A","refreshToken":"R"},"organizationUuid":"org-b"}"#,
                configurationRoot: #"{"oauthAccount":{"accountUuid":"account-a","organizationUuid":"org-a"}}"#
            )
        }
    }

    @Test("Dead credential markers require re-login without reviving tokens")
    func recognizesDeadCredentialMarkers() throws {
        let snapshot = try ClaudeLoginSnapshot.capture(
            secureRoot: #"{"claudeAiOauth":{"accessToken":"","refreshToken":"","expiresAt":0}}"#,
            configurationRoot: #"{"oauthAccount":{"accountUuid":"account-a"}}"#
        )

        #expect(snapshot.usability == .reLoginNeeded)
        #expect(snapshot.claudeAiOauth == .value(#"{"accessToken":"","refreshToken":"","expiresAt":0}"#))
    }
}
