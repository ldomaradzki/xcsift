import Foundation

/// A structure-preserving, `Sendable` representation of a JSON-RPC message.
///
/// Re-serialization normalises three things: object keys come out sorted, an integral double loses
/// its `.0`, and a non-finite double becomes `null`. That is why the proxy decodes a message only
/// to decide whether it needs rewriting — messages forwarded untouched are copied byte for byte, so
/// key order and number formatting of pass-through traffic stay exactly as the peer wrote them.
enum JSONValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}

// MARK: - Decoding

extension JSONValue: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    /// Decodes one JSON-RPC message, returning `nil` for anything that is not valid JSON.
    ///
    /// A `nil` result is not an error for the proxy: the bytes are forwarded verbatim so a peer
    /// that writes non-JSON to the message stream behaves exactly as it would without the proxy.
    static func parse(_ data: Data) -> JSONValue? {
        try? JSONDecoder().decode(JSONValue.self, from: data)
    }
}

// MARK: - Serialization

extension JSONValue {
    /// Serializes to compact single-line JSON, the framing the MCP stdio transport requires.
    ///
    /// Object keys are emitted in sorted order so a rewritten message is byte-for-byte
    /// reproducible; tests and diffs depend on that.
    func serialized() -> Data {
        var output = Data()
        write(into: &output)
        return output
    }

    private func write(into output: inout Data) {
        switch self {
        case .null:
            output.append(contentsOf: Array("null".utf8))
        case let .bool(value):
            output.append(contentsOf: Array((value ? "true" : "false").utf8))
        case let .int(value):
            output.append(contentsOf: Array(String(value).utf8))
        case let .double(value):
            output.append(contentsOf: Array(Self.encode(value).utf8))
        case let .string(value):
            Self.writeString(value, into: &output)
        case let .array(values):
            output.append(UInt8(ascii: "["))
            for (index, value) in values.enumerated() {
                if index > 0 { output.append(UInt8(ascii: ",")) }
                value.write(into: &output)
            }
            output.append(UInt8(ascii: "]"))
        case let .object(values):
            output.append(UInt8(ascii: "{"))
            for (index, key) in values.keys.sorted().enumerated() {
                if index > 0 { output.append(UInt8(ascii: ",")) }
                Self.writeString(key, into: &output)
                output.append(UInt8(ascii: ":"))
                values[key]?.write(into: &output)
            }
            output.append(UInt8(ascii: "}"))
        }
    }

    private static func encode(_ value: Double) -> String {
        guard value.isFinite else { return "null" }
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int64(value))
        }
        return String(value)
    }

    private static func writeString(_ value: String, into output: inout Data) {
        output.append(UInt8(ascii: "\""))
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"":
                output.append(contentsOf: Array("\\\"".utf8))
            case "\\":
                output.append(contentsOf: Array("\\\\".utf8))
            case "\n":
                output.append(contentsOf: Array("\\n".utf8))
            case "\r":
                output.append(contentsOf: Array("\\r".utf8))
            case "\t":
                output.append(contentsOf: Array("\\t".utf8))
            case let scalar where scalar.value < 0x20:
                output.append(contentsOf: Array(String(format: "\\u%04x", scalar.value).utf8))
            default:
                output.append(contentsOf: Array(String(scalar).utf8))
            }
        }
        output.append(UInt8(ascii: "\""))
    }
}

// MARK: - Accessors

extension JSONValue {
    var objectValue: [String: JSONValue]? {
        guard case let .object(value) = self else { return nil }
        return value
    }

    var arrayValue: [JSONValue]? {
        guard case let .array(value) = self else { return nil }
        return value
    }

    var stringValue: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }

    var intValue: Int? {
        switch self {
        case let .int(value): return value
        case let .double(value): return Int(exactly: value.rounded())
        default: return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case let .int(value): return Double(value)
        case let .double(value): return value
        default: return nil
        }
    }

    var boolValue: Bool? {
        guard case let .bool(value) = self else { return nil }
        return value
    }

    subscript(key: String) -> JSONValue? {
        get { objectValue?[key] }
        set {
            guard case var .object(object) = self else {
                assertionFailure("setting member '\(key)' on a JSON value that is not an object")
                return
            }
            object[key] = newValue
            self = .object(object)
        }
    }
}
