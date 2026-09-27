import Foundation

/// Searches native executables in PATH order, then in the supplied fallback directories.
enum ExecutableLookup {
    static func first(
        named name: String, path: String, extraDirectories: [String],
        isExecutable: (String) -> Bool, resolve: (String) -> String? = { $0 },
        windowsMounts: [String] = []
    ) -> String? {
        let directories = path.split(separator: ":", omittingEmptySubsequences: false).map(String.init) + extraDirectories
        for directory in directories where directory.hasPrefix("/") {
            let candidate = directory + "/" + name
            guard !isWindowsSide(candidate, windowsMounts: windowsMounts), isExecutable(candidate),
                  let resolved = resolve(candidate), resolved.hasPrefix("/"),
                  !isWindowsSide(resolved, windowsMounts: windowsMounts) else { continue }
            return candidate
        }
        return nil
    }

    /// The first native executable on this system's PATH and usual install directories.
    static func live(named name: String) -> String? {
        first(
            named: name, path: ProcessInfo.processInfo.environment["PATH"] ?? "",
            extraDirectories: [NSHomeDirectory() + "/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"],
            isExecutable: FileManager.default.isExecutableFile(atPath:),
            resolve: { candidate in
                guard let resolved = realpath(candidate, nil) else { return nil }
                defer { free(resolved) }
                return String(cString: resolved)
            },
            windowsMounts: {
                #if os(Linux)
                return windowsMounts(
                    fromMountTable: (try? String(contentsOfFile: "/proc/self/mounts", encoding: .utf8)) ?? "")
                #else
                return []
                #endif
            }()
        )
    }

    static func isWindowsSide(_ path: String, windowsMounts: [String] = []) -> Bool {
        let name = (path as NSString).lastPathComponent.lowercased()
        if [".exe", ".cmd", ".bat"].contains(where: name.hasSuffix) { return true }
        if windowsMounts.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { return true }
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        return path.hasPrefix("/") && parts.count >= 3 && parts[0] == "mnt" &&
            parts[1].count == 1 && parts[1].first?.isASCII == true && parts[1].first?.isLetter == true
    }

    static func windowsMounts(fromMountTable table: String) -> [String] {
        table.split(separator: "\n").compactMap { line in
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count >= 4,
                  fields[2] == "drvfs" || (fields[2] == "9p" && fields[3].split(separator: ",").contains {
                      $0 == "aname=drvfs" || $0.hasPrefix("aname=drvfs;")
                  }) else { return nil }
            let mount = String(fields[1]).replacingOccurrences(of: #"\040"#, with: " ")
                .replacingOccurrences(of: #"\011"#, with: "\t")
                .replacingOccurrences(of: #"\012"#, with: "\n")
                .replacingOccurrences(of: #"\134"#, with: "\\")
            return mount.hasPrefix("/") ? mount : nil
        }
    }
}

/// A missing native CLI must not fall back to Windows-side credentials.
enum NativeCodexRequired: LocalizedError {
    case missing
    var errorDescription: String? { "Codex CLI not found. Install it on this system (inside WSL on Windows); a Windows-side codex cannot use these logins." }
}
