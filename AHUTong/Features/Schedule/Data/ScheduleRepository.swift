import Foundation

protocol ScheduleRemoteDataSource: Sendable {
    func fetchCourses(for semester: Semester) async throws -> [Course]
}

enum ScheduleLoadPolicy: Equatable, Sendable {
    case cacheFirst
    case refresh
}

enum ScheduleSnapshotSource: String, Equatable, Sendable {
    case cache
    case remote
    case staleCache
}

struct ScheduleSnapshot: Equatable, Sendable {
    let courses: [Course]
    let source: ScheduleSnapshotSource
}

enum ScheduleRepositoryError: Error, Equatable, Sendable {
    case noValidCourses
}

struct ScheduleRepository: Sendable {
    private let remote: any ScheduleRemoteDataSource
    private let cache: UserScopedStore

    init(remote: any ScheduleRemoteDataSource, cache: UserScopedStore) {
        self.remote = remote
        self.cache = cache
    }

    func load(
        semester: Semester,
        policy: ScheduleLoadPolicy = .cacheFirst
    ) async throws -> ScheduleSnapshot {
        let store = JSONStore<[Course]>(
            store: cache,
            key: "schedule.\(semester.rawValue)"
        )
        let cachedCourses = await loadCacheRecoveringCorruption(from: store)

        if policy == .cacheFirst, let cachedCourses {
            return ScheduleSnapshot(courses: cachedCourses, source: .cache)
        }

        do {
            let fetchedCourses = try await remote.fetchCourses(for: semester)
            let validCourses = fetchedCourses.filter(\.isStructurallyValid)
            if !fetchedCourses.isEmpty, validCourses.isEmpty {
                throw ScheduleRepositoryError.noValidCourses
            }
            try await store.save(validCourses)
            return ScheduleSnapshot(courses: validCourses, source: .remote)
        } catch {
            if let cachedCourses {
                return ScheduleSnapshot(courses: cachedCourses, source: .staleCache)
            }
            throw error
        }
    }

    private func loadCacheRecoveringCorruption(
        from store: JSONStore<[Course]>
    ) async -> [Course]? {
        do {
            return try await store.load()
        } catch {
            try? await store.remove()
            return nil
        }
    }
}
