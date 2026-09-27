import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// A small secret file readable only by its owner, replaced in one rename.
///
/// Used wherever there is no Keychain: Claude Code itself keeps its Linux login in such a file
/// (`~/.claude/.credentials.json`, mode 600), and AI Control keeps its saved logins the same way there.
/// Symbolic links and files owned by another user are refused rather than followed.
struct ProtectedFileStore: ClaudeLoginDataStore, IsolatedCredentialItem {
    let path: String
    var beforeMutation: () throws -> Void = {}

    func read() throws -> Data {
        try checkedExisting()
        guard let data = FileManager.default.contents(atPath: path) else { throw IsolatedKeychainError.corrupt }
        return data
    }

    func create(data: Data) throws { try create(data: data, guardedBy: beforeMutation) }
    func update(data: Data) throws { try update(data: data, guardedBy: beforeMutation) }

    func create(data: Data, guardedBy guardMutation: () throws -> Void) throws {
        do {
            try checkedExisting()
            throw IsolatedKeychainError.duplicate
        } catch IsolatedKeychainError.missing {}
        try guardMutation()
        try writeAtomically(data)
    }

    func update(data: Data, guardedBy guardMutation: () throws -> Void) throws {
        _ = try read()
        try guardMutation()
        try writeAtomically(data)
    }

    func replace(expectedData: Data, with data: Data, guardedBy guardMutation: () throws -> Void) throws {
        guard try read() == expectedData else { throw IsolatedKeychainError.corrupt }
        try guardMutation()
        try writeAtomically(data)
    }

    func delete() throws {
        try checkedExisting()
        guard unlink(path) == 0 else { throw IsolatedKeychainError.operatingSystem(OSStatus(errno)) }
    }

    /// Throws `missing` when absent and `corrupt` for anything but a regular file owned by this user.
    private func checkedExisting() throws {
        var metadata = stat()
        guard lstat(path, &metadata) == 0 else {
            throw errno == ENOENT ? IsolatedKeychainError.missing : IsolatedKeychainError.corrupt
        }
        guard (metadata.st_mode & S_IFMT) == S_IFREG, metadata.st_uid == geteuid() else {
            throw IsolatedKeychainError.corrupt
        }
    }

    private func writeAtomically(_ data: Data) throws {
        let directory = (path as NSString).deletingLastPathComponent
        if !FileManager.default.fileExists(atPath: directory) {
            try FileManager.default.createDirectory(
                atPath: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
            )
        }
        let temporary = directory + "/." + (path as NSString).lastPathComponent + ".aicontrol-" + UUID().uuidString
        let descriptor = open(temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw IsolatedKeychainError.operatingSystem(OSStatus(errno)) }
        var renamed = false
        defer { if !renamed { unlink(temporary) } }
        let written = data.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
        let synced = fsync(descriptor) == 0
        close(descriptor)
        guard written == data.count, synced, rename(temporary, path) == 0 else {
            throw IsolatedKeychainError.operatingSystem(OSStatus(errno))
        }
        renamed = true
        let directoryDescriptor = open(directory, O_RDONLY)
        if directoryDescriptor >= 0 {
            _ = fsync(directoryDescriptor)
            close(directoryDescriptor)
        }
    }
}
