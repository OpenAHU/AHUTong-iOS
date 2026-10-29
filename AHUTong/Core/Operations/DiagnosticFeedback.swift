import CryptoKit
import Foundation
import Security

struct DiagnosticFeedbackPreview: Identifiable, Sendable {
    struct LogAttachment: Sendable { let filename: String; let text: String }
    let id = UUID()
    let generation: Int
    let message: String
    let associatedEventID: String?
    let attachments: [LogAttachment]
    var displayText: String {
        ([message] + attachments.map { "【\($0.filename)】\n\($0.text)" }).filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
    init(message: String, categories: Set<DiagnosticLogCategory>, log: DiagnosticLog = .shared) {
        generation = log.generation
        self.message = DiagnosticText.redacted(String(message.prefix(4_096)), includeIdentity: false)
        associatedEventID = categories.contains(.error) && log === DiagnosticLog.shared ? AppDiagnostics.shared.latestErrorID : nil
        attachments = DiagnosticLogCategory.allCases.filter(categories.contains).map {
            let value = log.snapshot($0)
            return .init(filename: "\($0.rawValue).txt", text: value.isEmpty ? "暂无记录" : value)
        }
    }
}

enum DiagnosticFeedbackError: LocalizedError {
    case expired, encryption
    var errorDescription: String? {
        switch self {
        case .expired: "诊断已关闭或账号已变化，请重新预览。"
        case .encryption: "日志加密失败，请重试。"
        }
    }
}

enum DiagnosticLogExport {
    static func encrypt(_ text: String, publicDER: Data) throws -> Data {
        // Android exports use a SubjectPublicKeyInfo public key; Security takes
        // the contained PKCS#1 RSA key. Never ship or request the private key.
        let keyData = try rsaKey(in: publicDER)
        let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPublic]
        guard let publicKey = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, nil) else { throw DiagnosticFeedbackError.encryption }
        let key = SymmetricKey(size: .bits256)
        let keyID = SHA256.hash(data: publicDER).map { String(format: "%02x", $0) }.joined().prefix(16)
        let format = "AHUTONG-LOG-1", algorithm = "RSA-OAEP-SHA256+A256GCM"
        let aad = Data("\(format)|\(algorithm)|\(keyID)".utf8)
        let sealed = try AES.GCM.seal(Data(text.utf8), using: key, authenticating: aad)
        let secret = key.withUnsafeBytes { Data($0) }
        guard let wrapped = SecKeyCreateEncryptedData(publicKey, .rsaEncryptionOAEPSHA256, secret as CFData, nil) as Data? else { throw DiagnosticFeedbackError.encryption }
        return try JSONSerialization.data(withJSONObject: [
            "format": format, "algorithm": algorithm, "keyId": String(keyID),
            "wrappedKey": wrapped.base64EncodedString(), "nonce": Data(sealed.nonce).base64EncodedString(),
            "ciphertext": (sealed.ciphertext + sealed.tag).base64EncodedString()
        ], options: [.sortedKeys])
    }

    static func write(_ preview: DiagnosticFeedbackPreview, directory: URL? = nil) throws -> URL {
        guard preview.generation == DiagnosticLog.shared.generation else { throw DiagnosticFeedbackError.expired }
        guard let keyURL = Bundle.main.url(forResource: "feedback_export_public_key", withExtension: "pem"),
              let pem = try? String(contentsOf: keyURL, encoding: .utf8),
              let der = Data(base64Encoded: pem.components(separatedBy: .newlines).filter { !$0.hasPrefix("-----") }.joined()) else { throw DiagnosticFeedbackError.encryption }
        let encrypted = try encrypt(preview.displayText, publicDER: der)
        guard preview.generation == DiagnosticLog.shared.generation else { throw DiagnosticFeedbackError.expired }
        let folder = directory ?? FileManager.default.temporaryDirectory.appendingPathComponent("feedback-exports", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for item in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey]) {
            if let date = try item.resourceValues(forKeys: [.creationDateKey]).creationDate, date.timeIntervalSinceNow < -86_400 { try? FileManager.default.removeItem(at: item) }
        }
        let url = folder.appendingPathComponent("AHUTong-\(preview.id.uuidString).ahulog")
        try encrypted.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    private static func rsaKey(in data: Data) throws -> Data {
        var index = 0
        func value(_ tag: UInt8) throws -> Data {
            guard index + 2 <= data.count, data[index] == tag else { throw DiagnosticFeedbackError.encryption }
            index += 1
            var length = Int(data[index]); index += 1
            if length & 0x80 != 0 {
                let count = length & 0x7f
                guard (1...4).contains(count), index + count <= data.count else { throw DiagnosticFeedbackError.encryption }
                length = 0
                for _ in 0..<count { length = length * 256 + Int(data[index]); index += 1 }
            }
            guard index + length <= data.count else { throw DiagnosticFeedbackError.encryption }
            defer { index += length }
            return data.subdata(in: index..<index + length)
        }
        let outer = try value(0x30)
        // Parse the two fields inside the outer sequence without accepting arbitrary key formats.
        let offset = data.count - outer.count
        index = offset
        _ = try value(0x30)
        let bits = try value(0x03)
        guard bits.first == 0, index == data.count else { throw DiagnosticFeedbackError.encryption }
        return Data(bits.dropFirst())
    }
}
