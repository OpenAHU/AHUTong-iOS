import Foundation

enum StrictServerFormTestDecoderError: Error {
    case nonASCIITransport
    case invalidPair
    case invalidPercentEscape
    case invalidUTF8
    case duplicateName
}

/// Test-only server semantics, intentionally implemented with Foundation's
/// percent decoder rather than the production byte encoder or decoder.
enum StrictServerFormTestDecoder {
    static func values(_ data: Data) throws -> [String: String] {
        guard let body = String(data: data, encoding: .ascii) else {
            throw StrictServerFormTestDecoderError.nonASCIITransport
        }
        guard !body.isEmpty else { return [:] }
        var result: [String: String] = [:]
        for pair in body.split(separator: "&", omittingEmptySubsequences: false) {
            guard let separator = pair.firstIndex(of: "=") else {
                throw StrictServerFormTestDecoderError.invalidPair
            }
            let name = try decode(String(pair[..<separator]))
            let value = try decode(String(pair[pair.index(after: separator)...]))
            guard result.updateValue(value, forKey: name) == nil else {
                throw StrictServerFormTestDecoderError.duplicateName
            }
        }
        return result
    }

    private static func decode(_ value: String) throws -> String {
        let scalars = Array(value.unicodeScalars)
        var index = 0
        while index < scalars.count {
            if scalars[index].value == 37 {
                guard index + 2 < scalars.count,
                      isHexadecimal(scalars[index + 1]),
                      isHexadecimal(scalars[index + 2]) else {
                    throw StrictServerFormTestDecoderError.invalidPercentEscape
                }
                index += 3
            } else {
                index += 1
            }
        }
        let plusDecoded = value.replacingOccurrences(of: "+", with: " ")
        guard let decoded = plusDecoded.removingPercentEncoding else {
            throw StrictServerFormTestDecoderError.invalidUTF8
        }
        return decoded
    }

    private static func isHexadecimal(_ scalar: UnicodeScalar) -> Bool {
        (48...57).contains(scalar.value)
            || (65...70).contains(scalar.value)
            || (97...102).contains(scalar.value)
    }
}
