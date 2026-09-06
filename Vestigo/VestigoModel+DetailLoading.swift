import SwiftUI
import Foundation

extension VestigoModel {

    func loadBasicDetailIfNeeded(_ item: MediaItem) async {
        guard detailsCache[item.key] == nil else { return }
        do {
            detailsCache[item.key] = try await tmdb.detail(for: item, regionCode: settings.streamingRegion.rawValue)
        } catch { }
    }

    func filterShorts(from trailers: [TrailerVideo]) async -> [TrailerVideo] {
        guard !trailers.isEmpty else { return trailers }
        let shortKeys = await withTaskGroup(of: String?.self, returning: Set<String>.self) { group in
            for trailer in trailers {
                group.addTask { await Self.isYouTubeShort(trailer.key) ? trailer.key : nil }
            }
            var keys = Set<String>()
            for await key in group { if let key { keys.insert(key) } }
            return keys
        }
        return shortKeys.isEmpty ? trailers : trailers.filter { !shortKeys.contains($0.key) }
    }

    static func isYouTubeShort(_ key: String) async -> Bool {
        guard let url = URL(string: "https://www.youtube.com/youtubei/v1/player?key=AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("com.google.android.youtube/17.31.35 (Linux; U; Android 11) gzip", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 5
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "videoId": key,
            "context": ["client": ["clientName": "ANDROID", "clientVersion": "17.31.35", "androidSdkVersion": 30]]
        ])
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        // Canonical URL is definitive — YouTube sets /shorts/ for Shorts, /watch?v= for everything else
        if let microformat = json["microformat"] as? [String: Any],
           let renderer = microformat["playerMicroformatRenderer"] as? [String: Any],
           let canonical = renderer["urlCanonical"] as? String {
            return canonical.contains("/shorts/")
        }
        // Fallback: actual video format dimensions
        if let streamingData = json["streamingData"] as? [String: Any],
           let formats = streamingData["adaptiveFormats"] as? [[String: Any]] {
            for fmt in formats {
                guard let mime = fmt["mimeType"] as? String, mime.hasPrefix("video/"),
                      let w = fmt["width"] as? Int, let h = fmt["height"] as? Int, w > 0 else { continue }
                return h > w
            }
        }
        return false
    }

    func loadDetail(_ item: MediaItem) async {
        if detailsCache[item.key] == nil {
            do {
                detailsCache[item.key] = try await tmdb.detail(for: item, regionCode: settings.streamingRegion.rawValue)
                if let detail = detailsCache[item.key], !detail.trailers.isEmpty {
                    let filtered = await filterShorts(from: detail.trailers)
                    if filtered.count != detail.trailers.count {
                        detailsCache[item.key] = detail.withTrailers(filtered)
                    }
                }
            } catch { }
        }
        if item.kind == .movie, let detail = detailsCache[item.key], let collectionID = detail.tmdbCollectionID {
            do {
                let collectionItems = try await backend.tmdbCollectionRecommendations(collectionID: collectionID)
                detailsCache[item.key] = detail.addingSimilarCandidates(
                    collectionItems,
                    source: item,
                    sameFranchiseKeys: Set(collectionItems.map(\.key)),
                    externalRatings: externalRatingsCache
                )
            } catch { }
        }
        if let detail = detailsCache[item.key] {
            do {
                let franchiseItems = try await franchiseRecommendationCandidates(for: item)
                detailsCache[item.key] = detail.addingSimilarCandidates(
                    franchiseItems,
                    source: item,
                    sameFranchiseKeys: Set(franchiseItems.map(\.key)),
                    externalRatings: externalRatingsCache
                )
            } catch { }
        }
        if let detail = detailsCache[item.key], let imdbID = detail.imdbID {
            do {
                let franchiseMembers = try await relatedMedia.franchiseMembers(imdbID: imdbID)
                let franchiseKeys = Set(franchiseMembers.map(\.mediaKey))
                if !franchiseKeys.isEmpty {
                    let franchiseItems = try await tmdb.items(for: Array(franchiseKeys))
                    if let latestDetail = detailsCache[item.key] {
                        detailsCache[item.key] = latestDetail.addingSimilarCandidates(
                            franchiseItems,
                            source: item,
                            sameFranchiseKeys: franchiseKeys,
                            externalRatings: externalRatingsCache
                        )
                    }
                }
            } catch { }
        }
        await loadExternalRatings(item, priority: true)
        if providerCache[item.key] == nil {
            do {
                let pricedProviders = try await streaming.providers(for: item, imdbID: detailsCache[item.key]?.imdbID, regionCode: settings.streamingRegion.rawValue)
                if pricedProviders.isEmpty, let tmdbProviders = detailsCache[item.key]?.tmdbProviders, !tmdbProviders.isEmpty {
                    providerCache[item.key] = tmdbProviders
                    tmdbFallbackKeys.insert(item.key)
                    scheduleWatchmodeRetryIfNeeded(item)
                } else {
                    providerCache[item.key] = pricedProviders
                }
            } catch {
                let fallback = detailsCache[item.key]?.tmdbProviders ?? []
                providerCache[item.key] = fallback
                if !fallback.isEmpty {
                    tmdbFallbackKeys.insert(item.key)
                    scheduleWatchmodeRetryIfNeeded(item)
                }
            }
        }
        if relatedMediaCache[item.key] == nil {
            if let imdbID = detailsCache[item.key]?.imdbID {
                do {
                    relatedMediaCache[item.key] = try await relatedMedia.sections(imdbID: imdbID)
                } catch {
                    relatedMediaCache[item.key] = []
                }
            } else {
                relatedMediaCache[item.key] = []
            }
        }
    }

    func scheduleWatchmodeRetryIfNeeded(_ item: MediaItem) {
        guard !watchmodeBackgroundRetried.contains(item.key) else { return }
        watchmodeBackgroundRetried.insert(item.key)
        Task {
            do {
                let pricedProviders = try await streaming.providers(for: item, imdbID: detailsCache[item.key]?.imdbID, regionCode: settings.streamingRegion.rawValue)
                if !pricedProviders.isEmpty {
                    providerCache[item.key] = pricedProviders
                    tmdbFallbackKeys.remove(item.key)
                }
            } catch { }
        }
    }

    func loadProvidersForWatchlistItems() {
        let uncached = library.watchlistItems.filter { providerCache[$0.key] == nil }
        guard !uncached.isEmpty else { return }
        Task {
            for item in uncached {
                guard providerCache[item.key] == nil else { continue }
                do {
                    let providers = try await streaming.providers(for: item, imdbID: detailsCache[item.key]?.imdbID, regionCode: settings.streamingRegion.rawValue)
                    await MainActor.run {
                        if providers.isEmpty, let tmdb = detailsCache[item.key]?.tmdbProviders, !tmdb.isEmpty {
                            providerCache[item.key] = tmdb
                            tmdbFallbackKeys.insert(item.key)
                        } else {
                            providerCache[item.key] = providers
                        }
                    }
                } catch {
                    // Leave providerCache[item.key] as nil on error so the filter shows the item by default
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }

    func universalMoreLikeThis(for item: MediaItem, hideWatched: Bool, limit: Int) async -> [MediaItem] {
        await loadBasicDetailIfNeeded(item)
        guard let detail = detailsCache[item.key] else {
            return []
        }

        var candidates = detail.similar
        var sameFranchiseKeys = detail.sameFranchiseKeys
        let strongKeys = detail.strongAPISimilarityKeys
        let mediumKeys = detail.mediumAPISimilarityKeys

        if item.kind == .movie {
            let collectionItems: [MediaItem]
            do {
                if let collectionID = detail.tmdbCollectionID {
                    collectionItems = try await backend.tmdbCollectionRecommendations(collectionID: collectionID)
                } else {
                    collectionItems = []
                }

                candidates.append(contentsOf: collectionItems)
                sameFranchiseKeys.formUnion(collectionItems.map(\.key))
            } catch { }
        }

        do {
            let franchiseItems = try await franchiseRecommendationCandidates(for: item)
            candidates.append(contentsOf: franchiseItems)
            sameFranchiseKeys.formUnion(franchiseItems.map(\.key))
        } catch { }

        if let imdbID = detail.imdbID {
            do {
                let franchiseKeys = Set(try await relatedMedia.franchiseMembers(imdbID: imdbID).map(\.mediaKey))
                if !franchiseKeys.isEmpty {
                    sameFranchiseKeys.formUnion(franchiseKeys)
                    candidates.append(contentsOf: try await tmdb.items(for: Array(franchiseKeys)))
                }
            } catch { }
        }

        let ranked = MediaDetail.rankedSimilarItems(
            candidates
                .uniqued()
                .filter { candidate in
                    candidate.shouldShowInDiscovery &&
                    !candidate.isUpcoming &&
                    candidate.key != item.key &&
                    !library.isNeverShowAgain(candidate.key) &&
                    (!hideWatched || !library.isWatched(candidate.key)) &&
                    (!settings.prioritiseEnglish || (candidate.originalLanguage ?? "en") == "en")
                },
            source: item,
            sameFranchiseKeys: sameFranchiseKeys,
            strongAPISimilarityKeys: strongKeys,
            mediumAPISimilarityKeys: mediumKeys,
            externalRatings: externalRatingsCache
        )

        return Array(ranked.prefix(limit))
    }

    func expandedTMDbSimilarCandidates(for item: MediaItem, detail: MediaDetail) async throws -> [MediaItem] {
        if let cached = tmdbExpandedSimilarCache[item.key] {
            return cached
        }

        let candidates = try await tmdb.keywordDiscoveryCandidates(for: item, keywordIDs: detail.keywordIDs)
            .uniqued()
            .filter { $0.shouldShowInDiscovery && !$0.isUpcoming && $0.key != item.key }
        tmdbExpandedSimilarCache[item.key] = candidates
        return candidates
    }

    func franchiseRecommendationCandidates(for item: MediaItem) async throws -> [MediaItem] {
        if let cached = franchiseRecommendationCache[item.key] {
            return cached
        }

        let uniqueCandidates = try await backend.exactFranchiseRecommendations(
            id: "\(item.kind.rawValue)-\(item.id)",
            matching: item.title
        )
        .uniqued()
        .filter { $0.shouldShowInDiscovery && !$0.isUpcoming && $0.key != item.key }
        franchiseRecommendationCache[item.key] = uniqueCandidates
        return uniqueCandidates
    }

    /*
    TasteDive recommendation expansion is intentionally disabled.

    The active More Like This system now uses TMDb recommendations/similar results plus exact
    provider-backed franchise membership. Leaving this code commented keeps the old integration
    available for future evaluation without querying or crediting an unused recommendation source.

    private func tasteDiveCandidates(for item: MediaItem) async throws -> [MediaItem] {
        if let cached = tasteDiveSimilarCache[item.key] {
            return cached
        }

        let names = try await tasteDive.similarTitles(for: item.title, kind: item.kind)
        var resolved: [MediaItem] = []
        let filter: MediaFilter = item.kind == .tv ? .tv : .movie
        let tmdb = self.tmdb

        try await withThrowingTaskGroup(of: MediaItem?.self) { group in
            for name in names.prefix(12) {
                group.addTask {
                    let results = try await tmdb.search(query: name, filter: filter)
                    return Self.bestTasteDiveMatch(named: name, from: results, matching: item.kind)
                }
            }

            for try await item in group {
                if let item, item.shouldShowInDiscovery {
                    resolved.append(item)
                }
            }
        }

        let candidates = resolved.uniqued().filter { $0.key != item.key }
        tasteDiveSimilarCache[item.key] = candidates
        return candidates
    }

    private nonisolated static func bestTasteDiveMatch(named title: String, from results: [MediaItem], matching kind: MediaKind) -> MediaItem? {
        let normalizedTitle = normalizedTasteDiveMatchTitle(title)
        return results
            .filter { item in
                item.kind == kind
                && item.voteAverage > 0
                && item.releaseDate.flatMap { Int($0.prefix(4)) } != nil
                && !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            .sorted { lhs, rhs in
                let lhsScore = tasteDiveMatchScore(lhs.title, normalizedTitle: normalizedTitle)
                let rhsScore = tasteDiveMatchScore(rhs.title, normalizedTitle: normalizedTitle)
                if lhsScore != rhsScore {
                    return lhsScore > rhsScore
                }
                return lhs.voteAverage > rhs.voteAverage
            }
            .first
    }

    private nonisolated static func normalizedTasteDiveMatchTitle(_ title: String) -> String {
        title
            .lowercased()
            .replacingOccurrences(of: "&", with: "and")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private nonisolated static func tasteDiveMatchScore(_ title: String, normalizedTitle: String) -> Int {
        let normalized = normalizedTasteDiveMatchTitle(title)
        if normalized == normalizedTitle { return 100 }
        if normalized.contains(normalizedTitle) { return 75 }
        if normalizedTitle.contains(normalized) { return 60 }
        return 0
    }
    */

    func loadExternalRatings(_ item: MediaItem, priority: Bool = false) async {
        guard settings.preferredRatingSource == .imdb else { return }
        guard item.kind == .movie || item.kind == .tv else { return }
        guard externalRatingsCache[item.key] == nil else { return }
        guard !externalRatingInFlight.contains(item.key) else { return }

        let primaryKey = settings.omdbPrimaryKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let backupKey = settings.omdbBackupKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !primaryKey.isEmpty || !backupKey.isEmpty else {
            externalRatingsCache[item.key] = .empty
            saveLocalSoon()
            return
        }

        externalRatingInFlight.insert(item.key)
        defer { externalRatingInFlight.remove(item.key) }

        do {
            if let ratings = try await backend.ratings(for: item, primaryKey: primaryKey, backupKey: backupKey), ratings.hasAnyRating {
                externalRatingsCache[item.key] = ratings
            } else {
                externalRatingsCache[item.key] = .empty
            }
            incrementOMDbDailyCount()
            saveLocalSoon()
        } catch {
            print("IMDb ratings failed for \(item.title): \(error.localizedDescription)")
            externalRatingsCache[item.key] = .empty
            saveLocalSoon()
        }
    }

    func incrementOMDbDailyCount() {
        let today = ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: Date()))
        if settings.omdbLastRequestDate != today {
            settings.omdbDailyRequestCount = 0
            settings.omdbLastRequestDate = today
        }
        settings.omdbDailyRequestCount += 1
        settings.omdbTotalRequestCount += 1
        if settings.omdbDailyRequestCount >= settings.omdbTierLimit {
            showOMDbLimitAlert = true
        }
    }

    func clearHomeFeedCache() {
        for filter in MediaFilter.allCases {
            UserDefaults.standard.removeObject(forKey: "Vestigo.homeFeedCaches.\(filter.rawValue)")
        }
    }

    func clearDescribeItCache() {
        describeItResultsCache = [:]
        saveLocalSoon()
    }

    func clearAllCaches() {
        detailsCache = [:]
        providerCache = [:]
        tmdbFallbackKeys = []
        Storage.save([MediaKey: [StreamingOption]](), key: "Vestigo.providerCache")
        relatedMediaCache = [:]
        personCreditsCache = [:]
        personDetails = [:]
        collectionRecommendations = [:]
        tmdbExpandedSimilarCache = [:]
        franchiseRecommendationCache = [:]
        describeItResultsCache = [:]
        pickForMeThematicCache = [:]
        clearHomeFeedCache()
    }

    func resetOMDbCounters() {
        settings.omdbDailyRequestCount = 0
        settings.omdbTotalRequestCount = 0
        settings.omdbLastRequestDate = ""
    }

    @discardableResult
    func forceICloudPush() -> String {
        Storage.saveKVSnapshot(library: library, settings: settings)
        return "Pushed at \(Date().formatted(date: .omitted, time: .standard))"
    }

    func simulateFirstLaunch() {
        showStreamingSetup = true
    }

    func loadExternalRatings(for items: [MediaItem], limit: Int = 80) async {
        let cappedLimit = min(limit, externalRatingBatchLimit)
        for item in items.prefix(cappedLimit) {
            await loadExternalRatings(item)
        }
    }

    func ratingDisplayText(for item: MediaItem) -> String {
        if settings.preferredRatingSource == .imdb {
            if let imdbRating = externalRatingsCache[item.key]?.imdbRating {
                return "IMDb \(imdbRating.formatted(.number.precision(.fractionLength(1))))"
            }
        }
        guard item.voteAverage > 0 else { return "" }
        return "TMDb \(item.voteAverage.formatted(.number.precision(.fractionLength(1))))"
    }

    func ratingSortValue(for item: MediaItem) -> Double {
        if settings.preferredRatingSource == .imdb,
           let imdbRating = externalRatingsCache[item.key]?.imdbRating {
            return imdbRating
        }
        guard item.voteAverage > 0 else { return 0 }
        // Don't trust a TMDb average backed by very few votes — it's statistically meaningless
        if let count = item.voteCount, count < 100 { return 0 }
        return item.voteAverage
    }

    func loadPersonDetailIfNeeded(_ person: PersonSummary) async {
        guard personDetails[person.id] == nil else { return }
        do {
            personDetails[person.id] = try await tmdb.personDetail(personID: person.id)
        } catch { }
    }

    func loadPersonCredits(_ person: PersonSummary) async {
        await loadPersonDetailIfNeeded(person)
        guard personCreditsCache[person.id] == nil else { return }
        do {
            personCreditsCache[person.id] = try await tmdb.personCredits(personID: person.id)
        } catch {
            personCreditsCache[person.id] = PersonCreditBundle(onScreen: [], behindCamera: [])
        }
    }

}
