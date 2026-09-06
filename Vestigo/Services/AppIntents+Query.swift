import Foundation
import SwiftUI
#if canImport(AppIntents)
import AppIntents

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

#endif
