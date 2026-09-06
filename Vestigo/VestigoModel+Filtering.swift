import SwiftUI
import Foundation

extension VestigoModel {

    var filteredSearchResults: [MediaItem] {
        searchResults.filter { item in
            guard searchFilter != .people else { return true }

            if let minimumTMDbRatingFilter, ratingSortValue(for: item) < minimumTMDbRatingFilter.minimumRating {
                return false
            }

            if !selectedDateFilters.isEmpty {
                guard let releaseDate = item.releaseDateValue else { return false }
                guard selectedDateFilters.contains(where: { $0.contains(releaseDate) }) else {
                    return false
                }
            }

            if !selectedRuntimeFilters.isEmpty {
                guard let runtime = item.runtime, runtime > 0 else {
                    return true
                }

                guard selectedRuntimeFilters.contains(where: { $0.contains(runtime) }) else {
                    return false
                }
            }

            if settings.hideUpcomingFromSearch && item.isUpcoming {
                return false
            }

            return true
        }
    }

    var activeSearchFilterCount: Int {
        selectedRuntimeFilters.count + selectedDateFilters.count + (minimumTMDbRatingFilter == nil ? 0 : 1)
    }

    func prioritisedForLanguage(_ items: [MediaItem]) -> [MediaItem] {
        guard settings.prioritiseEnglish else { return items }

        return items.sorted { lhs, rhs in
            let lhsEnglish = lhs.originalLanguage == nil || lhs.originalLanguage == "en"
            let rhsEnglish = rhs.originalLanguage == nil || rhs.originalLanguage == "en"

            if lhsEnglish != rhsEnglish {
                return lhsEnglish
            }

            return false
        }
    }

    func filteredForAnimePreference(_ items: [MediaItem]) -> [MediaItem] {
        guard settings.hideAnimeResults else { return items }

        let animeGenreIDs: Set<Int> = [16]
        let animeKeywords = [
            "anime",
            "japanese animation",
            "manga",
            "shonen",
            "shounen",
            "shojo",
            "shoujo",
            "isekai"
        ]

        return items.filter { item in
            if !animeGenreIDs.isDisjoint(with: Set(item.genreIDs)) {
                return false
            }

            let searchableText = "\(item.title) \(item.overview)".lowercased()
            return !animeKeywords.contains { searchableText.contains($0) }
        }
    }

    func filteredForWatchedPreference(_ items: [MediaItem], hideWatched: Bool) -> [MediaItem] {
        guard hideWatched else { return items }

        return items.filter { item in
            !library.isWatched(item.key)
        }
    }

    func shouldHideAsShortFilm(_ item: MediaItem, enabled: Bool) -> Bool {
        guard enabled else { return false }
        guard item.kind == .movie else { return false }
        let runtime = detailsCache[item.key]?.runtime ?? item.runtime ?? 0
        return runtime > 0 && runtime <= 40
    }

    func shouldHideForLowestAgeRating(_ item: MediaItem, enabled: Bool) -> Bool {
        guard enabled else { return false }
        guard let ageRating = detailsCache[item.key]?.ageRating else { return false }
        return Self.isLowestAgeRating(ageRating)
    }

    func shouldHideAsSupplementalContent(_ item: MediaItem, enabled: Bool) -> Bool {
        guard enabled else { return false }
        guard item.kind == .movie else { return false }

        let detail = detailsCache[item.key]
        let runtime = detail?.runtime ?? item.runtime
        let voteCount = item.voteCount ?? 0
        let genres = Set(item.genreIDs)
        let hasDocumentaryGenre = genres.contains(99)
        let hasRegularFeatureRuntime = runtime.map { $0 >= 65 } ?? false
        let hasStrongAudienceFootprint = voteCount >= 500 || item.voteAverage >= 7.8
        let hasVisualCatalogMetadata = item.posterPath != nil && item.backdropPath != nil

        if hasRegularFeatureRuntime || hasStrongAudienceFootprint {
            return false
        }

        if hasDocumentaryGenre, let runtime, runtime > 0, runtime <= 60 {
            return true
        }

        if let runtime, runtime > 0, runtime <= 25, voteCount < 150 {
            return true
        }

        if hasDocumentaryGenre, voteCount < 75, !hasVisualCatalogMetadata {
            return true
        }

        return false
    }

    static func isLowestAgeRating(_ rawRating: String) -> Bool {
        let normalized = rawRating
            .uppercased()
            .replacingOccurrences(of: "_", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return ["G", "U", "TV-Y", "TV-G", "TV-Y7", "TV-Y7-FV"].contains(normalized)
    }

    func filteredContentCleanupIfNeeded(
        _ items: [MediaItem],
        hideShortFilms: Bool,
        hideExtrasAndPromos: Bool,
        loadMissingDetails: Bool = true
    ) async -> [MediaItem] {
        guard hideShortFilms || hideExtrasAndPromos || settings.hideLowestAgeRatings else { return items }

        var filtered: [MediaItem] = []

        for item in items {
            if loadMissingDetails, detailsCache[item.key] == nil {
                await loadBasicDetailIfNeeded(item)
            }

            if shouldHideAsShortFilm(item, enabled: hideShortFilms) {
                continue
            }

            if shouldHideAsSupplementalContent(item, enabled: hideExtrasAndPromos) {
                continue
            }

            if shouldHideForLowestAgeRating(item, enabled: settings.hideLowestAgeRatings) {
                continue
            }

            filtered.append(item)
        }

        return filtered
    }

    func filteredLowestAgeRatingsIfNeeded(_ items: [MediaItem]) -> [MediaItem] {
        guard settings.hideLowestAgeRatings else { return items }

        return items.filter { item in
            !shouldHideForLowestAgeRating(item, enabled: true)
        }
    }

    func preparedResults(_ items: [MediaItem], hideWatched: Bool = false) -> [MediaItem] {
        filteredLowestAgeRatingsIfNeeded(
            filteredForWatchedPreference(
                filteredForAnimePreference(
                    prioritisedForLanguage(items.filter(\.shouldShowInDiscovery))
                ),
                hideWatched: hideWatched
            )
        )
    }

    func clearSearchFilters() {
        selectedRuntimeFilters.removeAll()
        selectedDateFilters.removeAll()
        minimumTMDbRatingFilter = nil
        refreshRuntimeFilteredSearchIfNeeded()
    }
}
