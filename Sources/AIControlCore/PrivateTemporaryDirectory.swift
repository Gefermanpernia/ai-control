import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// A new owner-only directory with an unpredictable name, for short-lived copies of a login.
///
/// `FileManager`'s item-replacement directory is not used: on Linux it is a predictable, reused name under a
/// shared `/tmp/TemporaryItems` that another user could create first. `mkdtemp` picks a random name, creates
/// it exclusively and gives it mode 0700, which is safe even directly in `/tmp`.
enum PrivateTemporaryDirectory {
    static func create(prefix: String, in parent: String = NSTemporaryDirectory()) throws -> String {
        var template = Array(((parent as NSString).appendingPathComponent(prefix + ".XXXXXXXX")).utf8CString)
        guard let created = template.withUnsafeMutableBufferPointer({ mkdtemp($0.baseAddress!) }) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return String(cString: created)
    }
}
