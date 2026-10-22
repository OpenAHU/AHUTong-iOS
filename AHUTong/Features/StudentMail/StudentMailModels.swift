import Foundation

enum StudentMailError: LocalizedError, Equatable {
    case expired, invalidResponse, signInRequired, untrustedRoute
    case unavailable, deliveryUncertain, draftUncertain, moveUncertain, unsupportedDraft
    case attachmentTooLarge
    var errorDescription: String? {
        switch self {
        case .expired: "邮箱会话已失效，请重新连接"
        case .invalidResponse: "邮箱返回了无法识别的数据，请重试"
        case .signInRequired: "请先登录校园账号，再连接校园邮箱"
        case .untrustedRoute: "邮箱登录入口已变化，请稍后重试"
        case .unavailable: "暂时无法连接校园邮箱，请检查网络后重试"
        case .deliveryUncertain: "发送结果尚未确认，请先检查已发送，避免重复发送"
        case .draftUncertain: "保存结果尚未确认，请先检查草稿箱，避免重复保存"
        case .moveUncertain: "移动结果尚未确认，请刷新邮件列表后再操作"
        case .unsupportedDraft: "该草稿含内嵌或云附件，请在学校邮箱网站继续编辑"
        case .attachmentTooLarge: "附件过大，请使用邮箱网页版处理"
        }
    }
}

struct StudentMailFolder: Identifiable, Equatable, Sendable {
    let id: Int
    let name: String
    let total: Int
    let unread: Int
}

struct StudentMailAttachment: Identifiable, Equatable, Sendable {
    var id: String { "\(messageID):\(partID)" }
    let messageID: String
    let partID: String
    let name: String
    let size: Int64
    var sizeText: String { ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }
}

struct StudentMailMessage: Identifiable, Equatable, Sendable {
    let id: String
    let folderID: Int
    let subject: String
    let sender: String
    let summary: String
    let date: String
    let isRead: Bool
    let attachments: [StudentMailAttachment]
    var title: String { subject.isEmpty ? "（无主题）" : subject }
}

struct StudentMailDetail: Equatable, Sendable {
    let id: String
    let subject: String
    let from: [String]
    let to: [String]
    let cc: [String]
    let text: String
    let attachments: [StudentMailAttachment]
}

struct StudentMailContact: Identifiable, Equatable, Sendable {
    var id: String { email.lowercased() }
    let name: String
    let email: String
}

struct StudentMailPage: Sendable {
    let messages: [StudentMailMessage]
    let total: Int
}

struct StudentMailDraftAttachment: Identifiable, Equatable, Sendable {
    let id: Int64
    let name: String
    let size: Int64
    let contentType: String
}

struct StudentMailDraft: Identifiable, Sendable {
    let id = UUID()
    var to = ""
    var cc = ""
    var bcc = ""
    var subject = ""
    var body = ""
    var composeID: String?
    var sessionKey: UUID?
    var attachments: [StudentMailDraftAttachment] = []
    var originalHTML: String?
    var unsupportedResources = false

    var canSend: Bool {
        !StudentMailProtocol.addresses(to).isEmpty
            && StudentMailProtocol.addresses(to + ";" + cc + ";" + bcc).allSatisfy(StudentMailProtocol.validAddress)
            && !unsupportedResources
    }
}

/// Contracts ported from Android's StudentMailProtocol, never a guessed mail API.
enum StudentMailProtocol {
    static func check(_ root: [String: Any]) throws {
        let code = string(root, "code")
        if code.uppercased().contains("SESSION") || code.uppercased().contains("LOGIN")
            || code.uppercased().contains("AUTH") || code == "S_INVALID_SID" { throw StudentMailError.expired }
        guard code == "S_OK" || (["0", "200"].contains(code) && root["success"] as? Bool == true) else {
            throw StudentMailError.invalidResponse
        }
    }

    static func root(_ data: Data) throws -> [String: Any] {
        guard let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StudentMailError.invalidResponse
        }
        try check(value)
        return value
    }

    static func folders(_ data: Data) throws -> [StudentMailFolder] {
        try objects(root(data)["var"]).map {
            let stats = object($0["stats"])
            return StudentMailFolder(id: integer($0, "id"), name: string($0, "name"),
                                     total: integer(stats, "messageCount"), unread: integer(stats, "unreadMessageCount"))
        }
    }

    static func page(_ data: Data) throws -> StudentMailPage {
        let root = try root(data)
        return StudentMailPage(messages: objects(root["var"]).map { item in
            StudentMailMessage(id: string(item, "id"), folderID: integer(item, "fid"),
                subject: string(item, "subject"), sender: string(item, "from"),
                summary: plainText(string(item, "summary")),
                date: string(item, "receivedDate").isEmpty ? string(item, "sentDate") : string(item, "receivedDate"),
                isRead: object(item["flags"])["read"] as? Bool ?? false,
                attachments: attachments(item["attachments"], messageID: string(item, "id")))
        }, total: integer(root, "total"))
    }

    static func detail(_ data: Data, id: String) throws -> StudentMailDetail {
        let item = object(try root(data)["var"])
        let text = string(object(item["text"]), "content")
        return StudentMailDetail(id: id, subject: string(item, "subject"), from: strings(item["from"]),
            to: strings(item["to"]), cc: strings(item["cc"]),
            text: text.isEmpty ? plainText(string(object(item["html"]), "content")) : text,
            attachments: attachments(item["attachments"], messageID: id))
    }

    static func contacts(_ data: Data, recent: Bool) throws -> [StudentMailContact] {
        let data = object(try root(data)["data"])
        if recent {
            return objects(data["contactList"]).compactMap {
                let email = string($0, "email")
                guard validAddress(email) else { return nil }
                let name = string($0, "nickname").isEmpty ? string($0, "name") : string($0, "nickname")
                return StudentMailContact(name: name.isEmpty ? email : name, email: email)
            }
        }
        guard integer(data, "statusCode") == 0 else { throw StudentMailError.invalidResponse }
        return objects(data["personContactVOList"]).flatMap { item in
            strings(item["email"]).filter(validAddress).map {
                StudentMailContact(name: string(item, "qiyeAccountName").isEmpty ? $0 : string(item, "qiyeAccountName"), email: $0)
            }
        }
    }

    static func listBody(folder: Int, start: Int, unread: Bool) -> [String: Any] {
        var body: [String: Any] = ["limit": 30, "start": start, "summaryWindowSize": 30,
            "returnTotal": true, "returnTid": true, "returnTag": true, "returnAttachments": true,
            "order": folder == -3 ? "deferredDate" : "date", "desc": folder != -3,
            "skipLockedFolders": unread || folder < 0]
        var filter: [String: Any] = [:]
        if unread { filter["flags"] = ["read": false] }
        if folder == -1 { filter["label0"] = 1 }
        if folder == -3 { filter["defer"] = ":22000101" }
        body["filter"] = filter
        if unread { body["fids"] = [folder] }
        else if folder == -1 { body["fids"] = [1, 3, -1, -9, -3, 2] }
        else if folder != -3 {
            body["fid"] = folder
            if [1, 2, 3].contains(folder) { body["topFlag"] = "top" }
        }
        return body
    }

    static func readBody(id: String) -> [String: Any] {
        ["id": id, "level": 32, "mode": "html", "markRead": false,
         "returnHeaders": ["Resent-From": "A", "Sender": "A"]]
    }

    static func composeBody(_ draft: StudentMailDraft, account: String, action: String) throws -> [String: Any] {
        guard ["continue", "save", "deliver"].contains(action), !draft.unsupportedResources else {
            throw StudentMailError.unsupportedDraft
        }
        guard draft.attachments.allSatisfy({ $0.id > 0 }) else { throw StudentMailError.invalidResponse }
        var body: [String: Any] = ["delayTime": 0, "returnInfo": true, "action": action,
            "mailTrace": false, "cloudAttachTrace": false, "riskHitIntercept": false,
            "xMailerExt": "Sirius_WEB_WIN_1.66.2", "noticeSenderReceivers": []]
        if let id = draft.composeID { body["id"] = id }
        body["attrs"] = ["subject": draft.subject, "requestReadReceipt": false,
            "to": addresses(draft.to), "cc": addresses(draft.cc), "bcc": addresses(draft.bcc),
            "content": draft.originalHTML ?? "<div>\(escape(draft.body).replacingOccurrences(of: "\n", with: "<br>"))</div>",
            "account": account, "isHtml": true, "saveSentCopy": true,
            "attachments": draft.attachments.map { ["id": $0.id, "name": $0.name, "inlined": false, "deleted": false] as [String: Any] },
            "cloudattachments": []] as [String: Any]
        return body
    }

    static func restoredDraft(_ data: Data, sessionKey: UUID) throws -> StudentMailDraft {
        let item = object(try root(data)["var"])
        let attachments = objects(item["attachments"]).filter { $0["deleted"] as? Bool != true }
        let html = string(item, "content")
        var draft = StudentMailDraft(to: strings(item["to"]).joined(separator: "; "),
            cc: strings(item["cc"]).joined(separator: "; "), bcc: strings(item["bcc"]).joined(separator: "; "),
            subject: string(item, "subject"), body: item["isHtml"] as? Bool == true ? plainText(html) : html,
            composeID: string(item, "id"), sessionKey: sessionKey)
        draft.originalHTML = item["isHtml"] as? Bool == true ? html : nil
        draft.unsupportedResources = item["inlineResources"] as? Bool == true || !objects(item["cloudattachments"]).isEmpty
            || attachments.contains { $0["inlined"] as? Bool == true || !["upload", "internal"].contains(string($0, "type")) }
        draft.attachments = attachments.map {
            StudentMailDraftAttachment(id: Int64(string($0, "id")) ?? 0, name: string($0, "name"),
                size: Int64(string($0, "size")) ?? 0, contentType: string($0, "contentType"))
        }
        guard draft.composeID?.isEmpty == false else { throw StudentMailError.invalidResponse }
        return draft
    }

    static func addresses(_ value: String) -> [String] {
        var seen = Set<String>()
        return value.components(separatedBy: CharacterSet(charactersIn: ";；,，\n\r"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }
    static func validAddress(_ value: String) -> Bool {
        value.range(of: #"^[^\s<>@,;]+@[^\s<>@,;]+\.[^\s<>@,;]+$"#, options: .regularExpression) != nil
    }
    static func recipient(_ display: String) -> String {
        if let start = display.lastIndex(of: "<"), let end = display.lastIndex(of: ">"), start < end {
            return String(display[display.index(after: start)..<end])
        }
        return display
    }
    static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
    static func plainText(_ html: String) -> String {
        var text = html.replacingOccurrences(of: #"(?is)<(script|style)\b[^>]*>.*?</\1\s*>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)<br\s*/?>|</(?:p|div|li|tr|h[1-6])\s*>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]*>"#, with: "", options: .regularExpression)
        guard let pattern = try? NSRegularExpression(pattern: #"&#(x[0-9A-Fa-f]+|[0-9]+);"#) else { return text }
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range(at: 1), in: text), let full = Range(match.range, in: text) else { continue }
            let raw = String(text[range])
            let number = raw.hasPrefix("x") ? UInt32(raw.dropFirst(), radix: 16) : UInt32(raw)
            if let number, let scalar = UnicodeScalar(number) { text.replaceSubrange(full, with: String(scalar)) }
        }
        for (entity, value) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")] {
            text = text.replacingOccurrences(of: entity, with: value)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func string(_ value: [String: Any], _ key: String) -> String {
        if let string = value[key] as? String { return string }
        return (value[key] as? NSNumber)?.stringValue ?? ""
    }
    static func integer(_ value: [String: Any], _ key: String) -> Int { Int(string(value, key)) ?? 0 }
    static func object(_ value: Any?) -> [String: Any] { value as? [String: Any] ?? [:] }
    static func objects(_ value: Any?) -> [[String: Any]] { value as? [[String: Any]] ?? [] }
    static func strings(_ value: Any?) -> [String] {
        if let values = value as? [String] { return values }
        if let value = value as? String, !value.isEmpty { return [value] }
        return []
    }
    private static func attachments(_ value: Any?, messageID: String) -> [StudentMailAttachment] {
        objects(value).map {
            let size = Int64(string($0, "estimateSize")) ?? 0
            return StudentMailAttachment(messageID: messageID, partID: string($0, "id"),
                name: string($0, "filename"), size: size > 0 ? size : Int64(string($0, "contentLength")) ?? 0)
        }
    }
}
