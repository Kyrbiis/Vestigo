import SwiftUI
import Foundation

extension VestigoModel {

    func updateSearch() {
        searchTask?.cancel()
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestID = UUID()
        searchRequestID = requestID

        guard !query.isEmpty else {
            searchResults = []
            searchPeopleResults = []
            return
        }

        let cacheKey = normalizedSearchCacheKey(query, filter: searchFilter)
        if searchFilter == .people, let cachedPeople = peopleSearchCache[cacheKey] {
            searchPeopleResults = cachedPeople
            searchResults = []
        } else if searchFilter != .people, let cachedResults = mediaSearchCache[cacheKey] {
            searchResults = cachedResults
            searchPeopleResults = []
        } else if searchFilter != .people {
            searchResults = instantSearchRefinement(for: query)
            searchPeopleResults = []
        } else {
            searchPeopleResults = []
            searchResults = []
        }

        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard let self, !Task.isCancelled else { return }
            guard await MainActor.run(body: { self.searchRequestID == requestID }) else { return }

            do {
                if self.searchFilter == .people {
                    let people = try await tmdb.searchPeople(query: query, includeAdult: !self.settings.hideAdultResults)
                    await MainActor.run {
                        guard self.searchRequestID == requestID else { return }
                        self.peopleSearchCache[cacheKey] = people
                        self.searchPeopleResults = people
                        self.searchResults = []
                    }
                } else if let filter = self.searchFilter.mediaFilter {
                    let rankedVisibleResults = try await self.searchMediaResults(query: query, filter: filter)
                    await MainActor.run {
                        guard self.searchRequestID == requestID else { return }
                        self.mediaSearchCache[cacheKey] = rankedVisibleResults
                        self.searchResults = rankedVisibleResults
                        self.searchPeopleResults = []
                        self.cacheUpcomingItems(from: rankedVisibleResults)
                        self.refreshSearchRatingsIfCurrent(
                            rankedVisibleResults,
                            query: query,
                            requestID: requestID,
                            cacheKey: cacheKey
                        )
                    }
                }
            } catch {
                if LoadErrorFilter.shouldIgnore(error) {
                    return
                }
                await MainActor.run { self.errorText = error.localizedDescription }
            }
        }
    }

    func refreshSearch() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestID = UUID()
        searchRequestID = requestID

        guard !query.isEmpty else {
            searchResults = []
            searchPeopleResults = []
            return
        }

        searchTask?.cancel()

        do {
            let cacheKey = normalizedSearchCacheKey(query, filter: searchFilter)
            if searchFilter == .people {
                let people = try await tmdb.searchPeople(query: query, includeAdult: !settings.hideAdultResults)
                guard searchRequestID == requestID else { return }
                peopleSearchCache[cacheKey] = people
                searchPeopleResults = people
                searchResults = []
            } else if let filter = searchFilter.mediaFilter {
                let results = try await searchMediaResults(query: query, filter: filter)
                guard searchRequestID == requestID else { return }
                mediaSearchCache[cacheKey] = results
                searchResults = results
                searchPeopleResults = []
                cacheUpcomingItems(from: results)
                refreshSearchRatingsIfCurrent(
                    results,
                    query: query,
                    requestID: requestID,
                    cacheKey: cacheKey
                )
            }
        } catch {
            if LoadErrorFilter.shouldIgnore(error) {
                return
            }
            errorText = error.localizedDescription
        }
    }

    func quickSearch(query: String) async -> [MediaItem] {
        guard !query.isEmpty else { return [] }
        return (try? await searchMediaResults(query: query, filter: .both)) ?? []
    }

    func cacheUpcomingItems(from results: [MediaItem]) {
        let today = Calendar.current.startOfDay(for: Date())
        let existingIDs = Set(upcoming.map { $0.key.stableID })
        let newItems = results.filter { item in
            !existingIDs.contains(item.key.stableID) &&
            (item.releaseDateValue.map { $0 > today } ?? false)
        }
        if !newItems.isEmpty { upcoming.append(contentsOf: newItems) }
    }

    func searchMediaResults(query: String, filter: MediaFilter) async throws -> [MediaItem] {
        let searchQueries = fuzzySearchQueries(from: query)
        var collectedResults: [MediaItem] = []

        for searchQuery in searchQueries {
            collectedResults.append(contentsOf: try await tmdb.search(query: searchQuery, filter: filter, includeAdult: !settings.hideAdultResults))
        }

        if collectedResults.isEmpty {
            collectedResults.append(contentsOf: try await tmdb.contextualSearch(query: query, filter: filter, includeAdult: !settings.hideAdultResults))
        }

        let baseResults = preparedResults(
            collectedResults
                .uniqued()
                .sorted { lhs, rhs in
                    let lhsScore = fuzzySearchRelevanceScore(item: lhs, query: query)
                    let rhsScore = fuzzySearchRelevanceScore(item: rhs, query: query)

                    if lhsScore != rhsScore {
                        return lhsScore > rhsScore
                    }

                    return (lhs.releaseDateValue ?? .distantPast) > (rhs.releaseDateValue ?? .distantPast)
                },
            hideWatched: settings.hideWatchedFromSearch
        )

        let enrichedResults: [MediaItem]
        if !selectedRuntimeFilters.isEmpty {
            enrichedResults = await enrichSearchResultsWithRuntimeIfNeeded(baseResults)
        } else {
            enrichedResults = baseResults
        }

        let visibleResults = await filteredContentCleanupIfNeeded(
            enrichedResults,
            hideShortFilms: settings.hideShortFilmsFromSearch,
            hideExtrasAndPromos: settings.hideExtrasAndPromosFromSearch
        )

        return finalizedSearchResults(visibleResults, query: query)
    }

    func finalizedSearchResults(_ items: [MediaItem], query: String) -> [MediaItem] {
        let ratingFilteredResults = items.filter { item in
            guard let minimumTMDbRatingFilter else { return true }
            return ratingSortValue(for: item) >= minimumTMDbRatingFilter.minimumRating
        }

        return ratingFilteredResults.sorted { lhs, rhs in
            let lhsScore = fuzzySearchRelevanceScore(item: lhs, query: query)
            let rhsScore = fuzzySearchRelevanceScore(item: rhs, query: query)

            if lhsScore != rhsScore {
                return lhsScore > rhsScore
            }

            let lhsRating = ratingSortValue(for: lhs)
            let rhsRating = ratingSortValue(for: rhs)
            if lhsRating != rhsRating {
                return lhsRating > rhsRating
            }

            return (lhs.releaseDateValue ?? .distantPast) > (rhs.releaseDateValue ?? .distantPast)
        }
    }

    func refreshSearchRatingsIfCurrent(_ items: [MediaItem], query: String, requestID: UUID, cacheKey: String) {
        Task { [weak self] in
            guard let self else { return }
            await self.loadExternalRatings(for: items, limit: 24)
            guard self.searchRequestID == requestID else { return }
            guard self.normalizedSearchCacheKey(query, filter: self.searchFilter) == cacheKey else { return }

            let updatedResults = self.finalizedSearchResults(items, query: query)
            self.mediaSearchCache[cacheKey] = updatedResults
            self.searchResults = updatedResults
        }
    }

    func instantSearchRefinement(for query: String) -> [MediaItem] {
        let normalizedQuery = normalizedSearchText(query)
        let queryTokens = normalizedQuery
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count >= 2 && $0 != "the" }

        guard !normalizedQuery.isEmpty, !searchResults.isEmpty else { return [] }

        let refined = searchResults.filter { item in
            let title = normalizedSearchText(item.title)
            let overview = normalizedSearchText(item.overview)

            if title.contains(normalizedQuery) {
                return true
            }

            guard !queryTokens.isEmpty else { return false }
            return queryTokens.allSatisfy { token in
                title.contains(token) || overview.contains(token)
            }
        }

        return finalizedSearchResults(refined, query: query)
    }

    func fuzzySearchQueries(from rawQuery: String) -> [String] {
        let normalized = rawQuery
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }

        var queries: [String] = [rawQuery]

        let meaningfulTokens = normalized.filter { token in
            token.count >= 3 && !["the", "and", "for", "with", "from", "into", "onto", "part"].contains(token)
        }

        if meaningfulTokens.count >= 2 {
            queries.append(meaningfulTokens.joined(separator: " "))
        }

        if let longest = meaningfulTokens.max(by: { $0.count < $1.count }), longest.count >= 4 {
            queries.append(longest)
        }

        if meaningfulTokens.count >= 3 {
            queries.append(meaningfulTokens.prefix(3).joined(separator: " "))
        }

        var seen = Set<String>()
        return queries.filter { query in
            seen.insert(query).inserted
        }
    }

    func fuzzySearchRelevanceScore(item: MediaItem, query: String) -> Int {
        let normalizedQuery = normalizedSearchText(query)
        let queryTokens = normalizedQuery
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count >= 2 }

        guard !queryTokens.isEmpty else { return 0 }

        let title = normalizedSearchText(item.title)
        let overview = normalizedSearchText(item.overview)
        var score = 0

        let continuationScore = searchTitleContinuationScore(title: title, query: normalizedQuery)
        if title == normalizedQuery {
            score += 17_000
            if let year = item.releaseYearNumber {
                if year >= 1995 {
                    score += 1_800
                } else if year < 1990 {
                    score -= 1_500
                }
            }
        } else if continuationScore > 0 {
            score += continuationScore
        } else if title.contains(" " + normalizedQuery + " ") || title.hasSuffix(" " + normalizedQuery) {
            score += 3_000
        }

        if title.contains(normalizedQuery) {
            score += 1_400
        }

        if settings.prioritiseEnglish {
            if item.originalLanguage == nil || item.originalLanguage == "en" {
                score += title == normalizedQuery ? 600 : 1_800
            } else if title != normalizedQuery {
                score -= 2_500
            }
        }

        score += Int(item.voteAverage * 120)
        if let year = item.releaseYearNumber, year >= 1990 {
            score += min((year - 1990) * 6, 300)
        }

        for token in queryTokens {
            if title.contains(token) {
                score += 60
            } else if overview.contains(token) {
                score += 6
            }
        }

        let titleTokens = title
            .split(separator: " ")
            .map(String.init)

        for queryToken in queryTokens where queryToken.count >= 4 {
            if titleTokens.contains(where: { titleToken in
                titleToken.hasPrefix(queryToken)
                || queryToken.hasPrefix(titleToken)
                || levenshteinDistance(queryToken, titleToken) <= 1
            }) {
                score += 14
            }
        }

        return score
    }

    func searchTitleContinuationScore(title: String, query: String) -> Int {
        guard title.hasPrefix(query + " ") else { return 0 }
        let suffix = title.dropFirst(query.count).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !suffix.isEmpty else { return 0 }
        let firstToken = suffix.split(separator: " ").first.map(String.init) ?? ""

        if isOrdinalContinuationToken(firstToken) {
            return 18_000
        }

        if suffix.hasPrefix("part ") || suffix.hasPrefix("chapter ") || suffix.hasPrefix("vol ") || suffix.hasPrefix("volume ") {
            return 16_500
        }

        if suffix.contains("animated") || suffix.contains("adventures") || suffix.contains("series") || suffix.contains("legacy") {
            return 12_500
        }

        return 8_000
    }

    func isOrdinalContinuationToken(_ token: String) -> Bool {
        if let number = Int(token), number > 1 {
            return true
        }

        guard token.range(of: #"^[ivxlcdm]+$"#, options: .regularExpression) != nil else {
            return false
        }

        var previous = 0
        var total = 0

        for character in token.reversed() {
            let value: Int
            switch character {
            case "i": value = 1
            case "v": value = 5
            case "x": value = 10
            case "l": value = 50
            case "c": value = 100
            case "d": value = 500
            case "m": value = 1000
            default: return false
            }

            if value < previous {
                total -= value
            } else {
                total += value
                previous = value
            }
        }

        return total > 1
    }

    func normalizedSearchText(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .split(separator: " ")
            .joined(separator: " ")
    }

    func normalizedSearchCacheKey(_ query: String, filter: SearchFilter) -> String {
        let minimumRatingKey = minimumTMDbRatingFilter.map { String($0.rawValue) } ?? "none"
        return "\(filter.rawValue)|\(normalizedSearchText(query))|\(settings.prioritiseEnglish)|\(settings.hideAdultResults)|\(settings.hideWatchedFromSearch)|\(settings.hideLowestAgeRatings)|\(minimumRatingKey)|\(selectedRuntimeFilters.map(\.rawValue).sorted().joined(separator: ","))|\(settings.hideShortFilmsFromSearch)|\(settings.hideExtrasAndPromosFromSearch)"
    }

    func levenshteinDistance(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)

        if aChars.isEmpty { return bChars.count }
        if bChars.isEmpty { return aChars.count }

        var previous = Array(0...bChars.count)
        var current = Array(repeating: 0, count: bChars.count + 1)

        for i in 1...aChars.count {
            current[0] = i

            for j in 1...bChars.count {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                current[j] = min(
                    previous[j] + 1,
                    current[j - 1] + 1,
                    previous[j - 1] + cost
                )
            }

            previous = current
        }

        return previous[bChars.count]
    }

    func refreshRuntimeFilteredSearchIfNeeded() {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard searchFilter != .people else { return }
        guard !selectedRuntimeFilters.isEmpty else { return }

        updateSearch()
    }

    func enrichSearchResultsWithRuntimeIfNeeded(_ items: [MediaItem]) async -> [MediaItem] {
        var enriched: [MediaItem] = []
        enriched.reserveCapacity(items.count)

        for item in items {
            guard item.kind == .movie, item.runtime == nil else {
                enriched.append(item)
                continue
            }

            do {
                let detail = try await tmdb.detail(for: item, regionCode: settings.streamingRegion.rawValue)
                detailsCache[item.key] = detail
                enriched.append(item.withRuntime(detail.runtime))
            } catch {
                enriched.append(item)
            }
        }

        return enriched
    }

    func loadGenre(_ genre: GenreDefinition, filter: MediaFilter = .both, sort: GenreSort = .tmdbRating, forceRefresh: Bool = false) async {
        let cacheKey = genreCacheKey(genreID: genre.tmdbID, filter: filter, sort: sort)
        if !forceRefresh, genreResults[cacheKey]?.isEmpty == false {
            return
        }

        do {
            let items = try await tmdb.discover(
                genreID: genre.tmdbID,
                filter: filter,
                sort: sort
            )

            let preparedItems = preparedResults(items, hideWatched: settings.hideWatchedFromSearch)
            let visibleItems = await filteredContentCleanupIfNeeded(preparedItems, hideShortFilms: settings.hideShortFilmsFromSearch, hideExtrasAndPromos: settings.hideExtrasAndPromosFromSearch)
            let fastSortedItems = sort == .tmdbRating
                ? visibleItems.sorted { lhs, rhs in
                    let lhsRating = lhs.voteAverage
                    let rhsRating = rhs.voteAverage
                    if lhsRating != rhsRating {
                        return lhsRating > rhsRating
                    }

                    return (lhs.releaseDateValue ?? .distantPast) > (rhs.releaseDateValue ?? .distantPast)
                }
                : visibleItems

            await MainActor.run {
                genreResults[cacheKey] = fastSortedItems
            }

            await loadExternalRatings(for: Array(visibleItems.prefix(12)), limit: 12)

            let finalSortedItems = sort == .tmdbRating
                ? visibleItems.sorted { lhs, rhs in
                    let lhsRating = ratingSortValue(for: lhs)
                    let rhsRating = ratingSortValue(for: rhs)
                    if lhsRating != rhsRating {
                        return lhsRating > rhsRating
                    }

                    return (lhs.releaseDateValue ?? .distantPast) > (rhs.releaseDateValue ?? .distantPast)
                }
                : visibleItems

            await MainActor.run {
                genreResults[cacheKey] = finalSortedItems
            }
        } catch {
            await MainActor.run {
                if genreResults[cacheKey] == nil {
                    genreResults[cacheKey] = []
                }
            }
        }
    }

    func genreCacheKey(genreID: Int, filter: MediaFilter = .both, sort: GenreSort = .tmdbRating) -> String {
        "\(genreID)-category-\(filter.rawValue)-\(sort.rawValue)"
    }

}
