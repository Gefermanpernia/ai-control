import Foundation

/// Searches native executables in PATH order, then in the supplied fallback directories.
enum ExecutableLookup {
    static func first(
        named name: String, path: String, extraDirectories: [String],
        isExecutable: (String) -> Bool
    ) -> String? {
        let directories = path.split(separator: ":", omittingEmptySubsequences: false).map(String.init) + extraDirectories
        return directories.lazy.map { ($0.isEmpty ? "." : $0) + "/" + name }.first {
            !isWindowsSide($0) && isExecutable($0)
        }
    }

    static func isWindowsSide(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent.lowercased()
        if [".exe", ".cmd", ".bat"].contains(where: name.hasSuffix) { return true }
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        return path.hasPrefix("/") && parts.count >= 3 && parts[0] == "mnt" &&
            parts[1].count == 1 && parts[1].first?.isASCII == true && parts[1].first?.isLetter == true
    }
}

/// A missing native CLI must not fall back to Windows-side credentials.
enum NativeCodexRequired: LocalizedError {
    case missing
    var errorDescription: String? { "Codex CLI not found. Install it on this system (inside WSL on Windows); a Windows-side codex cannot use these logins." }
}
