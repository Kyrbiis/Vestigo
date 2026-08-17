import Foundation

// MARK: - Helpers

enum DynamicCollections {
    static func inferredSeriesNames(for item: MediaItem) -> [String] { [] }

    static func broadCollections(for item: MediaItem) -> [String] {
        var genreNames: Set<String> = []
        for genreID in item.genreIDs {
            if let name = GenreDefinition.all.first(where: { $0.tmdbID == genreID })?.name {
                genreNames.insert(name)
            }
            for name in tvGenreNames(for: genreID) { genreNames.insert(name) }
        }
        return Array(genreNames).sorted()
    }

    private static func tvGenreNames(for genreID: Int) -> [String] {
        switch genreID {
        case 10759: return ["Action", "Adventure"]
        case 16: return ["Animation"]
        case 35: return ["Comedy"]
        case 80: return ["Crime"]
        case 99: return ["Documentary"]
        case 18: return ["Drama"]
        case 10751: return ["Family"]
        case 10762: return ["Kids"]
        case 9648: return ["Mystery"]
        case 10763: return ["News"]
        case 10764: return ["Reality"]
        case 10765: return ["Fantasy"]
        case 10766: return ["Soap"]
        case 10767: return ["Talk"]
        case 10768: return ["War", "Politics"]
        case 37: return ["Western"]
        default: return []
        }
    }

    static func tmdbGenreIDs(forCollectionName name: String) -> Set<Int> {
        switch name.lowercased() {
        case "action": return [28, 10759]
        case "adventure": return [12, 10759]
        case "animation": return [16]
        case "comedy": return [35]
        case "crime": return [80]
        case "documentary": return [99]
        case "drama": return [18]
        case "family": return [10751]
        case "fantasy": return [14, 10765]
        case "horror": return [27]
        case "kids": return [10762]
        case "mystery": return [9648]
        case "news": return [10763]
        case "reality": return [10764]
        case "sci-fi", "science fiction", "sci fi": return [878, 10765]
        case "soap": return [10766]
        case "talk": return [10767]
        case "war": return [10752, 10768]
        case "politics": return [10768]
        case "western": return [37]
        default:
            if let genre = GenreDefinition.all.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                return [genre.tmdbID]
            }
            return []
        }
    }

    static func item(_ item: MediaItem, belongsToCollectionNamed collectionName: String) -> Bool {
        let genreIDs = tmdbGenreIDs(forCollectionName: collectionName)
        guard !genreIDs.isEmpty else { return false }
        return !Set(item.genreIDs).intersection(genreIDs).isEmpty
    }
}

enum LoadErrorFilter {
    static func shouldIgnore(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }
}

struct KVLibrarySnapshot: Codable {
    let modifiedAt: Date
    let library: UserLibrary
    let settings: AppSettings
}

enum Storage {
    private static let kvSnapshotKey = "Vestigo.kvSnapshot"
    private static let homeFeedCacheKeyPrefix = "Vestigo.homeFeedCaches"

    static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
    }

    static func saveKVSnapshot(library: UserLibrary, settings: AppSettings) {
        let snapshot = KVLibrarySnapshot(modifiedAt: Date(), library: library, settings: settings)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        let store = NSUbiquitousKeyValueStore.default
        store.set(data, forKey: kvSnapshotKey)
        store.synchronize()
    }

    static func loadKVSnapshot() -> KVLibrarySnapshot? {
        let store = NSUbiquitousKeyValueStore.default
        store.synchronize()
        guard let data = store.data(forKey: kvSnapshotKey) else { return nil }
        return try? JSONDecoder().decode(KVLibrarySnapshot.self, from: data)
    }

    static func loadNewestHomeFeedCache(for filter: MediaFilter) -> HomeFeedCache? {
        load([HomeFeedCache].self, key: homeFeedCacheKey(for: filter))?
            .sorted { $0.cachedAt > $1.cachedAt }
            .first { $0.filter == filter && $0.hasContent }
    }

    static func saveHomeFeedCache(_ cache: HomeFeedCache) {
        guard cache.hasContent else { return }
        let key = homeFeedCacheKey(for: cache.filter)
        var caches = load([HomeFeedCache].self, key: key) ?? []
        caches.insert(cache, at: 0)
        caches = caches.filter { $0.filter == cache.filter && $0.hasContent }
            .sorted { $0.cachedAt > $1.cachedAt }
        if caches.count > 2 { caches = Array(caches.prefix(2)) }
        save(caches, key: key)
    }

    private static func homeFeedCacheKey(for filter: MediaFilter) -> String {
        "\(homeFeedCacheKeyPrefix).\(filter.rawValue)"
    }
}

