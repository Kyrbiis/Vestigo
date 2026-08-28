import Foundation
#if canImport(AppIntents)
import AppIntents

enum VestigoMediaKindFilter: String, AppEnum, CaseIterable {
    case movies
    case shows
    case both

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Type" }

    static var caseDisplayRepresentations: [Self: DisplayRepresentation] {
        [
            .movies: DisplayRepresentation(title: "movies"),
            .shows: DisplayRepresentation(title: "shows"),
            .both: DisplayRepresentation(title: "items")
        ]
    }

    var subtitleWord: String {
        switch self {
        case .movies: return "Movie"
        case .shows: return "Show"
        case .both: return "Item"
        }
    }

    var noun: String {
        switch self {
        case .movies: return "movies"
        case .shows: return "shows"
        case .both: return "items"
        }
    }
}

@available(iOS 16.0, *)
struct VestigoMediaEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Vestigo item" }
    static var defaultQuery: VestigoMediaEntityQuery { VestigoMediaEntityQuery() }

    var id: String
    var title: String
    var kindFilter: VestigoMediaKindFilter
    var releaseYear: String?
    var rating: Double?
    var isWatched: Bool
    var isOnWatchlist: Bool
    var isFavourite: Bool

    init(
        id: String,
        title: String,
        kindFilter: VestigoMediaKindFilter,
        releaseYear: String?,
        rating: Double? = nil,
        isWatched: Bool = false,
        isOnWatchlist: Bool = false,
        isFavourite: Bool = false
    ) {
        self.id = id
        self.title = title
        self.kindFilter = kindFilter
        self.releaseYear = releaseYear
        self.rating = rating
        self.isWatched = isWatched
        self.isOnWatchlist = isOnWatchlist
        self.isFavourite = isFavourite
    }

    var displayRepresentation: DisplayRepresentation {
        var parts: [String] = [kindFilter.subtitleWord]
        if let year = releaseYear { parts.append(year) }
        if let r = rating, r > 0 {
            parts.append("\(r.formatted(.number.precision(.fractionLength(1))))★")
        } else if isWatched {
            parts.append("Watched")
        } else if isOnWatchlist {
            parts.append("On watchlist")
        }
        if isFavourite { parts.append("Favourite") }
        return DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: title),
            subtitle: LocalizedStringResource(stringLiteral: parts.joined(separator: " · "))
        )
    }
}

@available(iOS 16.0, *)
struct VestigoMediaEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [VestigoMediaEntity.ID]) async throws -> [VestigoMediaEntity] {
        VestigoIntentBridge.entities(withIDs: identifiers)
    }

    @MainActor
    func entities(matching string: String) async throws -> [VestigoMediaEntity] {
        var seen = Set<String>()
        var results: [VestigoMediaEntity] = []

        for entity in VestigoIntentBridge.libraryMatches(query: string) {
            if seen.insert(entity.id).inserted { results.append(entity) }
        }
        for entity in await VestigoIntentSearch.searchCatalog(query: string) {
            if seen.insert(entity.id).inserted {
                results.append(entity)
                if results.count >= 12 { break }
            }
        }
        return results
    }

    @MainActor
    func suggestedEntities() async throws -> [VestigoMediaEntity] {
        VestigoIntentBridge.suggestedEntities()
    }
}

// MARK: - Catalog search

@available(iOS 16.0, *)
enum VestigoIntentSearch {
    private static let base = "https://mtttuyvpjyugudkevchj.supabase.co/functions/v1/vestigo-api"

    static func searchCatalog(query: String) async -> [VestigoMediaEntity] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var comps = URLComponents(string: base + "/tmdb-proxy")
        comps?.queryItems = [
            URLQueryItem(name: "path", value: "/search/multi"),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "query", value: trimmed),
            URLQueryItem(name: "include_adult", value: "false")
        ]

        guard let url = comps?.url else { return [] }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) { return [] }
            let decoded = try JSONDecoder().decode(TMDbSearchResponse.self, from: data)
            return decoded.results.compactMap { result -> VestigoMediaEntity? in
                guard let mediaType = result.media_type,
                      mediaType == "movie" || mediaType == "tv",
                      let id = result.id else { return nil }
                let title = mediaType == "tv" ? (result.name ?? "") : (result.title ?? "")
                guard !title.isEmpty else { return nil }
                let year: String? = (result.release_date ?? result.first_air_date).flatMap { date in
                    date.count >= 4 ? String(date.prefix(4)) : nil
                }
                let filter: VestigoMediaKindFilter = mediaType == "tv" ? .shows : .movies
                return VestigoMediaEntity(id: "\(mediaType)-\(id)", title: title, kindFilter: filter, releaseYear: year)
            }
        } catch {
            return []
        }
    }

    private struct TMDbSearchResponse: Decodable {
        let results: [TMDbSearchResult]
    }
    private struct TMDbSearchResult: Decodable {
        let id: Int?
        let title: String?
        let name: String?
        let media_type: String?
        let release_date: String?
        let first_air_date: String?
    }
}

// MARK: - Library writer

@available(iOS 16.0, *)
enum VestigoIntentWriter {
    static let libraryChangedNotification = Notification.Name("vestigo.library.changedByIntent")

    static func addToWatchlist(entity: VestigoMediaEntity) -> String {
        mutate { library in
            let key = mediaKey(for: entity)
            library.items[key] = library.items[key] ?? synthesize(entity: entity, key: key)
            library.watchlist.insert(key)
            return "Added \(entity.title) to your Vestigo watchlist."
        }
    }

    static func removeFromWatchlist(entity: VestigoMediaEntity) -> String {
        mutate { library in
            let key = mediaKey(for: entity)
            library.watchlist.remove(key)
            return "Removed \(entity.title) from your Vestigo watchlist."
        }
    }

    static func markWatched(entity: VestigoMediaEntity, rating: Double?) -> String {
        mutate { library in
            let key = mediaKey(for: entity)
            library.items[key] = library.items[key] ?? synthesize(entity: entity, key: key)
            library.watched.insert(key)
            library.watchlist.remove(key)
            if !library.watchedOrder.contains(key) { library.watchedOrder.append(key) }
            if let rating { library.ratings[key] = max(0, min(5, rating)) }
            if let rating {
                return "Marked \(entity.title) as watched and rated it \(rating.formatted(.number.precision(.fractionLength(1)))) stars."
            } else {
                return "Marked \(entity.title) as watched."
            }
        }
    }

    static func markUnwatched(entity: VestigoMediaEntity) -> String {
        mutate { library in
            let key = mediaKey(for: entity)
            library.watched.remove(key)
            library.watchedOrder.removeAll { $0 == key }
            return "Marked \(entity.title) as unwatched in Vestigo."
        }
    }

    static func rate(entity: VestigoMediaEntity, stars: Double) -> String {
        mutate { library in
            let key = mediaKey(for: entity)
            library.items[key] = library.items[key] ?? synthesize(entity: entity, key: key)
            let clamped = max(0, min(5, stars))
            library.ratings[key] = clamped
            return "Rated \(entity.title) \(clamped.formatted(.number.precision(.fractionLength(1)))) stars in Vestigo."
        }
    }

    static func addToFavourites(entity: VestigoMediaEntity) -> String {
        mutate { library in
            let key = mediaKey(for: entity)
            library.items[key] = library.items[key] ?? synthesize(entity: entity, key: key)
            if !library.favouriteKeys.contains(key) {
                library.favouriteKeys.insert(key)
                library.favouriteOrder.append(key)
            }
            return "Marked \(entity.title) as a favourite in Vestigo."
        }
    }

    static func removeFromFavourites(entity: VestigoMediaEntity) -> String {
        mutate { library in
            let key = mediaKey(for: entity)
            library.favouriteKeys.remove(key)
            library.favouriteOrder.removeAll { $0 == key }
            return "Removed \(entity.title) from your Vestigo favourites."
        }
    }

    static func markNotInterested(entity: VestigoMediaEntity) -> String {
        mutate { library in
            let key = mediaKey(for: entity)
            library.items[key] = library.items[key] ?? synthesize(entity: entity, key: key)
            library.notInterested.insert(key)
            library.neverShowAgain.remove(key)
            return "Marked \(entity.title) as not interested. Vestigo will de-emphasize similar titles."
        }
    }

    private static func mutate(_ apply: (inout UserLibrary) -> String) -> String {
        var library = loadLibrary() ?? UserLibrary()
        let response = apply(&library)
        if let data = try? JSONEncoder().encode(library) {
            UserDefaults.standard.set(data, forKey: "Vestigo.library")
        }
        NotificationCenter.default.post(name: libraryChangedNotification, object: nil)
        return response
    }

    private static func loadLibrary() -> UserLibrary? {
        guard let data = UserDefaults.standard.data(forKey: "Vestigo.library") else { return nil }
        return try? JSONDecoder().decode(UserLibrary.self, from: data)
    }

    private static func mediaKey(for entity: VestigoMediaEntity) -> MediaKey {
        let parts = entity.id.split(separator: "-", maxSplits: 1)
        let kind: MediaKind = parts.first == "tv" ? .tv : .movie
        let id = parts.count == 2 ? (Int(parts[1]) ?? 0) : 0
        return MediaKey(id: id, kind: kind)
    }

    private static func synthesize(entity: VestigoMediaEntity, key: MediaKey) -> MediaItem {
        MediaItem(
            id: key.id, kind: key.kind, title: entity.title, overview: "",
            posterPath: nil, backdropPath: nil,
            releaseDate: entity.releaseYear.map { "\($0)-01-01" },
            voteAverage: 0, voteCount: nil, genreIDs: [], creditRole: nil, runtime: nil, originalLanguage: nil
        )
    }
}

// MARK: - Query intents

@available(iOS 16.0, *)
struct ShowVestigoWatchlistIntent: AppIntent {
    static var title: LocalizedStringResource = "Show my Vestigo watchlist"
    static var description = IntentDescription("Lists the movies and shows saved on your Vestigo watchlist.", categoryName: "Library")

    @Parameter(title: "Type", default: .both)
    var kindFilter: VestigoMediaKindFilter

    static var parameterSummary: some ParameterSummary {
        Summary("Show my Vestigo watchlist \(\.$kindFilter)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[VestigoMediaEntity]> & ProvidesDialog {
        let items = VestigoIntentBridge.watchlistItems(kindFilter: kindFilter)
        return .result(value: items, dialog: VestigoIntentBridge.watchlistDialog(for: items, kindFilter: kindFilter))
    }
}

@available(iOS 16.0, *)
struct ShowVestigoFavouritesIntent: AppIntent {
    static var title: LocalizedStringResource = "Show my Vestigo favourites"
    static var description = IntentDescription("Lists the movies and shows you've marked as favourites in Vestigo.", categoryName: "Library")

    @Parameter(title: "Type", default: .both)
    var kindFilter: VestigoMediaKindFilter

    static var parameterSummary: some ParameterSummary {
        Summary("Show my Vestigo favourite \(\.$kindFilter)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[VestigoMediaEntity]> & ProvidesDialog {
        let items = VestigoIntentBridge.favouriteItems(kindFilter: kindFilter)
        return .result(value: items, dialog: VestigoIntentBridge.dialog(for: items, source: .favourites, kindFilter: kindFilter))
    }
}

@available(iOS 16.0, *)
struct ShowVestigoWatchedIntent: AppIntent {
    static var title: LocalizedStringResource = "Show what I've watched in Vestigo"
    static var description = IntentDescription("Lists the movies and shows you've marked as watched in Vestigo.", categoryName: "Library")

    @Parameter(title: "Type", default: .both)
    var kindFilter: VestigoMediaKindFilter

    static var parameterSummary: some ParameterSummary {
        Summary("Show what I've watched in Vestigo \(\.$kindFilter)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[VestigoMediaEntity]> & ProvidesDialog {
        let recent = VestigoIntentBridge.recentlyWatchedItems(kindFilter: kindFilter, limit: 5)
        let all = VestigoIntentBridge.watchedItems(kindFilter: kindFilter)
        return .result(value: all, dialog: VestigoIntentBridge.watchedDialog(recentItems: recent, totalCount: all.count, kindFilter: kindFilter))
    }
}

@available(iOS 16.0, *)
struct GetUnwatchedVestigoWatchlistIntent: AppIntent {
    static var title: LocalizedStringResource = "What haven't I watched on my Vestigo watchlist"
    static var description = IntentDescription("Shows watchlist items you haven't watched yet, sorted by highest TMDb rating.", categoryName: "Library")

    @Parameter(title: "Type", default: .both)
    var kindFilter: VestigoMediaKindFilter

    static var parameterSummary: some ParameterSummary {
        Summary("Show unwatched Vestigo watchlist \(\.$kindFilter)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[VestigoMediaEntity]> & ProvidesDialog {
        let items = VestigoIntentBridge.unwatchedWatchlistItems(kindFilter: kindFilter)
        let noun = kindFilter.noun
        if items.isEmpty {
            return .result(value: [], dialog: IntentDialog(LocalizedStringResource(stringLiteral: "You have no unwatched \(noun) on your Vestigo watchlist.")))
        }
        let preview = VestigoIntentBridge.formatList(items.prefix(3).map(\.title))
        let dialog: String = items.count <= 3
            ? "Your unwatched Vestigo \(noun): \(preview)."
            : "You have \(items.count) unwatched \(noun) on your Vestigo watchlist. Top picks: \(preview)."
        return .result(value: items, dialog: IntentDialog(LocalizedStringResource(stringLiteral: dialog)))
    }
}

@available(iOS 16.0, *)
struct GetRecentlyWatchedInVestigoIntent: AppIntent {
    static var title: LocalizedStringResource = "What did I watch recently in Vestigo"
    static var description = IntentDescription("Shows the most recently watched movies and shows in Vestigo.", categoryName: "Library")

    @Parameter(title: "Type", default: .both)
    var kindFilter: VestigoMediaKindFilter

    static var parameterSummary: some ParameterSummary {
        Summary("Show recently watched in Vestigo \(\.$kindFilter)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[VestigoMediaEntity]> & ProvidesDialog {
        let items = VestigoIntentBridge.recentlyWatchedItems(kindFilter: kindFilter, limit: 10)
        if items.isEmpty {
            let noun = kindFilter.noun
            return .result(value: [], dialog: IntentDialog(LocalizedStringResource(stringLiteral: "You haven't watched any \(noun) in Vestigo yet.")))
        }
        let names = items.prefix(5).map { entity -> String in
            if let r = entity.rating, r > 0 { return "\(entity.title) (\(r.formatted(.number.precision(.fractionLength(1))))★)" }
            return entity.title
        }
        let preview = VestigoIntentBridge.formatList(Array(names))
        return .result(value: items, dialog: IntentDialog(LocalizedStringResource(stringLiteral: "You recently watched \(preview) in Vestigo.")))
    }
}

@available(iOS 16.0, *)
struct GetTopRatedInVestigoIntent: AppIntent {
    static var title: LocalizedStringResource = "Show my top rated in Vestigo"
    static var description = IntentDescription("Shows your highest rated movies and shows in Vestigo.", categoryName: "Library")

    @Parameter(title: "Type", default: .both)
    var kindFilter: VestigoMediaKindFilter

    static var parameterSummary: some ParameterSummary {
        Summary("Show my top rated Vestigo \(\.$kindFilter)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[VestigoMediaEntity]> & ProvidesDialog {
        let items = VestigoIntentBridge.topRatedItems(kindFilter: kindFilter, limit: 10)
        let noun = kindFilter.noun
        if items.isEmpty {
            return .result(value: [], dialog: IntentDialog(LocalizedStringResource(stringLiteral: "You haven't rated any \(noun) in Vestigo yet.")))
        }
        let names = items.prefix(5).map { entity -> String in
            let r = entity.rating.map { "\($0.formatted(.number.precision(.fractionLength(1))))★" } ?? ""
            return r.isEmpty ? entity.title : "\(entity.title) (\(r))"
        }
        let preview = VestigoIntentBridge.formatList(Array(names))
        return .result(value: items, dialog: IntentDialog(LocalizedStringResource(stringLiteral: "Your highest rated \(noun) in Vestigo: \(preview).")))
    }
}

@available(iOS 16.0, *)
struct CheckVestigoItemStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Check item status in Vestigo"
    static var description = IntentDescription(
        "Check whether a movie or show is on your watchlist, whether you've watched it, and how you rated it.",
        categoryName: "Library"
    )
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: "Item",
        requestValueDialog: IntentDialog("Which movie or show?"),
        requestDisambiguationDialog: IntentDialog("Which one did you mean?")
    )
    var item: VestigoMediaEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Check \(\.$item) in Vestigo")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let status = VestigoIntentBridge.itemStatus(entityID: item.id, title: item.title)
        return .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: status)))
    }
}

@available(iOS 16.0, *)
struct GetVestigoLibraryStatsIntent: AppIntent {
    static var title: LocalizedStringResource = "Show my Vestigo library stats"
    static var description = IntentDescription(
        "Gives a summary of how many movies and shows you've watched, your watchlist size, favourites, and average rating.",
        categoryName: "Library"
    )
    static var openAppWhenRun: Bool = false

    static var parameterSummary: some ParameterSummary {
        Summary("Show my Vestigo library stats")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let stats = VestigoIntentBridge.libraryStats()
        return .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: stats)))
    }
}

@available(iOS 16.0, *)
struct GetVestigoCollectionIntent: AppIntent {
    static var title: LocalizedStringResource = "Show a Vestigo collection"
    static var description = IntentDescription(
        "Lists the items in one of your named Vestigo collections.",
        categoryName: "Library"
    )
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: "Collection name",
        requestValueDialog: IntentDialog("Which collection?")
    )
    var collectionName: String

    static var parameterSummary: some ParameterSummary {
        Summary("Show my \(\.$collectionName) collection in Vestigo")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[VestigoMediaEntity]> & ProvidesDialog {
        let result = VestigoIntentBridge.collectionItems(named: collectionName)
        if !result.found {
            return .result(value: [], dialog: IntentDialog(LocalizedStringResource(stringLiteral: "You don't have a collection called \"\(collectionName)\" in Vestigo.")))
        }
        let entities = result.entities
        if entities.isEmpty {
            return .result(value: [], dialog: IntentDialog(LocalizedStringResource(stringLiteral: "Your \"\(result.name)\" collection in Vestigo is empty.")))
        }
        let preview = VestigoIntentBridge.formatList(entities.prefix(3).map(\.title))
        let dialog: String = entities.count <= 3
            ? "Your \(result.name) collection in Vestigo: \(preview)."
            : "Your \(result.name) collection has \(entities.count) items, including \(preview)."
        return .result(value: entities, dialog: IntentDialog(LocalizedStringResource(stringLiteral: dialog)))
    }
}

// MARK: - Action intents

@available(iOS 16.0, *)
struct AddToVestigoWatchlistIntent: AppIntent {
    static var title: LocalizedStringResource = "Add to Vestigo watchlist"
    static var description = IntentDescription("Saves a movie or show to your Vestigo watchlist.", categoryName: "Library")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Item", requestValueDialog: IntentDialog("Which movie or show?"), requestDisambiguationDialog: IntentDialog("Which one did you mean?"))
    var item: VestigoMediaEntity

    static var parameterSummary: some ParameterSummary { Summary("Add \(\.$item) to my Vestigo watchlist") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: VestigoIntentWriter.addToWatchlist(entity: item))))
    }
}

@available(iOS 16.0, *)
struct RemoveFromVestigoWatchlistIntent: AppIntent {
    static var title: LocalizedStringResource = "Remove from Vestigo watchlist"
    static var description = IntentDescription("Removes a movie or show from your Vestigo watchlist.", categoryName: "Library")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Item", requestValueDialog: IntentDialog("Which movie or show?"), requestDisambiguationDialog: IntentDialog("Which one did you mean?"))
    var item: VestigoMediaEntity

    static var parameterSummary: some ParameterSummary { Summary("Remove \(\.$item) from my Vestigo watchlist") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: VestigoIntentWriter.removeFromWatchlist(entity: item))))
    }
}

@available(iOS 16.0, *)
struct MarkWatchedInVestigoIntent: AppIntent {
    static var title: LocalizedStringResource = "Mark as watched in Vestigo"
    static var description = IntentDescription("Marks a movie or show as watched. Optionally records a star rating from 0 to 5.", categoryName: "Library")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Item", requestValueDialog: IntentDialog("Which movie or show?"), requestDisambiguationDialog: IntentDialog("Which one did you mean?"))
    var item: VestigoMediaEntity

    @Parameter(title: "Rating", description: "Optional star rating from 0 to 5.", default: nil, inclusiveRange: (0.0, 5.0))
    var rating: Double?

    static var parameterSummary: some ParameterSummary {
        Summary("Mark \(\.$item) as watched") { \.$rating }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: VestigoIntentWriter.markWatched(entity: item, rating: rating))))
    }
}

@available(iOS 16.0, *)
struct MarkUnwatchedInVestigoIntent: AppIntent {
    static var title: LocalizedStringResource = "Mark as unwatched in Vestigo"
    static var description = IntentDescription("Removes a movie or show from your Vestigo watch history.", categoryName: "Library")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Item", requestValueDialog: IntentDialog("Which movie or show?"), requestDisambiguationDialog: IntentDialog("Which one did you mean?"))
    var item: VestigoMediaEntity

    static var parameterSummary: some ParameterSummary { Summary("Mark \(\.$item) as unwatched in Vestigo") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: VestigoIntentWriter.markUnwatched(entity: item))))
    }
}

@available(iOS 16.0, *)
struct RateInVestigoIntent: AppIntent {
    static var title: LocalizedStringResource = "Rate a movie or show in Vestigo"
    static var description = IntentDescription("Sets a star rating from 0 to 5 for a movie or show in Vestigo.", categoryName: "Library")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Item", requestValueDialog: IntentDialog("Which movie or show?"), requestDisambiguationDialog: IntentDialog("Which one did you mean?"))
    var item: VestigoMediaEntity

    @Parameter(title: "Stars", description: "Star rating from 0 to 5.", inclusiveRange: (0.0, 5.0))
    var stars: Double

    static var parameterSummary: some ParameterSummary { Summary("Rate \(\.$item) \(\.$stars) stars in Vestigo") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: VestigoIntentWriter.rate(entity: item, stars: stars))))
    }
}

@available(iOS 16.0, *)
struct AddToVestigoFavouritesIntent: AppIntent {
    static var title: LocalizedStringResource = "Add to Vestigo favourites"
    static var description = IntentDescription("Marks a movie or show as a favourite in Vestigo.", categoryName: "Library")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Item", requestValueDialog: IntentDialog("Which movie or show?"), requestDisambiguationDialog: IntentDialog("Which one did you mean?"))
    var item: VestigoMediaEntity

    static var parameterSummary: some ParameterSummary { Summary("Mark \(\.$item) as a favourite in Vestigo") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: VestigoIntentWriter.addToFavourites(entity: item))))
    }
}

@available(iOS 16.0, *)
struct RemoveFromVestigoFavouritesIntent: AppIntent {
    static var title: LocalizedStringResource = "Remove from Vestigo favourites"
    static var description = IntentDescription("Removes a movie or show from your Vestigo favourites.", categoryName: "Library")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Item", requestValueDialog: IntentDialog("Which movie or show?"), requestDisambiguationDialog: IntentDialog("Which one did you mean?"))
    var item: VestigoMediaEntity

    static var parameterSummary: some ParameterSummary { Summary("Remove \(\.$item) from my Vestigo favourites") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: VestigoIntentWriter.removeFromFavourites(entity: item))))
    }
}

@available(iOS 16.0, *)
struct MarkNotInterestedInVestigoIntent: AppIntent {
    static var title: LocalizedStringResource = "Mark as not interested in Vestigo"
    static var description = IntentDescription("Marks a movie or show as not interested. Vestigo will de-emphasize it in recommendations.", categoryName: "Library")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Item", requestValueDialog: IntentDialog("Which movie or show?"), requestDisambiguationDialog: IntentDialog("Which one did you mean?"))
    var item: VestigoMediaEntity

    static var parameterSummary: some ParameterSummary { Summary("Mark \(\.$item) as not interested in Vestigo") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: VestigoIntentWriter.markNotInterested(entity: item))))
    }
}

// NOTE: `VestigoAppShortcuts` lives in `VestigoApp.swift` to avoid Previews
// thunk issues with compile-time literal strings in `#Preview {}` files.

// MARK: - Intent bridge

@available(iOS 16.0, *)
enum VestigoIntentBridge {
    enum LibrarySource { case watchlist, favourites, watched }

    static func watchlistItems(kindFilter: VestigoMediaKindFilter) -> [VestigoMediaEntity] {
        guard let library = loadLibrary() else { return [] }
        return collectEntities(from: library.watchlist, kindFilter: kindFilter, library: library)
    }

    static func favouriteItems(kindFilter: VestigoMediaKindFilter) -> [VestigoMediaEntity] {
        guard let library = loadLibrary() else { return [] }
        let keys = Set((library.favouriteItems).map(\.key))
        return collectEntities(from: keys, kindFilter: kindFilter, library: library)
    }

    static func watchedItems(kindFilter: VestigoMediaKindFilter) -> [VestigoMediaEntity] {
        guard let library = loadLibrary() else { return [] }
        return collectEntities(from: library.watched, kindFilter: kindFilter, library: library)
    }

    static func unwatchedWatchlistItems(kindFilter: VestigoMediaKindFilter) -> [VestigoMediaEntity] {
        guard let library = loadLibrary() else { return [] }
        let unwatched = library.watchlist.subtracting(library.watched)
        return unwatched
            .compactMap { library.items[$0] }
            .filter { matches(kind: $0.kind, filter: kindFilter) }
            .sorted { $0.voteAverage > $1.voteAverage }
            .map { entity(from: $0, library: library) }
    }

    static func recentlyWatchedItems(kindFilter: VestigoMediaKindFilter, limit: Int = 10) -> [VestigoMediaEntity] {
        guard let library = loadLibrary() else { return [] }
        var results: [VestigoMediaEntity] = []
        var seen = Set<MediaKey>()
        for key in library.watchedOrder.reversed() {
            guard seen.insert(key).inserted,
                  library.watched.contains(key),
                  let item = library.items[key],
                  matches(kind: item.kind, filter: kindFilter) else { continue }
            results.append(entity(from: item, library: library))
            if results.count >= limit { break }
        }
        return results
    }

    static func topRatedItems(kindFilter: VestigoMediaKindFilter, limit: Int = 10) -> [VestigoMediaEntity] {
        guard let library = loadLibrary() else { return [] }
        return library.ratings
            .filter { $0.value > 0 }
            .compactMap { (key, rating) -> (MediaItem, Double)? in
                guard let item = library.items[key], matches(kind: item.kind, filter: kindFilter) else { return nil }
                return (item, rating)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { entity(from: $0.0, library: library) }
    }

    static func itemStatus(entityID: String, title: String) -> String {
        guard let library = loadLibrary(), let key = mediaKey(fromEntityID: entityID) else {
            return "\(title) isn't in your Vestigo library."
        }
        let mediaItem = library.items[key]
        let itemTitle = mediaItem?.title ?? title
        let watched = library.watched.contains(key)
        let onWatchlist = library.watchlist.contains(key)
        let favourite = library.favouriteKeys.contains(key) && watched
        let rating = library.ratings[key]

        var parts: [String] = []
        if watched {
            if let r = rating, r > 0 {
                parts.append("You've watched \(itemTitle) and rated it \(r.formatted(.number.precision(.fractionLength(1))))★.")
            } else {
                parts.append("You've watched \(itemTitle) in Vestigo.")
            }
            if favourite { parts.append("It's one of your favourites.") }
        } else if onWatchlist {
            parts.append("\(itemTitle) is on your watchlist but you haven't watched it yet.")
        } else {
            parts.append("\(itemTitle) isn't on your watchlist or in your watch history.")
        }
        return parts.joined(separator: " ")
    }

    static func collectionItems(named name: String) -> (found: Bool, name: String, entities: [VestigoMediaEntity]) {
        guard let library = loadLibrary() else { return (false, name, []) }
        let manual = library.collections.filter { !$0.isDynamic }
        let collection = manual.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
                      ?? manual.first { $0.name.lowercased().contains(name.lowercased()) }
        guard let collection else { return (false, name, []) }
        let items = collection.itemKeys
            .compactMap { library.items[$0] }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            .map { entity(from: $0, library: library) }
        return (true, collection.name, items)
    }

    static func libraryStats() -> String {
        guard let library = loadLibrary() else { return "Unable to read your Vestigo library." }
        let watchedMovies = library.watched.filter { $0.kind == .movie }.count
        let watchedShows  = library.watched.filter { $0.kind == .tv }.count
        let watchlistCount = library.watchlist.count
        let favouritesCount = library.favouriteKeys.filter { library.watched.contains($0) }.count
        let ratingValues = library.ratings.values.filter { $0 > 0 }
        let avgRating = ratingValues.isEmpty ? nil : ratingValues.reduce(0, +) / Double(ratingValues.count)

        var parts: [String] = []
        if watchedMovies > 0 || watchedShows > 0 {
            if watchedMovies > 0 && watchedShows > 0 {
                parts.append("You've watched \(watchedMovies) movie\(watchedMovies == 1 ? "" : "s") and \(watchedShows) show\(watchedShows == 1 ? "" : "s") in Vestigo")
            } else if watchedMovies > 0 {
                parts.append("You've watched \(watchedMovies) movie\(watchedMovies == 1 ? "" : "s") in Vestigo")
            } else {
                parts.append("You've watched \(watchedShows) show\(watchedShows == 1 ? "" : "s") in Vestigo")
            }
        } else {
            parts.append("You haven't marked anything as watched in Vestigo yet")
        }
        if watchlistCount > 0 { parts.append("you have \(watchlistCount) item\(watchlistCount == 1 ? "" : "s") on your watchlist") }
        if favouritesCount > 0 { parts.append("\(favouritesCount) favourite\(favouritesCount == 1 ? "" : "s")") }
        if let avg = avgRating { parts.append("average rating \(avg.formatted(.number.precision(.fractionLength(1))))★") }
        return parts.joined(separator: ", ") + "."
    }

    static func entities(withIDs identifiers: [String]) -> [VestigoMediaEntity] {
        guard let library = loadLibrary() else { return [] }
        return identifiers.compactMap { identifier -> VestigoMediaEntity? in
            guard let key = mediaKey(fromEntityID: identifier), let item = library.items[key] else { return nil }
            return entity(from: item, library: library)
        }
    }

    static func suggestedEntities() -> [VestigoMediaEntity] {
        guard let library = loadLibrary() else { return [] }
        var seenIDs = Set<String>()
        var results: [VestigoMediaEntity] = []
        let keys = Array(library.watchlist) + library.favouriteItems.map(\.key)
        for key in keys {
            guard let item = library.items[key] else { continue }
            let e = entity(from: item, library: library)
            if seenIDs.insert(e.id).inserted {
                results.append(e)
                if results.count >= 12 { break }
            }
        }
        return results
    }

    static func libraryMatches(query: String) -> [VestigoMediaEntity] {
        guard let library = loadLibrary() else { return [] }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }
        return library.items.values
            .filter { $0.title.lowercased().contains(needle) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            .prefix(20)
            .map { entity(from: $0, library: library) }
    }

    // MARK: Dialog builders

    static func watchlistDialog(for items: [VestigoMediaEntity], kindFilter: VestigoMediaKindFilter) -> IntentDialog {
        guard let library = loadLibrary() else { return dialog(for: items, source: .watchlist, kindFilter: kindFilter) }
        let noun = kindFilter.noun
        if items.isEmpty { return IntentDialog(LocalizedStringResource(stringLiteral: "Your Vestigo watchlist has no \(noun) yet.")) }

        let unwatched = items.filter { entity in
            guard let key = mediaKey(fromEntityID: entity.id) else { return true }
            return !library.watched.contains(key)
        }
        let topUnwatched = unwatched
            .compactMap { e -> (String, Double)? in
                guard let key = mediaKey(fromEntityID: e.id), let item = library.items[key] else { return nil }
                return (e.title, item.voteAverage)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(3)
            .map(\.0)

        let preview = topUnwatched.isEmpty ? formatList(items.prefix(3).map(\.title)) : formatList(Array(topUnwatched))
        let total = items.count
        let unwatchedCount = unwatched.count

        if unwatchedCount == 0 {
            return IntentDialog(LocalizedStringResource(stringLiteral: "You have \(total) \(noun) on your watchlist and you've already watched all of them."))
        }
        if total == unwatchedCount {
            return IntentDialog(LocalizedStringResource(stringLiteral: "You have \(total) unwatched \(noun) on your Vestigo watchlist. Top picks: \(preview)."))
        }
        return IntentDialog(LocalizedStringResource(stringLiteral: "You have \(total) \(noun) on your watchlist, \(unwatchedCount) still to watch. Top unwatched: \(preview)."))
    }

    static func watchedDialog(recentItems: [VestigoMediaEntity], totalCount: Int, kindFilter: VestigoMediaKindFilter) -> IntentDialog {
        let noun = kindFilter.noun
        if totalCount == 0 { return IntentDialog(LocalizedStringResource(stringLiteral: "You haven't watched any \(noun) in Vestigo yet.")) }
        let names = recentItems.prefix(5).map { e -> String in
            if let r = e.rating, r > 0 { return "\(e.title) (\(r.formatted(.number.precision(.fractionLength(1))))★)" }
            return e.title
        }
        let preview = formatList(Array(names))
        if totalCount <= 5 {
            return IntentDialog(LocalizedStringResource(stringLiteral: "You've watched \(preview) in Vestigo."))
        }
        return IntentDialog(LocalizedStringResource(stringLiteral: "You've watched \(totalCount) \(noun) in Vestigo. Most recently: \(preview)."))
    }

    static func dialog(for items: [VestigoMediaEntity], source: LibrarySource, kindFilter: VestigoMediaKindFilter) -> IntentDialog {
        let noun = kindFilter.noun
        let sourceLabel: String = {
            switch source {
            case .watchlist: return "on your watchlist"
            case .favourites: return "in your favourites"
            case .watched: return "in your watched history"
            }
        }()
        if items.isEmpty { return IntentDialog(LocalizedStringResource(stringLiteral: "You don't have any \(noun) \(sourceLabel) yet.")) }
        let preview = formatList(items.prefix(3).map(\.title))
        if items.count <= 3 { return IntentDialog(LocalizedStringResource(stringLiteral: "You have \(preview) \(sourceLabel).")) }
        return IntentDialog(LocalizedStringResource(stringLiteral: "You have \(items.count) \(noun) \(sourceLabel), including \(preview)."))
    }

    // MARK: Formatting

    static func formatList(_ items: any Sequence<String>) -> String {
        let arr = Array(items)
        switch arr.count {
        case 0: return "nothing"
        case 1: return arr[0]
        case 2: return "\(arr[0]) and \(arr[1])"
        default: return "\(arr.dropLast().joined(separator: ", ")), and \(arr.last!)"
        }
    }

    // MARK: Private helpers

    private static func loadLibrary() -> UserLibrary? {
        guard let data = UserDefaults.standard.data(forKey: "Vestigo.library") else { return nil }
        return try? JSONDecoder().decode(UserLibrary.self, from: data)
    }

    private static func collectEntities(from keys: Set<MediaKey>, kindFilter: VestigoMediaKindFilter, library: UserLibrary) -> [VestigoMediaEntity] {
        keys
            .compactMap { library.items[$0] }
            .filter { matches(kind: $0.kind, filter: kindFilter) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            .map { entity(from: $0, library: library) }
    }

    private static func entity(from item: MediaItem, library: UserLibrary) -> VestigoMediaEntity {
        let filter: VestigoMediaKindFilter = item.kind == .tv ? .shows : .movies
        let year: String? = item.releaseDate.flatMap { date in
            guard date.count >= 4 else { return nil }
            let prefix = String(date.prefix(4))
            return Int(prefix) != nil ? prefix : nil
        }
        return VestigoMediaEntity(
            id: entityID(for: item.key),
            title: item.title,
            kindFilter: filter,
            releaseYear: year,
            rating: library.ratings[item.key],
            isWatched: library.watched.contains(item.key),
            isOnWatchlist: library.watchlist.contains(item.key),
            isFavourite: library.favouriteKeys.contains(item.key) && library.watched.contains(item.key)
        )
    }

    private static func entityID(for key: MediaKey) -> String { "\(key.kind.rawValue)-\(key.id)" }

    static func mediaKey(fromEntityID identifier: String) -> MediaKey? {
        let parts = identifier.split(separator: "-", maxSplits: 1)
        guard parts.count == 2, let id = Int(parts[1]) else { return nil }
        switch String(parts[0]) {
        case "tv":     return MediaKey(id: id, kind: .tv)
        case "movie":  return MediaKey(id: id, kind: .movie)
        default:       return nil
        }
    }

    private static func matches(kind: MediaKind, filter: VestigoMediaKindFilter) -> Bool {
        switch filter {
        case .movies: return kind == .movie
        case .shows:  return kind == .tv
        case .both:   return kind == .movie || kind == .tv
        }
    }
}

#endif
