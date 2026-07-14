import Foundation

private struct ObjectEnvelope<Value: Decodable>: Decodable {
    let code: Int
    let msg: String
    let object: Value
}

private struct MutationEnvelope: Decodable {
    let code: Int
    let msg: String?
}

private struct PublishPayload: Encodable {
    let imgs: [String] = []
    let linkman: String
    let phone: String
    let typeid: String
    let num1: String?
    let campusid: String
    let title: String
    let state: String
    let auditresult = 1
}

struct CampusLostFoundRemote: LostFoundRemote {
    private let client: CampusAuthenticatedClient
    private let baseURL = URL(string: "https://adwmh.ahu.edu.cn")!

    init(campusAPI: any CampusCoreAPI) {
        client = CampusAuthenticatedClient(campusAPI: campusAPI)
    }

    func catalog() async throws -> LostFoundCatalog {
        async let campusesData = client.data(url: baseURL.appendingPathComponent("lostfound/campus/all"))
        async let typesData = client.data(url: baseURL.appendingPathComponent("lostfound/type/all"))
        let campuses = try JSONDecoder().decode(ObjectEnvelope<[LostFoundCampus]>.self, from: await campusesData)
        let types = try JSONDecoder().decode(ObjectEnvelope<[LostFoundType]>.self, from: await typesData)
        guard Self.success(campuses.code), Self.success(types.code) else {
            throw CampusWebError.server(campuses.code == 0 ? types.msg : campuses.msg)
        }
        return LostFoundCatalog(campuses: campuses.object, types: types.object)
    }

    func page(state: Int, page: Int, size: Int) async throws -> LostFoundPage {
        let url = baseURL.appendingPathComponent("lostfound/all").appendingQueryItems([
            URLQueryItem(name: "pageNo", value: String(page)),
            URLQueryItem(name: "pageSize", value: String(size)),
            URLQueryItem(name: "state", value: String(state))
        ])
        let envelope = try JSONDecoder().decode(
            ObjectEnvelope<LostFoundPage>.self,
            from: await client.data(url: url)
        )
        guard Self.success(envelope.code) else { throw CampusWebError.server(envelope.msg) }
        return envelope.object
    }

    func publish(_ draft: LostFoundPublishDraft) async throws -> LostFoundItem {
        if let message = draft.validationMessage { throw CampusWebError.server(message) }
        let payload = PublishPayload(
            linkman: draft.contact,
            phone: draft.phone,
            typeid: draft.typeID!,
            num1: draft.documentNumber.isEmpty ? nil : draft.documentNumber,
            campusid: draft.campusID!,
            title: draft.title,
            state: String(draft.state)
        )
        let data = try await client.data(
            url: baseURL.appendingPathComponent("lostfound/saveupdate"),
            method: "POST",
            body: try JSONEncoder().encode(payload),
            contentType: "application/json"
        )
        let response = try JSONDecoder().decode(MutationEnvelope.self, from: data)
        guard Self.success(response.code) else { throw CampusWebError.server(response.msg ?? "发布失败") }
        return LostFoundItem(
            id: UUID().uuidString,
            title: draft.title,
            phone: draft.phone,
            linkman: draft.contact,
            createtime: nil,
            state: draft.state,
            typeid: draft.typeID,
            campusid: draft.campusID,
            num1: draft.documentNumber.isEmpty ? nil : draft.documentNumber,
            campusName: nil,
            imgs: [],
            pubuser: nil,
            lostType: nil
        )
    }

    func delete(id: String) async throws {
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "id", value: id)]
        let body = components.percentEncodedQuery?.data(using: .utf8)
        let data = try await client.data(
            url: baseURL.appendingPathComponent("lostfound/delete"),
            method: "POST",
            body: body,
            contentType: "application/x-www-form-urlencoded"
        )
        let response = try JSONDecoder().decode(MutationEnvelope.self, from: data)
        guard Self.success(response.code) else { throw CampusWebError.server(response.msg ?? "删除失败") }
    }

    private static func success(_ code: Int) -> Bool { code == 0 || code == 200 }
}

actor DemoLostFoundRemote: LostFoundRemote {
    private var items = Self.fixtures

    func catalog() -> LostFoundCatalog {
        LostFoundCatalog(
            campuses: [LostFoundCampus(id: "1", campusName: "磬苑校区"), LostFoundCampus(id: "2", campusName: "龙河校区")],
            types: [
                LostFoundType(typeId: "1", typeName: "校园卡"),
                LostFoundType(typeId: "2", typeName: "电子设备"),
                LostFoundType(typeId: "3", typeName: "证件资料"),
                LostFoundType(typeId: "4", typeName: "生活用品")
            ]
        )
    }

    func page(state: Int, page: Int, size: Int) -> LostFoundPage {
        let matching = items.filter { $0.state == state }
        let start = min((page - 1) * size, matching.count)
        let end = min(start + size, matching.count)
        return LostFoundPage(
            pageNum: page,
            pageSize: size,
            total: matching.count,
            pages: max(1, Int(ceil(Double(matching.count) / Double(size)))),
            list: Array(matching[start..<end])
        )
    }

    func publish(_ draft: LostFoundPublishDraft) throws -> LostFoundItem {
        if let message = draft.validationMessage { throw CampusWebError.server(message) }
        let item = LostFoundItem(
            id: "demo-owned-\(items.count + 1)",
            title: draft.title,
            phone: draft.phone,
            linkman: draft.contact,
            createtime: "2026-07-14 10:05:00",
            state: draft.state,
            typeid: draft.typeID,
            campusid: draft.campusID,
            num1: draft.documentNumber.isEmpty ? nil : draft.documentNumber,
            campusName: draft.campusID == "2" ? "龙河校区" : "磬苑校区",
            imgs: [],
            pubuser: LostFoundUser(idNumber: "AB220001", userName: "测试同学"),
            lostType: [
                LostFoundType(typeId: "1", typeName: "校园卡"),
                LostFoundType(typeId: "2", typeName: "电子设备"),
                LostFoundType(typeId: "3", typeName: "证件资料"),
                LostFoundType(typeId: "4", typeName: "生活用品")
            ].first { $0.id == draft.typeID }
        )
        items.insert(item, at: 0)
        return item
    }

    func delete(id: String) throws {
        guard let index = items.firstIndex(where: { $0.id == id && $0.pubuser?.idNumber == "AB220001" }) else {
            throw CampusWebError.server("只能删除自己发布的帖子")
        }
        items.remove(at: index)
    }

    static let fixtures = [
        LostFoundItem(id: "demo-lost-1", title: "文典阁三楼捡到 U 盘 - 请描述外观后领取", phone: "13900001000", linkman: "Mock 同学", createtime: "2026-07-14 09:00:00", state: 1, typeid: "2", campusid: "1", num1: "文典阁 3F 自习区", campusName: "磬苑校区", imgs: [], pubuser: LostFoundUser(idNumber: "U20260002", userName: "Mock 同学"), lostType: LostFoundType(typeId: "2", typeName: "电子设备")),
        LostFoundItem(id: "demo-lost-2", title: "文典阁三楼捡到 U 盘 - 请描述外观后领取", phone: "13900001000", linkman: "Mock 同学", createtime: "2026-07-13 18:30:00", state: 1, typeid: "2", campusid: "1", num1: "文典阁 3F 自习区", campusName: "磬苑校区", imgs: [], pubuser: LostFoundUser(idNumber: "U20260003", userName: "Mock 同学"), lostType: LostFoundType(typeId: "2", typeName: "电子设备")),
        LostFoundItem(id: "demo-owned-1", title: "实验中心捡到蓝牙耳机 - 物品保存在学院办公室", phone: "13800000000", linkman: "测试同学", createtime: "2026-07-13 15:10:00", state: 1, typeid: "2", campusid: "1", num1: "实验中心 5F", campusName: "磬苑校区", imgs: [], pubuser: LostFoundUser(idNumber: "AB220001", userName: "测试同学"), lostType: LostFoundType(typeId: "2", typeName: "电子设备")),
        LostFoundItem(id: "demo-found-1", title: "寻找校园卡和钥匙 - 蓝色挂绳，钥匙上有小标签", phone: "13700002000", linkman: "Mock 同学", createtime: "2026-07-14 08:00:00", state: 2, typeid: "1", campusid: "2", num1: "龙河教学楼 204", campusName: "龙河校区", imgs: [], pubuser: LostFoundUser(idNumber: "U20260004", userName: "Mock 同学"), lostType: LostFoundType(typeId: "1", typeName: "校园卡"))
    ]
}
