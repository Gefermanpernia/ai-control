import Foundation
import Testing
@testable import AIControlCore

struct SettingsTests {
    private func store() throws -> (SettingsStore, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("settings-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return (SettingsStore(directory: root.path + "/data"), root)
    }

    private func run(_ arguments: [String], _ store: SettingsStore) -> (Int32, [String]) {
        var lines: [String] = []
        let code = runSettings(arguments: arguments, store: store) { lines.append($0) }
        return (code, lines)
    }

    @Test("Everything is off by default, and a missing file is not created by reading")
    func defaults() throws {
        let (store, root) = try store()
        defer { try? FileManager.default.removeItem(at: root) }
        let settings = try store.load()
        #expect(!settings.refresh.enabled && settings.refresh.intervalSeconds == 300)
        #expect(!settings.autoSwitch.claude && !settings.autoSwitch.codex && !settings.autoSwitch.background)
        #expect(settings.autoSwitch.thresholdPercent == 99)
        #expect(!FileManager.default.fileExists(atPath: store.path))
    }

    @Test("Set changes one option, keeps the rest, and writes an owner-only file")
    func setRoundTrip() throws {
        let (store, root) = try store()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(run(["settings", "set", "refresh", "on"], store).0 == 0)
        #expect(run(["settings", "set", "refresh-interval", "600"], store).0 == 0)
        #expect(run(["settings", "set", "auto-switch-claude", "on"], store).0 == 0)
        #expect(run(["settings", "set", "auto-switch-threshold", "95"], store).0 == 0)
        #expect(run(["settings", "set", "background-refresh", "on"], store).0 == 0)

        let settings = try store.load()
        #expect(settings.refresh.enabled && settings.refresh.intervalSeconds == 600)
        #expect(settings.autoSwitch.claude && !settings.autoSwitch.codex)
        #expect(settings.autoSwitch.thresholdPercent == 95 && settings.autoSwitch.background)
        let mode = (try FileManager.default.attributesOfItem(atPath: store.path))[.posixPermissions] as? Int
        #expect(mode == 0o600)
    }

    @Test("Refused values leave the file unchanged: interval below 300 s, threshold outside 50–100, unknown keys")
    func refusals() throws {
        let (store, root) = try store()
        defer { try? FileManager.default.removeItem(at: root) }
        for arguments in [["settings", "set", "refresh-interval", "299"],
                          ["settings", "set", "auto-switch-threshold", "49"],
                          ["settings", "set", "auto-switch-threshold", "101"],
                          ["settings", "set", "refresh", "maybe"],
                          ["settings", "set", "colour", "on"]] {
            let (code, lines) = run(arguments, store)
            #expect(code == 2, "\(arguments)")
            #expect(lines.last != nil && lines.last != "Saved.", "\(arguments)")
        }
        #expect(!FileManager.default.fileExists(atPath: store.path))
    }

    @Test("Timer follows effective background state, not unrelated settings changes")
    func timerTransitions() throws {
        let (store, root) = try store()
        defer { try? FileManager.default.removeItem(at: root) }
        var calls: [[String]] = []
        func set(_ key: String, _ value: String) -> (Int32, [String]) {
            var lines: [String] = []
            let code = runSettings(arguments: ["settings", "set", key, value], store: store,
                                   systemdUser: { calls.append($0); return 0 }, linuxSystemd: true,
                                   output: { lines.append($0) })
            return (code, lines)
        }
        #expect(set("background-refresh", "on").1 == ["Saved."])
        #expect(set("refresh-interval", "600").1 == ["Saved."])
        #expect(set("auto-switch-claude", "on").1 == ["Saved.", "Background checks enabled."])
        #expect(calls == [["enable", "--now", "ai-control-auto-switch.timer"]])
        #expect(set("auto-switch-threshold", "90").1 == ["Saved."])
        #expect(set("auto-switch-codex", "on").1 == ["Saved."])
        #expect(set("auto-switch-claude", "off").1 == ["Saved."])
        #expect(set("background-refresh", "off").1 == ["Saved.", "Background checks disabled."])
        #expect(calls == [["enable", "--now", "ai-control-auto-switch.timer"],
                          ["disable", "--now", "ai-control-auto-switch.timer"]])
        #expect(set("background-refresh", "on").0 == 0)
        #expect(set("auto-switch-codex", "off").1 == ["Saved.", "Background checks disabled."])
    }

    @Test("Unavailable or failing timer is advisory after settings have been saved")
    func timerFailureIsSoft() throws {
        let (store, root) = try store()
        defer { try? FileManager.default.removeItem(at: root) }
        try store.update { $0.autoSwitch.background = true }
        for result: Int32? in [nil, 1] {
            var lines: [String] = []
            let code = runSettings(arguments: ["settings", "set", "auto-switch-claude", "on"], store: store,
                                   systemdUser: { _ in result }, linuxSystemd: true,
                                   output: { lines.append($0) })
            #expect(code == 0)
            #expect(lines.first == "Saved.")
            #expect(lines.last?.contains("systemctl --user enable --now ai-control-auto-switch.timer") == true)
            try store.update { $0.autoSwitch.claude = false }
        }
    }

    @Test("Non-Linux settings changes never invoke the timer")
    func nonLinuxSkipsTimer() throws {
        let (store, root) = try store()
        defer { try? FileManager.default.removeItem(at: root) }
        try store.update { $0.autoSwitch.background = true }
        var called = false
        let code = runSettings(arguments: ["settings", "set", "auto-switch-claude", "on"], store: store,
                               systemdUser: { _ in called = true; return 0 }, linuxSystemd: false,
                               output: { _ in })
        #expect(code == 0 && !called)
        #expect(try store.load().backgroundRefreshActive)
    }

    @Test("Refused and failed saves never invoke the timer")
    func timerRequiresSuccessfulSave() throws {
        let (store, root) = try store()
        defer { try? FileManager.default.removeItem(at: root) }
        var calls = 0
        func set(_ store: SettingsStore, _ key: String, _ value: String) -> Int32 {
            runSettings(arguments: ["settings", "set", key, value], store: store,
                        systemdUser: { _ in calls += 1; return 0 }, linuxSystemd: true,
                        output: { _ in })
        }
        #expect(set(store, "background-refresh", "invalid") == 2)
        let obstacle = root.appendingPathComponent("obstacle")
        #expect(FileManager.default.createFile(atPath: obstacle.path, contents: Data()))
        #expect(set(SettingsStore(directory: obstacle.path + "/data"), "background-refresh", "on") == 3)
        #expect(calls == 0)
    }

    @Test("Background refresh only applies while automatic switching is on for a provider")
    func backgroundNeedsAutoSwitch() throws {
        var settings = AIControlSettings()
        settings.autoSwitch.background = true
        #expect(!settings.backgroundRefreshActive)
        settings.autoSwitch.codex = true
        #expect(settings.backgroundRefreshActive)
    }

    @Test("Unknown keys in the file, such as a pasted credential, are never echoed or written back")
    func unknownKeysAreDropped() throws {
        let (store, root) = try store()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(atPath: store.directory, withIntermediateDirectories: true)
        let secret = "sk-test-do-not-echo"
        #expect(FileManager.default.createFile(
            atPath: store.path, contents: Data(#"{"apiKey":"\#(secret)","refresh":{"enabled":true,"token":"\#(secret)"}}"#.utf8),
            attributes: [.posixPermissions: 0o600]))

        let (_, shown) = run(["settings"], store)
        #expect(!shown.joined().contains(secret))
        #expect(shown.joined().contains(#""enabled":true"#))
        let encoder = JSONEncoder()
        let status = LoginStatus(claude: .init(available: false, selected: nil, logins: [], installed: true),
                                 codex: .init(available: false, inUse: nil, logins: [], installed: true),
                                 monitors: [], settings: try store.load())
        #expect(!String(decoding: try encoder.encode(status), as: UTF8.self).contains(secret))
        #expect(run(["settings", "set", "refresh", "off"], store).0 == 0)
        #expect(!String(decoding: try Data(contentsOf: URL(fileURLWithPath: store.path)), as: UTF8.self).contains(secret))
    }

    @Test("settings prints the effective options as JSON")
    func printsJSON() throws {
        let (store, root) = try store()
        defer { try? FileManager.default.removeItem(at: root) }
        let (code, lines) = run(["settings"], store)
        #expect(code == 0)
        let object = try #require(JSONSerialization.jsonObject(with: Data(lines.joined().utf8)) as? [String: Any])
        #expect(object.keys.sorted() == ["autoSwitch", "refresh", "version"])
        let autoSwitch = try #require(object["autoSwitch"] as? [String: Any])
        #expect(autoSwitch.keys.sorted() == ["background", "claude", "claudeOrder", "codex", "codexOrder", "thresholdPercent"])
    }
}
