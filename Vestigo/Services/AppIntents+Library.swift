import Foundation
import SwiftUI
#if canImport(AppIntents)
import AppIntents

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

#endif
