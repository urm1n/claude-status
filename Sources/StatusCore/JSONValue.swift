import Foundation

/// A JSON tree that keeps object key order and number spelling, so editing the user's
/// `settings.json` only changes the entries we add or remove. (`JSONSerialization` would
/// reorder every key in the file.)
public indirect enum JSONValue: Equatable, Sendable {
    case object([JSONMember])
    case array([JSONValue])
    case string(String)
    case number(String)
    case bool(Bool)
    case null

    public subscript(key: String) -> JSONValue? {
        get {
            guard case .object(let members) = self else { return nil }
            return members.first { $0.key == key }?.value
        }
        set {
            guard case .object(var members) = self else { return }
            if let index = members.firstIndex(where: { $0.key == key }) {
                if let newValue { members[index].value = newValue } else { members.remove(at: index) }
            } else if let newValue {
                members.append(JSONMember(key, newValue))
            }
            self = .object(members)
        }
    }

    public var members: [JSONMember]? {
        if case .object(let members) = self { return members }
        return nil
    }

    public var array: [JSONValue]? {
        if case .array(let items) = self { return items }
        return nil
    }

    public var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }
}

public struct JSONMember: Equatable, Sendable {
    public var key: String
    public var value: JSONValue

    public init(_ key: String, _ value: JSONValue) {
        self.key = key
        self.value = value
    }
}

public struct JSONParseError: Error, CustomStringConvertible {
    public let message: String
    public let offset: Int
    public var description: String { "Invalid JSON at byte \(offset): \(message)" }
}

// MARK: - Parsing

extension JSONValue {
    public static func parse(_ data: Data) throws -> JSONValue {
        var parser = Parser(bytes: Array(data))
        if parser.bytes.starts(with: [0xEF, 0xBB, 0xBF]) { parser.index = 3 }
        parser.skipWhitespace()
        let value = try parser.parseValue(depth: 0)
        parser.skipWhitespace()
        guard parser.index == parser.bytes.count else { throw parser.error("unexpected trailing content") }
        return value
    }

    private struct Parser {
        let bytes: [UInt8]
        var index = 0

        func error(_ message: String) -> JSONParseError { JSONParseError(message: message, offset: index) }

        var current: UInt8? { index < bytes.count ? bytes[index] : nil }

        mutating func skipWhitespace() {
            while let byte = current, byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09 { index += 1 }
        }

        mutating func expect(_ byte: UInt8) throws {
            guard current == byte else { throw error("expected '\(Character(UnicodeScalar(byte)))'") }
            index += 1
        }

        mutating func parseValue(depth: Int) throws -> JSONValue {
            guard depth < 512 else { throw error("nesting too deep") }
            guard let byte = current else { throw error("unexpected end of input") }
            switch byte {
            case UInt8(ascii: "{"): return try parseObject(depth: depth)
            case UInt8(ascii: "["): return try parseArray(depth: depth)
            case UInt8(ascii: "\""): return .string(try parseString())
            case UInt8(ascii: "t"): try literal("true"); return .bool(true)
            case UInt8(ascii: "f"): try literal("false"); return .bool(false)
            case UInt8(ascii: "n"): try literal("null"); return .null
            case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): return try parseNumber()
            default: throw error("unexpected character")
            }
        }

        mutating func literal(_ word: String) throws {
            for byte in word.utf8 { try expect(byte) }
        }

        mutating func parseObject(depth: Int) throws -> JSONValue {
            index += 1
            var members: [JSONMember] = []
            skipWhitespace()
            if current == UInt8(ascii: "}") { index += 1; return .object(members) }
            while true {
                skipWhitespace()
                guard current == UInt8(ascii: "\"") else { throw error("expected object key") }
                let key = try parseString()
                skipWhitespace()
                try expect(UInt8(ascii: ":"))
                skipWhitespace()
                members.append(JSONMember(key, try parseValue(depth: depth + 1)))
                skipWhitespace()
                if current == UInt8(ascii: ",") { index += 1; continue }
                try expect(UInt8(ascii: "}"))
                return .object(members)
            }
        }

        mutating func parseArray(depth: Int) throws -> JSONValue {
            index += 1
            var items: [JSONValue] = []
            skipWhitespace()
            if current == UInt8(ascii: "]") { index += 1; return .array(items) }
            while true {
                skipWhitespace()
                items.append(try parseValue(depth: depth + 1))
                skipWhitespace()
                if current == UInt8(ascii: ",") { index += 1; continue }
                try expect(UInt8(ascii: "]"))
                return .array(items)
            }
        }

        mutating func parseHex4() throws -> UInt32 {
            guard index + 4 <= bytes.count,
                  let value = UInt32(String(decoding: bytes[index..<index + 4], as: UTF8.self), radix: 16)
            else { throw error("bad \\u escape") }
            index += 4
            return value
        }

        mutating func parseString() throws -> String {
            index += 1
            var out: [UInt8] = []
            while true {
                guard let byte = current else { throw error("unterminated string") }
                index += 1
                switch byte {
                case UInt8(ascii: "\""):
                    return String(decoding: out, as: UTF8.self)
                case UInt8(ascii: "\\"):
                    guard let escaped = current else { throw error("unterminated escape") }
                    index += 1
                    switch escaped {
                    case UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: "/"): out.append(escaped)
                    case UInt8(ascii: "b"): out.append(0x08)
                    case UInt8(ascii: "f"): out.append(0x0C)
                    case UInt8(ascii: "n"): out.append(0x0A)
                    case UInt8(ascii: "r"): out.append(0x0D)
                    case UInt8(ascii: "t"): out.append(0x09)
                    case UInt8(ascii: "u"):
                        var code = try parseHex4()
                        if (0xD800...0xDBFF).contains(code), current == UInt8(ascii: "\\"),
                           index + 1 < bytes.count, bytes[index + 1] == UInt8(ascii: "u") {
                            let save = index
                            index += 2
                            let low = try parseHex4()
                            if (0xDC00...0xDFFF).contains(low) {
                                code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                            } else {
                                index = save
                            }
                        }
                        let scalar = Unicode.Scalar(code) ?? "\u{FFFD}"
                        out.append(contentsOf: Array(String(Character(scalar)).utf8))
                    default:
                        throw error("bad escape")
                    }
                case 0x00..<0x20:
                    throw error("control character in string")
                default:
                    out.append(byte)
                }
            }
        }

        mutating func parseNumber() throws -> JSONValue {
            let start = index
            while let byte = current,
                  (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) || byte == UInt8(ascii: "-")
                    || byte == UInt8(ascii: "+") || byte == UInt8(ascii: ".")
                    || byte == UInt8(ascii: "e") || byte == UInt8(ascii: "E") {
                index += 1
            }
            let raw = String(decoding: bytes[start..<index], as: UTF8.self)
            guard Double(raw) != nil else { throw error("bad number") }
            return .number(raw)
        }
    }
}

// MARK: - Serializing

extension JSONValue {
    /// Two-space pretty print, same layout as `JSON.stringify(value, null, 2)` (what Claude Code writes).
    public func serialized() -> String {
        var out = ""
        write(into: &out, level: 0)
        return out
    }

    private func write(into out: inout String, level: Int) {
        let pad = String(repeating: "  ", count: level + 1)
        let closePad = String(repeating: "  ", count: level)
        switch self {
        case .object(let members):
            if members.isEmpty { out += "{}"; return }
            out += "{\n"
            for (i, member) in members.enumerated() {
                out += pad
                JSONValue.writeString(member.key, into: &out)
                out += ": "
                member.value.write(into: &out, level: level + 1)
                out += i == members.count - 1 ? "\n" : ",\n"
            }
            out += closePad + "}"
        case .array(let items):
            if items.isEmpty { out += "[]"; return }
            out += "[\n"
            for (i, item) in items.enumerated() {
                out += pad
                item.write(into: &out, level: level + 1)
                out += i == items.count - 1 ? "\n" : ",\n"
            }
            out += closePad + "]"
        case .string(let value):
            JSONValue.writeString(value, into: &out)
        case .number(let raw):
            out += raw
        case .bool(let value):
            out += value ? "true" : "false"
        case .null:
            out += "null"
        }
    }

    private static func writeString(_ value: String, into out: inout String) {
        out += "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case _ where scalar.value < 0x20:
                out += String(format: "\\u%04x", scalar.value)
            default:
                out.unicodeScalars.append(scalar)
            }
        }
        out += "\""
    }
}
