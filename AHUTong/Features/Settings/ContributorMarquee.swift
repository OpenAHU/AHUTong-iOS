import Foundation

struct ContributorMarqueeClock: Equatable {
    private var accumulated: TimeInterval = 0
    private var startedAt: Date
    private(set) var isPaused = false

    init(now: Date = Date()) { startedAt = now }

    func distance(at date: Date, speed: Double = 12) -> Double {
        (accumulated + (isPaused ? 0 : max(0, date.timeIntervalSince(startedAt)))) * speed
    }

    mutating func setPaused(_ paused: Bool, at date: Date = Date()) {
        guard paused != isPaused else { return }
        if paused { accumulated += max(0, date.timeIntervalSince(startedAt)) }
        startedAt = date
        isPaused = paused
    }
}

enum ContributorRows {
    static func shuffled(using entries: [ContributorEntry]) -> [[ContributorEntry]] {
        let shuffled = entries.shuffled()
        let midpoint = (shuffled.count + 1) / 2
        return [Array(shuffled.prefix(midpoint)), Array(shuffled.dropFirst(midpoint))]
    }
}
