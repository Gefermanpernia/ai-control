import Foundation

enum JSONPresence: Equatable, Sendable {
    case missing
    case null
    case value(String)
}

struct ScopedJSON: Sendable {
    enum Error: Swift.Error { case invalidJSON, duplicateKey, rootIsNotObject }

    fileprivate struct Member {
        let key: String
        let memberStart: Int
        let value: Range<Int>
        let memberEnd: Int
    }

    private let raw: [UInt8]
    private let members: [Member]
    private let closingBrace: Int

    init(_ source: String) throws {
        var parser = Parser(Array(source.utf8))
        let result = try parser.parseDocument(captureRootMembers: true)
        guard let members = result.members, let closingBrace = result.closingBrace else {
            throw Error.rootIsNotObject
        }
        raw = parser.bytes
        self.members = members
        self.closingBrace = closingBrace
    }

    func presence(of key: String) -> JSONPresence {
        guard let member = members.first(where: { $0.key == key }) else { return .missing }
        let value = String(decoding: raw[member.value], as: UTF8.self)
        return value == "null" ? .null : .value(value)
    }

    func replacing(_ changes: [String: JSONPresence]) throws -> String {
        var source = String(decoding: raw, as: UTF8.self)
        for key in changes.keys.sorted() {
            guard let presence = changes[key] else { continue }
            source = try ScopedJSON(source).replacingOne(key, with: presence)
        }
        return source
    }

    private func replacingOne(_ key: String, with presence: JSONPresence) throws -> String {
        var output = raw
        if let index = members.firstIndex(where: { $0.key == key }) {
            let member = members[index]
            switch presence {
            case .missing:
                let deletion: Range<Int>
                if members.count == 1 {
                    deletion = member.memberStart..<member.memberEnd
                } else if index < members.count - 1 {
                    deletion = member.memberStart..<members[index + 1].memberStart
                } else {
                    deletion = members[index - 1].memberEnd..<member.memberEnd
                }
                output.removeSubrange(deletion)
            case .null:
                output.replaceSubrange(member.value, with: Array("null".utf8))
            case .value(let value):
                try Parser.validateValue(value)
                output.replaceSubrange(member.value, with: Array(value.utf8))
            }
        } else {
            let value: String
            switch presence {
            case .missing: return String(decoding: output, as: UTF8.self)
            case .null: value = "null"
            case .value(let rawValue): value = rawValue
            }
            try Parser.validateValue(value)
            let encodedKey = String(decoding: try JSONEncoder().encode(key), as: UTF8.self)
            let prefix = members.isEmpty ? "" : ","
            output.insert(contentsOf: Array("\(prefix)\(encodedKey):\(value)".utf8), at: closingBrace)
        }
        return String(decoding: output, as: UTF8.self)
    }
}

fileprivate struct Parser {
    struct Result { let members: [ScopedJSON.Member]?; let closingBrace: Int? }
    let bytes: [UInt8]
    private var offset = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    static func validateValue(_ source: String) throws {
        var parser = Parser(Array(source.utf8))
        _ = try parser.parseDocument(captureRootMembers: false)
    }

    mutating func parseDocument(captureRootMembers: Bool) throws -> Result {
        skipWhitespace()
        let result = try parseValue(captureMembers: captureRootMembers)
        skipWhitespace()
        guard offset == bytes.count else { throw ScopedJSON.Error.invalidJSON }
        return result
    }

    private mutating func parseValue(captureMembers: Bool = false) throws -> Result {
        guard offset < bytes.count else { throw ScopedJSON.Error.invalidJSON }
        switch bytes[offset] {
        case 0x7B: return try parseObject(captureMembers: captureMembers)
        case 0x5B: try parseArray()
        case 0x22: _ = try parseString()
        case 0x74: try consume("true")
        case 0x66: try consume("false")
        case 0x6E: try consume("null")
        default: try parseNumber()
        }
        return Result(members: nil, closingBrace: nil)
    }

    private mutating func parseObject(captureMembers: Bool) throws -> Result {
        offset += 1
        skipWhitespace()
        var keys = Set<String>()
        var members: [ScopedJSON.Member] = []
        if consumeIf(0x7D) { return Result(members: captureMembers ? members : nil, closingBrace: offset - 1) }
        while true {
            let memberStart = offset
            let key = try parseString()
            guard keys.insert(key).inserted else { throw ScopedJSON.Error.duplicateKey }
            skipWhitespace(); try expect(0x3A); skipWhitespace()
            let valueStart = offset
            _ = try parseValue()
            let valueEnd = offset
            skipWhitespace()
            members.append(.init(key: key, memberStart: memberStart, value: valueStart..<valueEnd, memberEnd: offset))
            if consumeIf(0x7D) { return Result(members: captureMembers ? members : nil, closingBrace: offset - 1) }
            try expect(0x2C); skipWhitespace()
        }
    }

    private mutating func parseArray() throws {
        offset += 1; skipWhitespace()
        if consumeIf(0x5D) { return }
        while true {
            _ = try parseValue(); skipWhitespace()
            if consumeIf(0x5D) { return }
            try expect(0x2C); skipWhitespace()
        }
    }

    private mutating func parseString() throws -> String {
        let start = offset
        try expect(0x22)
        while offset < bytes.count {
            let byte = bytes[offset]; offset += 1
            if byte == 0x22 {
                let data = Data(bytes[start..<offset])
                guard let value = try? JSONDecoder().decode(String.self, from: data) else { throw ScopedJSON.Error.invalidJSON }
                return value
            }
            guard byte >= 0x20 else { throw ScopedJSON.Error.invalidJSON }
            if byte == 0x5C {
                guard offset < bytes.count else { throw ScopedJSON.Error.invalidJSON }
                let escaped = bytes[offset]; offset += 1
                guard [0x22, 0x5C, 0x2F, 0x62, 0x66, 0x6E, 0x72, 0x74, 0x75].contains(escaped) else { throw ScopedJSON.Error.invalidJSON }
                if escaped == 0x75 {
                    guard offset + 4 <= bytes.count, bytes[offset..<offset + 4].allSatisfy(Self.isHex) else { throw ScopedJSON.Error.invalidJSON }
                    offset += 4
                }
            }
        }
        throw ScopedJSON.Error.invalidJSON
    }

    private mutating func parseNumber() throws {
        let suffix = String(decoding: bytes[offset...], as: UTF8.self)
        let pattern = #"^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?"#
        guard let match = suffix.range(of: pattern, options: .regularExpression) else { throw ScopedJSON.Error.invalidJSON }
        offset += suffix.utf8.distance(from: suffix.utf8.startIndex, to: match.upperBound.samePosition(in: suffix.utf8)!)
    }

    private mutating func consume(_ text: String) throws {
        let value = Array(text.utf8)
        guard offset + value.count <= bytes.count, Array(bytes[offset..<offset + value.count]) == value else { throw ScopedJSON.Error.invalidJSON }
        offset += value.count
    }

    private mutating func expect(_ byte: UInt8) throws {
        guard consumeIf(byte) else { throw ScopedJSON.Error.invalidJSON }
    }

    private mutating func consumeIf(_ byte: UInt8) -> Bool {
        guard offset < bytes.count, bytes[offset] == byte else { return false }
        offset += 1; return true
    }

    private mutating func skipWhitespace() {
        while offset < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[offset]) { offset += 1 }
    }

    private static func isHex(_ byte: UInt8) -> Bool {
        (0x30...0x39).contains(byte) || (0x41...0x46).contains(byte) || (0x61...0x66).contains(byte)
    }
}
