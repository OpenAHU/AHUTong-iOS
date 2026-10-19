import SwiftUI
import WidgetKit
import XCTest
@testable import AHUTong

final class ScheduleWidgetLayoutTests: XCTestCase {
    private func course(_ id: String, day: Int, start: Int, end: Int) -> ScheduleWidgetCourse {
        .init(id: id, weekday: day, startPeriod: start, endPeriod: end, name: ["高等数学", "大学英语", "程序设计", "计算机网络", "线性代数"][max(0, day - 1) % 5], location: "博学南楼A301", weekIndexes: [7])
    }
    func testWeeklyLayoutPreservesWeekendAndOverlappingCourses() {
        let courses = [course("a", day: 6, start: 1, end: 2), course("b", day: 6, start: 2, end: 3), course("c", day: 6, start: 5, end: 6), course("d", day: 7, start: 11, end: 13)]
        let saturday = ScheduleWidgetBlock.make(courses: courses, day: 6)
        XCTAssertEqual(saturday.count, 2)
        XCTAssertEqual(saturday[0].courses.map(\.id), ["a", "b"])
        XCTAssertEqual(saturday[0].end, 3)
        XCTAssertEqual(ScheduleWidgetBlock.make(courses: courses, day: 7).first?.end, 13)
        XCTAssertEqual((1...7).flatMap { ScheduleWidgetBlock.make(courses: courses, day: $0) }.flatMap(\.courses).count, courses.count)
    }
    func testAgendaExcludesCompletedTodayAndKeepsNextTeachingDays() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-19T07:00:00Z"))
        let snapshot = ScheduleWidgetSnapshot(status: .ready, currentWeek: 7, updatedAt: now, courses: [course("past", day: 1, start: 1, end: 2), course("next", day: 2, start: 1, end: 2)], allCourses: nil)
        let agenda = ScheduleWidgetAgenda.make(snapshot: snapshot, date: now, limit: 2)
        XCTAssertEqual(agenda.map(\.day), [2])
        XCTAssertEqual(agenda[0].courses.map(\.id), ["next"])
    }
    @MainActor
    func testRenderLightAndDarkScheduleAtWidgetSizes() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-19T00:00:00Z"))
        let courses = (1...7).flatMap { day in
            [course("\(day)-early", day: day, start: 1, end: 2), course("\(day)-late", day: day, start: 7, end: 8), course("\(day)-evening", day: day, start: 11, end: 13)]
        }
        let snapshot = ScheduleWidgetSnapshot(status: .ready, currentWeek: 7, updatedAt: now, courses: courses, allCourses: courses)
        for dark in [false, true] {
            for family in [WidgetFamily.systemSmall, .systemMedium, .systemLarge] {
                let size = CGSize(width: family == .systemSmall ? 170 : 354, height: family == .systemLarge ? 370 : 170)
                let content = ScheduleWidgetContent(date: now, snapshot: snapshot, family: family, dark: dark)
                    .padding(14).background(dark ? Color(red: 0.065, green: 0.09, blue: 0.14) : Color(red: 0.96, green: 0.97, blue: 0.99))
                    .frame(width: size.width, height: size.height)
                    .environment(\.colorScheme, dark ? .dark : .light)
                let renderer = ImageRenderer(content: content)
                renderer.scale = 3
                let image = try XCTUnwrap(renderer.uiImage)
                let name = "widget-\(family)-\(dark ? "dark" : "light")"
                let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
                if let directory = ProcessInfo.processInfo.environment["AHUTONG_WIDGET_EVIDENCE_DIR"] {
                    try image.pngData()?.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
                }
            }
        }
    }
}
