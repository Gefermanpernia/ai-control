import Testing
@testable import AIControlCore

struct ExecutableLookupTests {
    @Test("Skips Windows mount entries before choosing a WSL executable")
    func skipsWindowsMount() {
        let executable = ExecutableLookup.first(
            named: "codex", path: "/mnt/c/Users/me/npm:/home/me/.local/bin",
            extraDirectories: [], isExecutable: { _ in true }
        )
        #expect(executable == "/home/me/.local/bin/codex")
    }

    @Test("Skips Windows suffixes and refuses Windows-only candidates")
    func skipsWindowsSuffixes() {
        let available: Set<String> = ["/opt/bin/codex.exe", "/opt/bin/codex.cmd", "/opt/bin/codex.bat"]
        #expect(ExecutableLookup.first(named: "codex.EXE", path: "/opt/bin", extraDirectories: [],
                                       isExecutable: { _ in true }) == nil)
        #expect(ExecutableLookup.first(named: "codex", path: "/mnt/D/npm:/opt/bin",
                                       extraDirectories: [], isExecutable: { available.contains($0) }) == nil)
    }

    @Test("Rejects only single-letter mounts and matches suffixes without case sensitivity")
    func mountBoundaryAndCase() {
        #expect(ExecutableLookup.isWindowsSide("/mnt/z/bin/codex"))
        #expect(!ExecutableLookup.isWindowsSide("/mnt/zz/bin/codex"))
        #expect(!ExecutableLookup.isWindowsSide("/mnt/z"))
        #expect(ExecutableLookup.isWindowsSide("/usr/local/bin/codex.CmD"))
    }

    @Test("Missing native Codex gives actionable installation guidance")
    func missingNativeCodexGuidance() {
        #expect(NativeCodexRequired.missing.localizedDescription.contains("inside WSL on Windows"))
    }

    @Test("Keeps search order and uses extra directories for native binaries")
    func searchesExtraDirectories() {
        let found = ExecutableLookup.first(named: "codex", path: "/mnt/C/npm:/missing",
                                           extraDirectories: ["/home/me/.local/bin", "/usr/local/bin"],
                                           isExecutable: { $0 == "/usr/local/bin/codex" })
        #expect(found == "/usr/local/bin/codex")
    }
}
