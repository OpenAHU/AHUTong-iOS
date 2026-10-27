import Foundation

final class MutableTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(_ date: Date = Date(timeIntervalSince1970: 1_800_000_000)) {
        self.date = date
    }

    func now() -> Date { lock.withLock { date } }
    func advance(seconds: TimeInterval) { lock.withLock { date.addTimeInterval(seconds) } }
}
