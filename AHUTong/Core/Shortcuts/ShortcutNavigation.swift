import Combine
import Foundation

enum ShortcutDestination: Equatable, Sendable {
    case paymentCode

    init?(url: URL) {
        guard url.scheme?.lowercased() == "ahutong",
              url.host?.lowercased() == "payment-code",
              url.path.isEmpty || url.path == "/",
              url.query == nil, url.fragment == nil else { return nil }
        self = .paymentCode
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
