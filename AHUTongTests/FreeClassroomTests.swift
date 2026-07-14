import XCTest
@testable import AHUTong

final class FreeClassroomTests: XCTestCase {
    func testDecodesAndroidBuildingAndRoomContracts() throws {
        let building = try JSONDecoder().decode(
            ClassroomBuilding.self,
            from: Data(#"{"code":"BXN","enabled":true,"id":101,"nameEn":"South","nameZh":"博学南楼"}"#.utf8)
        )
        let room = try JSONDecoder().decode(
            FreeClassroomRoom.self,
            from: Data(#"{"building":{"id":101,"nameZh":"博学南楼"},"code":"BXN-A210","floor":2,"id":101210,"nameZh":"A210 教室","remark":"可容纳 80 人","seats":80,"unknown":"ignored"}"#.utf8)
        )
        XCTAssertEqual(building.nameZh, "博学南楼")
        XCTAssertEqual(room.building, .init(id: 101, nameZh: "博学南楼"))
        XCTAssertEqual(room.seats, 80)
    }

    func testDemoRemoteUsesAllBuildingsWhenNoFilterIsSelected() {
        let query = FreeClassroomQuery(
            campusID: 1,
            buildingIDs: [],
            units: [],
            startDate: DemoDataState.referenceDate,
            endDate: DemoDataState.referenceDate
        )
        let rooms = DemoFreeClassroomRemote().rooms(query: query)
        XCTAssertEqual(rooms.count, 12)
        XCTAssertEqual(rooms.prefix(3).map(\.nameZh), ["201 教室", "305 教室", "512 教室"])
    }

    func testDemoRemoteFiltersSelectedBuildings() {
        let query = FreeClassroomQuery(
            campusID: 1,
            buildingIDs: [102],
            units: [1, 2, 3],
            startDate: DemoDataState.referenceDate,
            endDate: DemoDataState.referenceDate
        )
        let rooms = DemoFreeClassroomRemote().rooms(query: query)
        XCTAssertEqual(rooms.map(\.id), [102_201, 102_305, 102_512])
    }

    @MainActor
    func testViewModelMaintainsMultiSelectAndSearchState() async {
        let model = FreeClassroomViewModel(api: FreeClassroomCampusAPIStub(), demo: true)
        await model.loadBuildings()
        model.toggleBuilding(102)
        model.toggleUnits(1...5)
        await model.search()
        XCTAssertEqual(model.selectedBuildingIDs, Set([102]))
        XCTAssertEqual(model.selectedUnits, Set(1...5))
        XCTAssertEqual(model.rooms.value?.map(\.nameZh), ["201 教室", "305 教室", "512 教室"])
    }
}

private actor FreeClassroomCampusAPIStub: CampusCoreAPI {
    func initialize(cookiesJSON: String) {}
    func login(studentID: String, password: String) -> User { User(name: "", studentID: studentID) }
    func dumpCookies() -> String { "[]" }
    func cookiesFlat() -> String { "[]" }
    func schedule() -> [Course] { [] }
    func currentWeek() -> Int { 1 }
    func exams() -> [CampusExam] { [] }
    func grades() -> CampusGradeReport { .init(grades: [], gradePointAverage: nil, rank: nil, studentProfiles: []) }
    func cardBalance() -> Double { 0 }
    func cardQRCode() -> String { "" }
}
