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
}

@available(iOS 16.0, *)
struct VestigoMediaEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Vestigo item" }

    static var defaultQuery: VestigoMediaEntityQuery { VestigoMediaEntityQuery() }

    var id: String
    var title: String
    var kindFilter: VestigoMediaKindFilter
    var releaseYear: String?

    var displayRepresentation: DisplayRepresentation {
        var subtitleParts: [String] = [kindFilter.subtitleWord]
        if let releaseYear { subtitleParts.append(releaseYear) }
        return DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: title),
            subtitle: LocalizedStringResource(stringLiteral: subtitleParts.joined(separator: " • "))
        )
    }
}

@available(iOS 16.0, *)
struct VestigoMediaEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [VestigoMediaEntity.ID]) async throws -> [VestigoMediaEntity] {
        VestigoIntentBridge.entities(withIDs: identifiers)
    }

    // Called by Siri when the user speaks a title. We search the user's library
    // first (so items they've already saved take priority), then extend with a
    // TMDb catalog search so unknown titles like new releases can also resolve.
    // Multiple returns automatically trigger Siri's disambiguation UI, which uses
    // each entity's `displayRepresentation` (title + kind + year) to help the
    // user pick the right item.
    @MainActor
    func entities(matching string: String) async throws -> [VestigoMediaEntity] {
        var seen = Set<String>()
        var results: [VestigoMediaEntity] = []

        for entity in VestigoIntentBridge.libraryMatches(query: string) {
            if seen.insert(entity.id).inserted {
                results.append(entity)
            }
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

// MARK: Catalog search — used by Siri disambiguation for titles that aren't
// already in the library. Hits the same backend proxy the app uses for TMDb.
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
                return VestigoMediaEntity(
                    id: "\(mediaType)-\(id)",
                    title: title,
                    kindFilter: filter,
                    releaseYear: year
                )
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
        // swiftlint:disable:next identifier_name
        let media_type: String?
        // swiftlint:disable:next identifier_name
        let release_date: String?
        // swiftlint:disable:next identifier_name
        let first_air_date: String?
    }
}

// MARK: Library writer — mutates the same Vestigo.library UserDefaults blob the
// app persists, so voice-driven actions land in the user's library on disk.
// Posts a notification VestigoModel observes to refresh in-memory state if the
// app is running when the intent executes.
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
            if !library.watchedOrder.contains(key) {
                library.watchedOrder.append(key)
            }
            if let rating {
                library.ratings[key] = max(0, min(5, rating))
            }
            if let rating {
                let stars = rating.formatted(.number.precision(.fractionLength(1)))
                return "Marked \(entity.title) as watched and rated it \(stars) stars."
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
            library.favouriteKeys.insert(key)
            return "Marked \(entity.title) as a favourite in Vestigo."
        }
    }

    static func removeFromFavourites(entity: VestigoMediaEntity) -> String {
        mutate { library in
            let key = mediaKey(for: entity)
            library.favouriteKeys.remove(key)
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

    // MARK: - Internal

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

    // Minimal MediaItem so the item shows up in the app's watchlist/history
    // even if it wasn't previously in the library. The app will refresh the
    // full detail record next time the user opens the item.
    private static func synthesize(entity: VestigoMediaEntity, key: MediaKey) -> MediaItem {
        MediaItem(
            id: key.id,
            kind: key.kind,
            title: entity.title,
            overview: "",
            posterPath: nil,
            backdropPath: nil,
            releaseDate: entity.releaseYear.map { "\($0)-01-01" },
            voteAverage: 0,
            voteCount: nil,
            genreIDs: [],
            creditRole: nil,
            runtime: nil,
            originalLanguage: nil
        )
    }
}

@available(iOS 16.0, *)
struct ShowVestigoWatchlistIntent: AppIntent {
    static var title: LocalizedStringResource = "Show my Vestigo watchlist"

    static var description = IntentDescription(
        "Lists the movies and shows saved on your Vestigo watchlist.",
        categoryName: "Library"
    )

    @Parameter(title: "Type", default: .both)
    var kindFilter: VestigoMediaKindFilter

    static var parameterSummary: some ParameterSummary {
        Summary("Show my Vestigo watchlist \(\.$kindFilter)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[VestigoMediaEntity]> & ProvidesDialog {
        let items = VestigoIntentBridge.watchlistItems(kindFilter: kindFilter)
        return .result(value: items, dialog: VestigoIntentBridge.dialog(for: items, source: .watchlist, kindFilter: kindFilter))
    }
}

@available(iOS 16.0, *)
struct ShowVestigoFavouritesIntent: AppIntent {
    static var title: LocalizedStringResource = "Show my Vestigo favourites"

    static var description = IntentDescription(
        "Lists the movies and shows you've marked as favourites in Vestigo.",
        categoryName: "Library"
    )

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

    static var description = IntentDescription(
        "Lists the movies and shows you've marked as watched in Vestigo.",
        categoryName: "Library"
    )

    @Parameter(title: "Type", default: .both)
    var kindFilter: VestigoMediaKindFilter

    static var parameterSummary: some ParameterSummary {
        Summary("Show what I've watched in Vestigo \(\.$kindFilter)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[VestigoMediaEntity]> & ProvidesDialog {
        let items = VestigoIntentBridge.watchedItems(kindFilter: kindFilter)
        return .result(value: items, dialog: VestigoIntentBridge.dialog(for: items, source: .watched, kindFilter: kindFilter))
    }
}

// MARK: - Action intents

@available(iOS 16.0, *)
struct AddToVestigoWatchlistIntent: AppIntent {
    static var title: LocalizedStringResource = "Add to Vestigo watchlist"
    static var description = IntentDescription(
        "Saves a movie or show to your Vestigo watchlist.",
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
        Summary("Add \(\.$item) to my Vestigo watchlist")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = VestigoIntentWriter.addToWatchlist(entity: item)
        return .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: message)))
    }
}

@available(iOS 16.0, *)
struct RemoveFromVestigoWatchlistIntent: AppIntent {
    static var title: LocalizedStringResource = "Remove from Vestigo watchlist"
    static var description = IntentDescription(
        "Removes a movie or show from your Vestigo watchlist.",
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
        Summary("Remove \(\.$item) from my Vestigo watchlist")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = VestigoIntentWriter.removeFromWatchlist(entity: item)
        return .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: message)))
    }
}

@available(iOS 16.0, *)
struct MarkWatchedInVestigoIntent: AppIntent {
    static var title: LocalizedStringResource = "Mark as watched in Vestigo"
    static var description = IntentDescription(
        "Marks a movie or show as watched. Optionally records a star rating from 0 to 5.",
        categoryName: "Library"
    )
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: "Item",
        requestValueDialog: IntentDialog("Which movie or show?"),
        requestDisambiguationDialog: IntentDialog("Which one did you mean?")
    )
    var item: VestigoMediaEntity

    @Parameter(
        title: "Rating",
        description: "Optional star rating from 0 to 5.",
        default: nil,
        inclusiveRange: (0.0, 5.0)
    )
    var rating: Double?

    static var parameterSummary: some ParameterSummary {
        Summary("Mark \(\.$item) as watched") {
            \.$rating
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = VestigoIntentWriter.markWatched(entity: item, rating: rating)
        return .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: message)))
    }
}

@available(iOS 16.0, *)
struct MarkUnwatchedInVestigoIntent: AppIntent {
    static var title: LocalizedStringResource = "Mark as unwatched in Vestigo"
    static var description = IntentDescription(
        "Removes a movie or show from your Vestigo watch history.",
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
        Summary("Mark \(\.$item) as unwatched in Vestigo")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = VestigoIntentWriter.markUnwatched(entity: item)
        return .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: message)))
    }
}

@available(iOS 16.0, *)
struct RateInVestigoIntent: AppIntent {
    static var title: LocalizedStringResource = "Rate a movie or show in Vestigo"
    static var description = IntentDescription(
        "Sets a star rating from 0 to 5 for a movie or show in Vestigo.",
        categoryName: "Library"
    )
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: "Item",
        requestValueDialog: IntentDialog("Which movie or show?"),
        requestDisambiguationDialog: IntentDialog("Which one did you mean?")
    )
    var item: VestigoMediaEntity

    @Parameter(
        title: "Stars",
        description: "Star rating from 0 to 5.",
        inclusiveRange: (0.0, 5.0)
    )
    var stars: Double

    static var parameterSummary: some ParameterSummary {
        Summary("Rate \(\.$item) \(\.$stars) stars in Vestigo")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = VestigoIntentWriter.rate(entity: item, stars: stars)
        return .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: message)))
    }
}

@available(iOS 16.0, *)
struct AddToVestigoFavouritesIntent: AppIntent {
    static var title: LocalizedStringResource = "Add to Vestigo favourites"
    static var description = IntentDescription(
        "Marks a movie or show as a favourite in Vestigo.",
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
        Summary("Mark \(\.$item) as a favourite in Vestigo")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = VestigoIntentWriter.addToFavourites(entity: item)
        return .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: message)))
    }
}

@available(iOS 16.0, *)
struct RemoveFromVestigoFavouritesIntent: AppIntent {
    static var title: LocalizedStringResource = "Remove from Vestigo favourites"
    static var description = IntentDescription(
        "Removes a movie or show from your Vestigo favourites.",
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
        Summary("Remove \(\.$item) from my Vestigo favourites")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = VestigoIntentWriter.removeFromFavourites(entity: item)
        return .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: message)))
    }
}

@available(iOS 16.0, *)
struct MarkNotInterestedInVestigoIntent: AppIntent {
    static var title: LocalizedStringResource = "Mark as not interested in Vestigo"
    static var description = IntentDescription(
        "Marks a movie or show as not interested. Vestigo will de-emphasize it and similar titles in recommendations.",
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
        Summary("Mark \(\.$item) as not interested in Vestigo")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = VestigoIntentWriter.markNotInterested(entity: item)
        return .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: message)))
    }
}

// NOTE: `VestigoAppShortcuts` (the `AppShortcutsProvider`) lives in
// `VestigoApp.swift` — its `shortTitle:` and `systemImageName:` require
// compile-time string literals, but SwiftUI Previews thunk literals in files
// that contain a `#Preview {}` block. Keeping it out of this file keeps the
// preview canvas working while the app build itself compiles the same phrases.

// MARK: Intent bridge — reads the same UserDefaults the app writes to.

@available(iOS 16.0, *)
enum VestigoIntentBridge {
    enum LibrarySource {
        case watchlist, favourites, watched
    }

    static func watchlistItems(kindFilter: VestigoMediaKindFilter) -> [VestigoMediaEntity] {
        collectEntities(from: loadLibrary()?.watchlist ?? [], kindFilter: kindFilter)
    }

    static func favouriteItems(kindFilter: VestigoMediaKindFilter) -> [VestigoMediaEntity] {
        collectEntities(from: loadLibrary()?.favouriteKeys ?? [], kindFilter: kindFilter)
    }

    static func watchedItems(kindFilter: VestigoMediaKindFilter) -> [VestigoMediaEntity] {
        collectEntities(from: loadLibrary()?.watched ?? [], kindFilter: kindFilter)
    }

    static func entities(withIDs identifiers: [String]) -> [VestigoMediaEntity] {
        guard let library = loadLibrary() else { return [] }
        return identifiers.compactMap { identifier in
            guard let key = mediaKey(fromEntityID: identifier), let item = library.items[key] else { return nil }
            return entity(from: item)
        }
    }

    static func suggestedEntities() -> [VestigoMediaEntity] {
        // Best-effort short suggestion list: watchlist + favourites, uniqued, capped at 12.
        guard let library = loadLibrary() else { return [] }
        var seenIDs = Set<String>()
        var results: [VestigoMediaEntity] = []
        let keys = Array(library.watchlist) + Array(library.favouriteKeys)
        for key in keys {
            guard let item = library.items[key] else { continue }
            let e = entity(from: item)
            if seenIDs.insert(e.id).inserted {
                results.append(e)
                if results.count >= 12 { break }
            }
        }
        return results
    }

    // Case-insensitive title-contains match across everything in the user's library.
    // Used by Siri disambiguation before we fall back to a catalog search.
    static func libraryMatches(query: String) -> [VestigoMediaEntity] {
        guard let library = loadLibrary() else { return [] }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }
        let matched = library.items.values.filter {
            $0.title.lowercased().contains(needle)
        }
        return matched
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            .prefix(20)
            .map { entity(from: $0) }
    }

    static func dialog(for items: [VestigoMediaEntity], source: LibrarySource, kindFilter: VestigoMediaKindFilter) -> IntentDialog {
        let noun = kindFilter == .both ? "items" : (kindFilter == .movies ? "movies" : "shows")
        let sourceLabel: String = {
            switch source {
            case .watchlist: return "on your watchlist"
            case .favourites: return "in your favourites"
            case .watched: return "in your watched history"
            }
        }()

        if items.isEmpty {
            return IntentDialog(LocalizedStringResource(stringLiteral: "You don't have any \(noun) \(sourceLabel) yet."))
        }

        let previewNames = items.prefix(3).map(\.title).joined(separator: ", ")
        if items.count <= 3 {
            return IntentDialog(LocalizedStringResource(stringLiteral: "You have \(previewNames) \(sourceLabel)."))
        }

        return IntentDialog(LocalizedStringResource(stringLiteral: "You have \(items.count) \(noun) \(sourceLabel), including \(previewNames)."))
    }

    // MARK: Private helpers reaching into the app's on-disk state.

    private static func loadLibrary() -> UserLibrary? {
        guard let data = UserDefaults.standard.data(forKey: "Vestigo.library") else { return nil }
        return try? JSONDecoder().decode(UserLibrary.self, from: data)
    }

    private static func collectEntities(from keys: Set<MediaKey>, kindFilter: VestigoMediaKindFilter) -> [VestigoMediaEntity] {
        guard let library = loadLibrary() else { return [] }
        return keys
            .compactMap { library.items[$0] }
            .filter { matches(kind: $0.kind, filter: kindFilter) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            .map { entity(from: $0) }
    }

    private static func entity(from item: MediaItem) -> VestigoMediaEntity {
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
            releaseYear: year
        )
    }

    private static func entityID(for key: MediaKey) -> String {
        "\(key.kind.rawValue)-\(key.id)"
    }

    private static func mediaKey(fromEntityID identifier: String) -> MediaKey? {
        let parts = identifier.split(separator: "-", maxSplits: 1)
        guard parts.count == 2, let id = Int(parts[1]) else { return nil }
        let rawKind = String(parts[0])
        let kind: MediaKind
        switch rawKind {
        case "tv": kind = .tv
        case "movie": kind = .movie
        case "person": kind = .person
        default: return nil
        }
        return MediaKey(id: id, kind: kind)
    }

    private static func matches(kind: MediaKind, filter: VestigoMediaKindFilter) -> Bool {
        switch filter {
        case .movies: return kind == .movie
        case .shows: return kind == .tv
        case .both: return kind == .movie || kind == .tv
        }
    }
}

#endif
