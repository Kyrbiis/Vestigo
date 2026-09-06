import Foundation
import SwiftUI
#if canImport(AppIntents)
import AppIntents

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
