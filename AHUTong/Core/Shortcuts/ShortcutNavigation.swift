import Combine
import Foundation

enum ShortcutDestination: Equatable, Sendable {
    case paymentCode
    case scanner

    init?(url: URL) {
        guard url.scheme?.lowercased() == "ahutong",
              url.user == nil, url.password == nil, url.port == nil,
              url.path.isEmpty || url.path == "/",
              url.query == nil, url.fragment == nil else { return nil }
        switch url.host?.lowercased() {
        case "payment-code": self = .paymentCode
        case "scan": self = .scanner
        default: return nil
        }
    }
}

@MainActor
final class ShortcutNavigation: ObservableObject {
    struct Request: Equatable {
        let id = UUID()
        let destination: ShortcutDestination
    }

    static let shared = ShortcutNavigation()
    @Published private(set) var pendingRequest: Request?

    func request(_ destination: ShortcutDestination) {
        pendingRequest = Request(destination: destination)
    }

    func consume(_ request: Request) {
        if pendingRequest == request { pendingRequest = nil }
    }
}
