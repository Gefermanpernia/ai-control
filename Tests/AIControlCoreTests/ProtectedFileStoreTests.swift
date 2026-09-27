import Foundation
import Testing
@testable import AIControlCore

struct ProtectedFileStoreTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("protected-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    private func mode(_ path: String) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.posixPermissions] as? Int
    }

    @Test("Creates owner-only files in owner-only directories and reads them back")
    func createsOwnerOnlyFiles() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProtectedFileStore(path: root.path + "/nested/logins.json")

        #expect(throws: IsolatedKeychainError.missing) { try store.read() }
        var guards = 0
        try store.create(data: Data("one".utf8)) { guards += 1 }

        #expect(try store.read() == Data("one".utf8))
        #expect(guards == 1)
        #expect(mode(store.path) == 0o600)
        #expect(mode(root.path + "/nested") == 0o700)
        #expect(throws: IsolatedKeychainError.duplicate) { try store.create(data: Data("two".utf8)) {} }
    }

    @Test("Updates and compare-and-swap replacements keep owner-only access and leave no temporary files")
    func replacesAtomically() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProtectedFileStore(path: root.path + "/credentials.json")
        try store.create(data: Data("one".utf8)) {}

        try store.update(data: Data("two".utf8)) {}
        try store.replace(expectedData: Data("two".utf8), with: Data("three".utf8)) {}
        var guarded = false
        #expect(throws: IsolatedKeychainError.corrupt) {
            try store.replace(expectedData: Data("two".utf8), with: Data("four".utf8)) { guarded = true }
        }

        #expect(try store.read() == Data("three".utf8))
        #expect(!guarded)
        #expect(mode(store.path) == 0o600)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["credentials.json"])
    }

    @Test("Updating a missing file never creates it, and deleting removes it")
    func updateNeverCreates() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProtectedFileStore(path: root.path + "/logins.json")

        #expect(throws: IsolatedKeychainError.missing) { try store.update(data: Data("x".utf8)) {} }
        #expect(!FileManager.default.fileExists(atPath: store.path))
        try store.create(data: Data("x".utf8)) {}
        try store.delete()
        #expect(!FileManager.default.fileExists(atPath: store.path))
    }

    @Test("Symbolic links are refused instead of followed")
    func refusesSymbolicLinks() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("elsewhere.json")
        try Data("secret".utf8).write(to: target)
        let link = root.appendingPathComponent("credentials.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let store = ProtectedFileStore(path: link.path)

        #expect(throws: IsolatedKeychainError.corrupt) { try store.read() }
        #expect(throws: IsolatedKeychainError.corrupt) { try store.update(data: Data("x".utf8)) {} }
        #expect(try String(contentsOf: target, encoding: .utf8) == "secret")
    }
}
