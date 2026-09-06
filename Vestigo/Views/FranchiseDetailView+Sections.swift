import SwiftUI
import Foundation

struct FranchiseDetailModePicker: View {
    @Binding var mode: FranchiseDetailMode
    var watchedTitle: String = "Watched"
    var recommendedTitle: String = "Recommended"

    var body: some View {
        Picker("Franchise view", selection: $mode) {
            Text(watchedTitle).tag(FranchiseDetailMode.watched)
            Text(recommendedTitle).tag(FranchiseDetailMode.recommended)
        }
        .pickerStyle(.segmented)
        .liquidGlass(cornerRadius: 18)
    }
}

enum FranchiseLibrary {
    static var seedFranchises: [FranchiseCollection] {
        []
    }

    static func defaultFranchises(matching items: [MediaItem], tvdbLists: [String: TVDBFranchiseList] = [:]) -> [FranchiseCollection] {
        seedFranchises
            .map { franchise in
                let matchedItems = self.items(in: franchise, from: items)
                let representativePoster = matchedItems.first(where: { $0.posterURL != nil })?.posterURL

                let localFranchise = FranchiseCollection(
                    id: franchise.id,
                    title: franchise.title,
                    logoSystemName: franchise.logoSystemName,
                    logoURL: franchise.logoURL ?? representativePoster,
                    aliases: franchise.aliases,
                    description: franchise.description,
                    tvdbListQuery: franchise.tvdbListQuery,
                    tvdbListID: franchise.tvdbListID,
                    tvdbMemberTitles: franchise.tvdbMemberTitles,
                    usesTVDBMembership: franchise.usesTVDBMembership,
                    tmdbCollectionID: franchise.tmdbCollectionID,
                    exactMemberIDs: franchise.exactMemberIDs
                )

                guard let tvdbList = tvdbLists[franchise.id] else {
                    return localFranchise
                }

                return FranchiseCollection(
                    id: franchise.id,
                    title: franchise.title,
                    logoSystemName: franchise.logoSystemName,
                    logoURL: localFranchise.logoURL,
                    aliases: franchise.aliases,
                    description: tvdbList.overview ?? franchise.description,
                    tvdbListQuery: franchise.tvdbListQuery,
                    tvdbListID: tvdbList.id,
                    tvdbMemberTitles: tvdbList.memberTitles,
                    usesTVDBMembership: !tvdbList.memberTitles.isEmpty,
                    tmdbCollectionID: franchise.tmdbCollectionID,
                    exactMemberIDs: franchise.exactMemberIDs
                )
            }
            .filter { !self.items(in: $0, from: items).isEmpty }
    }

    static func items(in franchise: FranchiseCollection, from sourceItems: [MediaItem]) -> [MediaItem] {
        sortedItems(
            sourceItems.filter { item in item.shouldShowInDiscovery && matches(item, franchise: franchise) },
            using: .releaseDate,
            library: UserLibrary()
        )
    }

    static func recommendations(in franchise: FranchiseCollection, from sourceItems: [MediaItem], library: UserLibrary, settings: AppSettings, sort: SortOption, externalRatings: [MediaKey: ExternalRatings] = [:], ratingSource: RatingSource = .imdb) -> [MediaItem] {
        let watchedGenreIDs = Set(library.watchedItems.flatMap(\.genreIDs))
        let favouriteKeys = Array(library.favouriteKeys)

        return sourceItems
            .filter { item in
                item.shouldShowInDiscovery
                && matches(item, franchise: franchise)
                && !library.isWatched(item.key)
                && (!settings.hideUpcomingFromCollectionRecommendations || !item.isUpcoming)
            }
            .sorted { lhs, rhs in
                let lhsScore = recommendationScore(for: lhs, watchedGenreIDs: watchedGenreIDs, favouriteKeys: favouriteKeys, ratings: library.ratings, externalRatings: externalRatings, ratingSource: ratingSource)
                let rhsScore = recommendationScore(for: rhs, watchedGenreIDs: watchedGenreIDs, favouriteKeys: favouriteKeys, ratings: library.ratings, externalRatings: externalRatings, ratingSource: ratingSource)

                if lhsScore != rhsScore {
                    return lhsScore > rhsScore
                }

                return comesBefore(lhs, rhs, using: sort, library: library, externalRatings: externalRatings, ratingSource: ratingSource)
            }
    }

    private static func matches(_ item: MediaItem, franchise: FranchiseCollection) -> Bool {
        let exactID = "\(item.kind.tmdbPath)-\(item.id)"
        if !franchise.exactMemberIDs.isEmpty {
            return franchise.exactMemberIDs.contains(exactID)
        }

        let normalizedTitle = VestigoBackendClient.normalizedTitle(item.title)
        let haystack = "\(item.title) \(item.overview)"
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()

        let localAliasMatch = franchise.aliases.contains { alias in
            haystack.contains(alias.lowercased())
        }

        guard franchise.usesTVDBMembership else {
            return localAliasMatch
        }

        let tvdbExactMatch = franchise.tvdbMemberTitles.contains(normalizedTitle)
        let tvdbPartialMatch = franchise.tvdbMemberTitles.contains { tvdbTitle in
            !tvdbTitle.isEmpty && (normalizedTitle.contains(tvdbTitle) || tvdbTitle.contains(normalizedTitle))
        }

        return tvdbExactMatch || tvdbPartialMatch || localAliasMatch
    }

    static func sortedItems(_ items: [MediaItem], using sort: SortOption, library: UserLibrary, externalRatings: [MediaKey: ExternalRatings] = [:], ratingSource: RatingSource = .imdb, direction: SortDirection = .descending) -> [MediaItem] {
        let result = items.sorted { lhs, rhs in
            comesBefore(lhs, rhs, using: sort, library: library, externalRatings: externalRatings, ratingSource: ratingSource)
        }
        return direction == .ascending ? result.reversed() : result
    }

    private static func comesBefore(_ lhs: MediaItem, _ rhs: MediaItem, using sort: SortOption, library: UserLibrary, externalRatings: [MediaKey: ExternalRatings], ratingSource: RatingSource) -> Bool {
        switch sort {
        case .tmdbRating:
            let lhsRating = ratingValue(for: lhs, externalRatings: externalRatings, ratingSource: ratingSource)
            let rhsRating = ratingValue(for: rhs, externalRatings: externalRatings, ratingSource: ratingSource)
            if lhsRating != rhsRating {
                return lhsRating > rhsRating
            }
        case .releaseDate:
            let lhsYear = releaseYear(for: lhs)
            let rhsYear = releaseYear(for: rhs)
            if lhsYear != rhsYear {
                return lhsYear > rhsYear
            }
        case .myRating:
            let lhsRating = library.ratings[lhs.key] ?? 0
            let rhsRating = library.ratings[rhs.key] ?? 0
            if lhsRating != rhsRating {
                return lhsRating > rhsRating
            }
        }

        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private static func recommendationScore(for item: MediaItem, watchedGenreIDs: Set<Int>, favouriteKeys: [MediaKey], ratings: [MediaKey: Double], externalRatings: [MediaKey: ExternalRatings], ratingSource: RatingSource) -> Double {
        let genreOverlap = Double(item.genreIDs.filter { watchedGenreIDs.contains($0) }.count) * 1.25
        let externalScore = max(ratingValue(for: item, externalRatings: externalRatings, ratingSource: ratingSource), 0) / 2.0
        let releaseScore = Double(max(0, min(releaseYear(for: item) - 1970, 60))) / 30.0
        let ratingScore = ratings[item.key] ?? 0
        let favouritePenalty = favouriteKeys.contains(item.key) ? 0.5 : 0

        return genreOverlap + externalScore + releaseScore + ratingScore - favouritePenalty
    }

    private static func ratingValue(for item: MediaItem, externalRatings: [MediaKey: ExternalRatings], ratingSource: RatingSource) -> Double {
        if ratingSource == .imdb {
            return externalRatings[item.key]?.imdbRating ?? -1
        }

        return item.voteAverage
    }

    private static func releaseYear(for item: MediaItem) -> Int {
        if let releaseDate = item.releaseDate, let year = Int(releaseDate.prefix(4)) {
            return year
        }

        if let year = Int(item.releaseYearText.prefix(4)) {
            return year
        }

        return 0
    }
}
