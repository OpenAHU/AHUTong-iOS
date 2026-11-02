import Foundation

enum ScanRoute: Equatable {
    case meituan(URL)
    case chaoxing(URL)
    case wechat
    case unsupported

    init(_ raw: String, now: Date = Date()) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = URLComponents(string: text)
        let host = components?.host?.lowercased()
        let isWeb = components?.scheme?.lowercased() == "https" || components?.scheme?.lowercased() == "http"
        // Only known QR families can launch another app. Never open arbitrary schemes.
        guard components?.user == nil, components?.password == nil else { self = .unsupported; return }
        if isWeb, host == "mobilelearn.chaoxing.com",
           components?.path.hasPrefix("/widget/sign/") == true {
            self = .chaoxing(Self.link(scheme: "chaoxingshareback", host: "xuexitong.com", path: "/", items: [
                .init(name: "sharebacktype", value: "1"), .init(name: "title", value: "签到"),
                .init(name: "url", value: text)
            ]))
        } else if isWeb, let host, host == "yuketang.cn" || host.hasSuffix(".yuketang.cn") {
            self = .wechat
        } else if text.range(of: "^(866|867|868|870)[0-9]{7}$", options: .regularExpression) != nil
            || (isWeb && (host == "t8.pub" || host == "t9.pub") && components?.path.isEmpty == false)
            || (isWeb && host == "www.mobike.com" && components?.path == "/download/app.html"
                && components?.queryItems?.first(where: { $0.name == "b" })?.value?
                    .range(of: "^[0-9A-Z]{10}_1$", options: .regularExpression) != nil) {
            self = .meituan(Self.link(scheme: "imeituan", host: "www.meituan.com", path: "/bike/scan", items: [
                .init(name: "time", value: String(Int64(now.timeIntervalSince1970 * 1_000))),
                .init(name: "url", value: text)
            ]))
        } else { self = .unsupported }
    }

    private static func link(scheme: String, host: String, path: String, items: [URLQueryItem]) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = path
        components.queryItems = items
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url! // Fixed scheme/host/path; query values are encoded by Foundation.
    }
}
