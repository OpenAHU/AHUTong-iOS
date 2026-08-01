import Foundation

/// Byte-for-byte compatibility with OkHttp 5.1.0 `FormBody.Builder.add`.
/// URL query encoding intentionally remains separate and uses URLComponents.
enum YCardFormURLEncoder {
    static func data(
        _ fields: [(name: String, value: String)]
    ) -> Data {
        var encoded = [UInt8]()
        encoded.reserveCapacity(fields.reduce(0) {
            $0 + $1.name.utf8.count + $1.value.utf8.count + 2
        })
        for (index, field) in fields.enumerated() {
            if index > 0 { encoded.append(38) }
            appendComponent(field.name, to: &encoded)
            encoded.append(61)
            appendComponent(field.value, to: &encoded)
        }
        return Data(encoded)
    }

    private static func appendComponent(
        _ value: String,
        to output: inout [UInt8]
    ) {
        let hexadecimal = Array("0123456789ABCDEF".utf8)
        for byte in value.utf8 {
            if byte == 32 {
                output.append(43)
            } else if isFormSafe(byte) {
                output.append(byte)
            } else {
                output.append(37)
                output.append(hexadecimal[Int(byte >> 4)])
                output.append(hexadecimal[Int(byte & 0x0f)])
            }
        }
    }

    private static func isFormSafe(_ byte: UInt8) -> Bool {
        (48...57).contains(byte)
            || (65...90).contains(byte)
            || (97...122).contains(byte)
            || byte == 42
            || byte == 45
            || byte == 46
            || byte == 95
    }
}

enum YCardServerFormDecodingError: Error, Equatable {
    case invalidPair
    case invalidPercentEscape
    case invalidUTF8
    case emptyName
    case duplicateName
}

/// Strict server-side form semantics. This implementation is deliberately
/// independent from the client encoder so policy validation cannot hide an
/// encoder canonicalization defect.
enum YCardServerFormDecoder {
    static func values(_ data: Data) throws -> [String: String] {
        guard !data.isEmpty else { return [:] }
        let bytes = [UInt8](data)
        var result: [String: String] = [:]
        for pair in bytes.split(separator: 38, omittingEmptySubsequences: false) {
            guard let separator = pair.firstIndex(of: 61) else {
                throw YCardServerFormDecodingError.invalidPair
            }
            let rawName = pair[..<separator]
            let rawValue = pair[pair.index(after: separator)..<pair.endIndex]
            let name = try decodeComponent(rawName)
            let value = try decodeComponent(rawValue)
            guard !name.isEmpty else {
                throw YCardServerFormDecodingError.emptyName
            }
            guard result.updateValue(value, forKey: name) == nil else {
                throw YCardServerFormDecodingError.duplicateName
            }
        }
        return result
    }

    private static func decodeComponent<C: Collection>(
        _ encoded: C
    ) throws -> String where C.Element == UInt8 {
        let bytes = Array(encoded)
        var decoded = [UInt8]()
        decoded.reserveCapacity(bytes.count)
        var index = 0
        while index < bytes.count {
            switch bytes[index] {
            case 43:
                decoded.append(32)
                index += 1
            case 37:
                guard index + 2 < bytes.count,
                      let high = hexadecimalValue(bytes[index + 1]),
                      let low = hexadecimalValue(bytes[index + 2]) else {
                    throw YCardServerFormDecodingError.invalidPercentEscape
                }
                decoded.append((high << 4) | low)
                index += 3
            default:
                decoded.append(bytes[index])
                index += 1
            }
        }
        guard let value = String(bytes: decoded, encoding: .utf8) else {
            throw YCardServerFormDecodingError.invalidUTF8
        }
        return value
    }

    private static func hexadecimalValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 48...57: byte - 48
        case 65...70: byte - 55
        case 97...102: byte - 87
        default: nil
        }
    }
}
