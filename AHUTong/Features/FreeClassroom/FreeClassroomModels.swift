import Foundation

struct ClassroomCampus: Identifiable, Equatable, Sendable {
    let id: Int
    let name: String

    static let all = [
        ClassroomCampus(id: 1, name: "磬苑校区"),
        ClassroomCampus(id: 2, name: "龙河校区")
    ]
}

struct ClassroomBuilding: Codable, Identifiable, Equatable, Sendable {
    let code: String
    let enabled: Bool
    let id: Int
    let nameZh: String
}

struct FreeClassroomRoom: Codable, Identifiable, Equatable, Sendable {
    struct Building: Codable, Equatable, Sendable {
        let id: Int
        let nameZh: String
    }

    let building: Building
    let code: String
    let floor: Int
    let id: Int
    let nameZh: String
    let remark: String?
    let seats: Int
}

struct FreeClassroomQuery: Equatable, Sendable {
    let campusID: Int
    let buildingIDs: [Int]
    let units: [Int]
    let startDate: Date
    let endDate: Date
}

protocol FreeClassroomRemote: Sendable {
    func buildings(campusID: Int) async throws -> [ClassroomBuilding]
    func rooms(query: FreeClassroomQuery) async throws -> [FreeClassroomRoom]
}

private struct FreeRoomEnvelope: Decodable {
    let roomList: [FreeClassroomRoom]
}

private struct FreeRoomRequest: Encodable {
    struct Segment: Encodable {
        let endDateTime: String
        let endTime = ""
        let startDateTime: String
        let startTime = ""
        let units: [String]
        let weekdays: [String] = []
    }

    let buildingId: String
    let campusId: String
    let dateTimeSegmentCmd: Segment
    let hasDataPermission = false
    let roomId = ""
    let seatsForLessonGte = ""
}

struct CampusFreeClassroomRemote: FreeClassroomRemote {
    private let client: CampusAuthenticatedClient
    private let baseURL = URL(string: "https://jw.ahu.edu.cn")!

    init(campusAPI: any CampusCoreAPI) {
        client = CampusAuthenticatedClient(campusAPI: campusAPI)
    }

    func buildings(campusID: Int) async throws -> [ClassroomBuilding] {
        let url = baseURL
            .appendingPathComponent("student/ws/room/get-buildings")
            .appendingQueryItems([
                URLQueryItem(name: "campusId", value: String(campusID)),
                URLQueryItem(name: "hasDataPermission", value: "false")
            ])
        let data = try await client.data(url: url)
        return try JSONDecoder().decode([ClassroomBuilding].self, from: data)
            .filter(\.enabled)
            .sorted { $0.nameZh < $1.nameZh }
    }

    func rooms(query: FreeClassroomQuery) async throws -> [FreeClassroomRoom] {
        let buildings = query.buildingIDs.isEmpty ? [0] : query.buildingIDs
        var collected: [FreeClassroomRoom] = []
        for buildingID in buildings {
            let request = FreeRoomRequest(
                buildingId: buildingID == 0 ? "" : String(buildingID),
                campusId: String(query.campusID),
                dateTimeSegmentCmd: .init(
                    endDateTime: Self.date(query.endDate),
                    startDateTime: Self.date(query.startDate),
                    units: (query.units.isEmpty ? Array(1...13) : query.units).map { String($0) }
                )
            )
            let data = try await client.data(
                url: baseURL.appendingPathComponent("student/ws/room-borrow/free-list"),
                method: "POST",
                body: try JSONEncoder().encode(request),
                contentType: "application/json"
            )
            collected += try JSONDecoder().decode(FreeRoomEnvelope.self, from: data).roomList
        }
        return Dictionary(grouping: collected, by: \.id)
            .values
            .compactMap(\.first)
            .sorted { ($0.building.nameZh, $0.floor, $0.nameZh) < ($1.building.nameZh, $1.floor, $1.nameZh) }
    }

    private static func date(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: value)
    }
}

struct DemoFreeClassroomRemote: FreeClassroomRemote {
    func buildings(campusID: Int) -> [ClassroomBuilding] {
        campusID == 2
            ? [ClassroomBuilding(code: "LH-JX", enabled: true, id: 201, nameZh: "龙河教学主楼")]
            : [
                ClassroomBuilding(code: "BXN", enabled: true, id: 101, nameZh: "博学南楼"),
                ClassroomBuilding(code: "DXB", enabled: true, id: 102, nameZh: "笃行北楼"),
                ClassroomBuilding(code: "WDG", enabled: true, id: 103, nameZh: "文典阁")
            ]
    }

    func rooms(query: FreeClassroomQuery) -> [FreeClassroomRoom] {
        let buildings: [(Int, String, String)] = [(101, "博学南楼", "BXN"), (102, "笃行北楼", "DXB"), (103, "文典阁", "WDG")]
        let rooms: [(Int, Int, Int)] = [(201, 2, 72), (305, 3, 48), (512, 5, 96)]
        let candidates = buildings.flatMap { building in
            rooms.map { room in
                FreeClassroomRoom(
                    building: .init(id: building.0, nameZh: building.1),
                    code: "\(building.2)-\(room.0)",
                    floor: room.1,
                    id: building.0 * 1000 + room.0,
                    nameZh: "\(room.0) 教室",
                    remark: "Mock：可容纳 \(room.2) 人",
                    seats: room.2
                )
            }
        }
        return query.buildingIDs.isEmpty ? candidates : candidates.filter { query.buildingIDs.contains($0.building.id) }
    }
}
