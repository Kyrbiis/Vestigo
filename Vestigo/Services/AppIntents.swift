import Foundation
import SwiftUI
#if canImport(AppIntents)
import AppIntents

// MARK: - Shared types

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

// NOTE: `VestigoAppShortcuts` lives in `VestigoApp.swift` to avoid Previews
// thunk issues with compile-time literal strings in `#Preview {}` files.

#endif
