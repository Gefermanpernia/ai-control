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

    @Test("Rejects symlinks into Windows mounts and Windows-suffixed targets")
    func rejectsResolvedWindowsPaths() {
        let mounts = ["/win/d"]
        #expect(ExecutableLookup.first(named: "codex", path: "/usr/local/bin:/native", extraDirectories: [],
            isExecutable: { _ in true }, resolve: { $0 == "/usr/local/bin/codex" ? "/win/d/npm/codex" : $0 },
            windowsMounts: mounts) == "/native/codex")
        #expect(ExecutableLookup.first(named: "codex", path: "/usr/local/bin", extraDirectories: [],
            isExecutable: { _ in true }, resolve: { _ in "/opt/npm/codex.CMD" },
            windowsMounts: []) == nil)
    }

    @Test("Skips empty and relative PATH entries and unresolved candidates")
    func skipsUnsafeEntries() {
        let found = ExecutableLookup.first(named: "codex", path: ":relative:.:/broken:/native",
            extraDirectories: [], isExecutable: { _ in true },
            resolve: { $0 == "/broken/codex" ? nil : $0 }, windowsMounts: [])
        #expect(found == "/native/codex")
    }

    @Test("Parses Windows drive mounts including escaped mount points and component boundaries")
    func mountTable() {
        let table = #"C:\134 /mnt/c 9p rw,aname=drvfs;path=C:\;uid=1000 0 0"# + "\n" +
            #"D:\134 /win/d\040drive drvfs rw,noatime 0 0"# + "\n" +
            "/dev/sdc / ext4 rw,relatime 0 0\n"
        let mounts = ExecutableLookup.windowsMounts(fromMountTable: table)
        #expect(mounts == ["/mnt/c", "/win/d drive"])
        #expect(ExecutableLookup.isWindowsSide("/win/d drive/npm/codex", windowsMounts: mounts))
        #expect(!ExecutableLookup.isWindowsSide("/win/d drive-extra/npm/codex", windowsMounts: mounts))
        #expect(!ExecutableLookup.isWindowsSide("/mnt/cache/npm/codex", windowsMounts: []))
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
