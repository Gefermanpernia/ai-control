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
///
/// The store does not lock: `update` and `replace` read and then rename, so callers that mutate
/// AI Control's own files hold `ManagerFileLock` for the whole command (every current caller does).
/// Claude Code does not take that lock, which is why `.credentials.json` changes go through `replace`.
struct ProtectedFileStore: ClaudeLoginDataStore, IsolatedCredentialItem {
    let path: String
    var beforeMutation: () throws -> Void = {}

    /// Opens the file once without following links and checks that same descriptor, so the file cannot
    /// be swapped between the check and the read. A file others can access is repaired to owner-only.
    func read() throws -> Data {
        // O_NONBLOCK keeps a FIFO planted at the path from blocking the open; it is refused below.
        let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw errno == ENOENT ? IsolatedKeychainError.missing : IsolatedKeychainError.corrupt
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0, (metadata.st_mode & S_IFMT) == S_IFREG,
              metadata.st_uid == geteuid() else {
            throw IsolatedKeychainError.corrupt
        }
        if metadata.st_mode & 0o077 != 0 {
            guard fchmod(descriptor, 0o600) == 0 else { throw IsolatedKeychainError.operatingSystem(OSStatus(errno)) }
        }
        guard let data = try? handle.readToEnd() else { throw IsolatedKeychainError.corrupt }
        return data ?? Data()
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
