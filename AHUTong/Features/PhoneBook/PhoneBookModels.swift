import Foundation

enum PhoneCampus: String, CaseIterable, Codable, Sendable {
    case qingyuan = "磬苑"
    case longhe = "龙河"
}

struct CampusPhoneNumber: Hashable, Codable, Identifiable, Sendable {
    let campus: PhoneCampus?
    let localNumber: String

    var id: String { "\(campus?.rawValue ?? "通用")-\(localNumber)" }
    var displayNumber: String { "0551-\(localNumber)" }

    var dialURL: URL? {
        let digits = displayNumber.filter(\.isNumber)
        guard digits.count == 12 else { return nil }
        return URL(string: "tel://\(digits)")
    }
}

struct PhoneBookEntry: Hashable, Identifiable, Sendable {
    let category: String
    let name: String
    let numbers: [CampusPhoneNumber]

    var id: String { "\(category)-\(name)" }
}

struct PhoneBookSection: Hashable, Identifiable, Sendable {
    let title: String
    let entries: [PhoneBookEntry]

    var id: String { title }
}

enum PhoneBookDirectory {
    static let sourceDescription = "号码来自《安徽大学 2025 新生手册》；教务处号码于 2026 年 3 月核对更新。座机统一使用 0551 区号，Android 对照基线不含蜀山校区。"

    static let sections: [PhoneBookSection] = [
        section("师生综合服务大厅", [
            ("咨询台", "63861400", nil),
            ("财务处", "63861322", "65107303"),
            ("研究生院", "63861455", "65107332"),
            ("教务处", "63861055", "65107135"),
            ("双创学院", "65106065", nil),
            ("学生处（学生发展中心）", "63861686", "65107232"),
            ("国际合作与交流处", "63861848", nil),
            ("学校办公室", "63861659", "65107020"),
            ("网络信息中心", "63861855", "65107421"),
            ("保卫处", "63861918", nil),
            ("人事处", "63861922", nil),
            ("国有资产管理与实验室管理处", "63861949", "65107310"),
            ("人文社会科学处", "63861958", nil),
            ("科学技术处", "63861983", nil),
            ("校团委", nil, "65107537")
        ]),
        section("学生处（心理健康教育中心）", [
            ("学生思想教育科", "63861900", nil),
            ("学生管理科", "63861054", nil),
            ("学生资助管理中心", "63861900", nil),
            ("学生就业指导中心", "63861355", "63861383"),
            ("心理健康教育中心", "63861590", nil)
        ]),
        section("校团委", [("团委办公室", "63861121", "63861196")]),
        section("图书馆", [("图书馆", "63861109", nil)]),
        section("校医院（医保办）", [
            ("24 小时值班电话", "63861120", nil),
            ("校医疗保障委员会办公室", "63861715", nil)
        ]),
        section("后勤服务", [
            ("学校物业监管办公室", "63861358", nil),
            ("餐饮监管办公室", "63861398", nil)
        ]),
        section("报警电话", [
            ("保卫处（优先联系）", "63861110", "65108229"),
            ("三里庵派出所", nil, "63636594"),
            ("芙蓉派出所", "63822505", nil)
        ]),
        section("磬苑后勤", [
            ("校园报修电话", "63861118", nil),
            ("服务监督电话", "63861722", nil),
            ("北区 24 小时报修电话", "62950090", nil),
            ("南区 24 小时报修电话", "63861333", nil),
            ("桃园", "63861034", nil),
            ("李园", "63861037", nil),
            ("桔园", "63861036", nil),
            ("枣园", "63861218", nil),
            ("榴园", "63861217", nil),
            ("杏园", "63861219", nil),
            ("蕙8", "63861654", nil),
            ("蕙9", "63861617", nil),
            ("蕙10", "63861697", nil),
            ("松园", "63861160", nil),
            ("竹园", "63861115", nil),
            ("梅园", "63861113", nil),
            ("桂园", "63861097", nil),
            ("枫园", "63861096", nil),
            ("槐园", "63861081", nil),
            ("留学生公寓", "63861096", nil)
        ]),
        section("龙河后勤", [
            ("宿舍管理办公室", nil, "65107014"),
            ("校园报修电话", nil, "63861118"),
            ("服务监督电话", nil, "63861722"),
            ("206楼", nil, "65107064"),
            ("207-208楼", nil, "65108150"),
            ("209楼", nil, "65107940"),
            ("301楼", nil, "65108004"),
            ("304-306楼", nil, "65108004")
        ])
    ]

    static var entries: [PhoneBookEntry] { sections.flatMap(\.entries) }

    static func search(_ query: String) -> [PhoneBookEntry] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }
        return entries.filter { entry in
            entry.name.localizedCaseInsensitiveContains(normalized)
                || entry.category.localizedCaseInsensitiveContains(normalized)
                || entry.numbers.contains { number in
                    number.localNumber.contains(normalized)
                        || number.displayNumber.contains(normalized)
                }
        }
    }

    private static func section(
        _ title: String,
        _ rows: [(String, String?, String?)]
    ) -> PhoneBookSection {
        PhoneBookSection(
            title: title,
            entries: rows.map { name, qingyuan, longhe in
                var numbers: [CampusPhoneNumber] = []
                if let qingyuan {
                    numbers.append(
                        CampusPhoneNumber(
                            campus: longhe == qingyuan ? nil : .qingyuan,
                            localNumber: qingyuan
                        )
                    )
                }
                if let longhe, longhe != qingyuan {
                    numbers.append(
                        CampusPhoneNumber(campus: .longhe, localNumber: longhe)
                    )
                }
                return PhoneBookEntry(category: title, name: name, numbers: numbers)
            }
        )
    }
}
