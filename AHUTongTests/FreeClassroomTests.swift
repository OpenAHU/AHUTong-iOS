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

    @MainActor
    func testViewModelClampsDatesAndExpandsAllBuildings() async {
        let model = FreeClassroomViewModel(api: FreeClassroomCampusAPIStub(), demo: true)
        await model.loadBuildings()
        let today = DemoDataState.referenceDate
        model.setStartDate(today.addingTimeInterval(-86_400), now: today)
        model.setEndDate(today.addingTimeInterval(-86_400))
        XCTAssertEqual(Calendar.current.startOfDay(for: model.startDate), Calendar.current.startOfDay(for: today))
        XCTAssertGreaterThanOrEqual(model.endDate, model.startDate)
        await model.search()
        XCTAssertEqual(model.rooms.value?.count, 12)
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
