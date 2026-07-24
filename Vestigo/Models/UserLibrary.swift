import Foundation

struct UserLibrary: Codable {
    var items: [MediaKey: MediaItem] = [:]
    var watchlist: Set<MediaKey> = []
    var watched: Set<MediaKey> = []
    var ratings: [MediaKey: Double] = [:]
    var favouriteKeys: Set<MediaKey> = []
    var neverShowAgain: Set<MediaKey> = []
    var notInterested: Set<MediaKey> = []
    var watchedOrder: [MediaKey] = []
    var collections: [MediaCollection] = []
    var watchedEpisodes: Set<EpisodeKey> = []

    private enum CodingKeys: String, CodingKey {
        case items
        case watchlist
        case watched
        case ratings
        case favouriteKeys
        case neverShowAgain
        case notInterested
        case watchedOrder
        case collections
        case watchedEpisodes
    }

    init() { }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([MediaKey: MediaItem].self, forKey: .items) ?? [:]
        watchlist = try container.decodeIfPresent(Set<MediaKey>.self, forKey: .watchlist) ?? []
        watched = try container.decodeIfPresent(Set<MediaKey>.self, forKey: .watched) ?? []
        ratings = try container.decodeIfPresent([MediaKey: Double].self, forKey: .ratings) ?? [:]
        favouriteKeys = try container.decodeIfPresent(Set<MediaKey>.self, forKey: .favouriteKeys) ?? []
        neverShowAgain = try container.decodeIfPresent(Set<MediaKey>.self, forKey: .neverShowAgain) ?? []
        notInterested = try container.decodeIfPresent(Set<MediaKey>.self, forKey: .notInterested) ?? []
        watchedOrder = try container.decodeIfPresent([MediaKey].self, forKey: .watchedOrder) ?? []
        collections = try container.decodeIfPresent([MediaCollection].self, forKey: .collections) ?? []
        watchedEpisodes = try container.decodeIfPresent(Set<EpisodeKey>.self, forKey: .watchedEpisodes) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(items, forKey: .items)
        try container.encode(watchlist, forKey: .watchlist)
        try container.encode(watched, forKey: .watched)
        try container.encode(ratings, forKey: .ratings)
        try container.encode(favouriteKeys, forKey: .favouriteKeys)
        try container.encode(neverShowAgain, forKey: .neverShowAgain)
        try container.encode(notInterested, forKey: .notInterested)
        try container.encode(watchedOrder, forKey: .watchedOrder)
        try container.encode(collections, forKey: .collections)
        try container.encode(watchedEpisodes, forKey: .watchedEpisodes)
    }

    var watchlistItems: [MediaItem] { watchlist.compactMap { items[$0] } }
    var watchedItems: [MediaItem] { watched.compactMap { items[$0] } }
    var neverShowAgainItems: [MediaItem] { neverShowAgain.compactMap { items[$0] } }
    var notInterestedItems: [MediaItem] { notInterested.compactMap { items[$0] } }

    func isInWatchlist(_ key: MediaKey) -> Bool { watchlist.contains(key) }
    func isWatched(_ key: MediaKey) -> Bool { watched.contains(key) }
    func isNeverShowAgain(_ key: MediaKey) -> Bool { neverShowAgain.contains(key) }
    func isNotInterested(_ key: MediaKey) -> Bool { notInterested.contains(key) }

    mutating func toggleWatchlist(_ item: MediaItem) {
        items[item.key] = item
        if watchlist.contains(item.key) { watchlist.remove(item.key) } else { watchlist.insert(item.key) }
    }

    mutating func markWatched(_ item: MediaItem) {
        items[item.key] = item
        watched.insert(item.key)
    }

    mutating func toggleWatched(_ item: MediaItem) {
        items[item.key] = item
        if watched.contains(item.key) { watched.remove(item.key) } else { watched.insert(item.key) }
    }

    mutating func toggleEpisode(showKey: MediaKey, season: Int, episode: Int) {
        let key = EpisodeKey(show: showKey, season: season, episode: episode)
        if watchedEpisodes.contains(key) { watchedEpisodes.remove(key) } else { watchedEpisodes.insert(key) }
    }

    mutating func setEpisode(showKey: MediaKey, season: Int, episode: Int, watched: Bool) {
        let key = EpisodeKey(show: showKey, season: season, episode: episode)
        if watched { watchedEpisodes.insert(key) } else { watchedEpisodes.remove(key) }
    }

    func isEpisodeWatched(showKey: MediaKey, season: Int, episode: Int) -> Bool {
        watchedEpisodes.contains(EpisodeKey(show: showKey, season: season, episode: episode))
    }

    var favouriteItems: [MediaItem] {
        favouriteKeys.compactMap { items[$0] }
    }

    var lastWatchedItem: MediaItem? {
        for key in watchedOrder.reversed() {
            if watched.contains(key), let item = items[key] {
                return item
            }
        }
        return watchedItems.last
    }

    func favouriteItems(for filter: MediaFilter) -> [MediaItem] {
        let favourites = favouriteItems
        switch filter {
        case .both:
            return favourites.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .movie:
            return favourites
                .filter { $0.kind == .movie }
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .tv:
            return favourites
                .filter { $0.kind == .tv }
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }

    func isFavourite(_ item: MediaItem) -> Bool {
        favouriteKeys.contains(item.key)
    }

    mutating func toggleFavourite(_ item: MediaItem) {
        items[item.key] = item
        if favouriteKeys.contains(item.key) {
            favouriteKeys.remove(item.key)
        } else {
            favouriteKeys.insert(item.key)
        }
    }

    mutating func toggleNeverShowAgain(_ item: MediaItem) {
        items[item.key] = item
        if neverShowAgain.contains(item.key) {
            neverShowAgain.remove(item.key)
        } else {
            neverShowAgain.insert(item.key)
            notInterested.remove(item.key)
        }
    }

    mutating func toggleNotInterested(_ item: MediaItem) {
        items[item.key] = item
        if notInterested.contains(item.key) {
            notInterested.remove(item.key)
        } else {
            notInterested.insert(item.key)
            neverShowAgain.remove(item.key)
        }
    }

    mutating func clearFavourites(for filter: MediaFilter) {
        switch filter {
        case .both:
            favouriteKeys.removeAll()
        case .movie:
            favouriteKeys = favouriteKeys.filter { $0.kind != .movie }
        case .tv:
            favouriteKeys = favouriteKeys.filter { $0.kind != .tv }
        }
    }

    mutating func recordWatchOrderChange(for item: MediaItem) {
        items[item.key] = item
        watchedOrder.removeAll { $0 == item.key }
        if watched.contains(item.key) {
            watchedOrder.append(item.key)
        }
    }
}

struct EpisodeKey: Codable, Hashable { let show: MediaKey; let season: Int; let episode: Int }
struct MediaCollection: Identifiable, Codable, Hashable { var id = UUID(); var name: String; var isDynamic: Bool; var itemKeys: Set<MediaKey> = [] }

enum NotificationKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case watchlistRelease
    case similarUpcoming
    case newTrailer
    case watchAvailability
    case watchedSeriesSeason
    case franchiseInstallment

    var id: String { rawValue }

    var title: String {
        switch self {
        case .watchlistRelease: return "Watchlist releases"
        case .similarUpcoming: return "Strong recommendation matches"
        case .newTrailer: return "New trailers"
        case .watchAvailability: return "Where-to-watch updates"
        case .watchedSeriesSeason: return "New watched-show seasons"
        case .franchiseInstallment: return "Franchise continuations"
        }
    }

    var description: String {
        switch self {
        case .watchlistRelease:
            return "A movie in your Watchlist is released, or a watchlisted show gets a new season."
        case .similarUpcoming:
            return "A movie or show comes out, or is upcoming, and strongly fits your watched, favourited, or highly rated history."
        case .newTrailer:
            return "A new trailer appears for something you watched or saved."
        case .watchAvailability:
            return "A saved released item gains or changes where-to-watch provider data."
        case .watchedSeriesSeason:
            return "A new season of a show you marked watched is released."
        case .franchiseInstallment:
            return "A new installment in a franchise you watched is released or upcoming."
        }
    }
}

enum NotificationLeadTime: String, Codable, CaseIterable, Identifiable, Hashable {
    case onReleaseDay = "day0"
    case oneDay = "1d"
    case threeDays = "3d"
    case oneWeek = "1w"
    case twoWeeks = "2w"
    case oneMonth = "1mo"
    case twoMonths = "2mo"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .onReleaseDay: return "On release day"
        case .oneDay:       return "1 day before"
        case .threeDays:    return "3 days before"
        case .oneWeek:      return "1 week before"
        case .twoWeeks:     return "2 weeks before"
        case .oneMonth:     return "1 month before"
        case .twoMonths:    return "2 months before"
        }
    }

    var daysOffset: Int {
        switch self {
        case .onReleaseDay: return 0
        case .oneDay:       return -1
        case .threeDays:    return -3
        case .oneWeek:      return -7
        case .twoWeeks:     return -14
        case .oneMonth:     return -30
        case .twoMonths:    return -60
        }
    }

    var relativeText: String {
        switch self {
        case .onReleaseDay: return "today"
        case .oneDay:       return "tomorrow"
        case .threeDays:    return "3 days"
        case .oneWeek:      return "1 week"
        case .twoWeeks:     return "2 weeks"
        case .oneMonth:     return "1 month"
        case .twoMonths:    return "2 months"
        }
    }
}

struct NotificationPreferences: Codable, Hashable {
    var isEnabled = false
    var enabledKinds: Set<NotificationKind> = Set(NotificationKind.allCases)
    var watchlistLeadTimes: Set<NotificationLeadTime> = [.onReleaseDay, .oneWeek]
    var hasSeenPrompt = false
    var deviceToken: String?
    var notifyOnlyForSubscribedServices: Bool = true
}
