import Foundation

struct LostFoundCampus: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let campusName: String
}

struct LostFoundType: Codable, Identifiable, Equatable, Sendable {
    let typeId: String
    let typeName: String
    var id: String { typeId }
}

struct LostFoundImage: Codable, Identifiable, Equatable, Sendable {
    let imgId: String
    let imgPath: String
    var id: String { imgId }
}

struct LostFoundUser: Codable, Equatable, Sendable {
    let idNumber: String?
    let userName: String?
}

struct LostFoundItem: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let phone: String?
    let linkman: String?
    let createtime: String?
    let state: Int
    let typeid: String?
    let campusid: String?
    let num1: String?
    let campusName: String?
    let imgs: [LostFoundImage]
    let pubuser: LostFoundUser?
    let lostType: LostFoundType?

    func matches(query: String, campusID: String?, typeID: String?) -> Bool {
        guard campusID == nil || campusid == campusID,
              typeID == nil || typeid == typeID else { return false }
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return [title, phone, linkman, campusName, lostType?.typeName, pubuser?.userName, num1, createtime]
            .compactMap { $0 }
            .contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

struct LostFoundPage: Codable, Equatable, Sendable {
    let pageNum: Int
    let pageSize: Int
    let total: Int
    let pages: Int
    let list: [LostFoundItem]
}

struct LostFoundPublishDraft: Equatable, Sendable {
    var contact = ""
    var phone = ""
    var title = ""
    var documentNumber = ""
    var campusID: String?
    var typeID: String?
    var state = 1

    var validationMessage: String? {
        if contact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            campusID == nil || typeID == nil {
            return "请填写完整信息"
        }
        let digits = phone.filter(\.isNumber)
        if digits.count < 7 { return "请填写有效联系电话" }
        return nil
    }
}

struct LostFoundCatalog: Codable, Equatable, Sendable {
    let campuses: [LostFoundCampus]
    let types: [LostFoundType]
}

protocol LostFoundRemote: Sendable {
    func catalog() async throws -> LostFoundCatalog
    func page(state: Int, page: Int, size: Int) async throws -> LostFoundPage
    func ownedPosts(userID: String) async throws -> [LostFoundItem]
    func publish(_ draft: LostFoundPublishDraft) async throws -> LostFoundItem
    func delete(id: String) async throws
}
