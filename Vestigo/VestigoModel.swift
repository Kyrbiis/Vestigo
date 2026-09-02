import SwiftUI
import Foundation
import Combine
#if canImport(FoundationModels)
import FoundationModels
#endif

struct PendingFriendAdd {
    let id: String
    let name: String
}

@MainActor
final class VestigoModel: ObservableObject {
    @Published var selectedTab: AppTab = .home
    @Published var tabTransitionDirection: TabTransitionDirection = .forward
    @Published var mediaFilter: MediaFilter = .both
    @Published var homeViewMode: ViewMode = .tile
    @Published var searchViewMode: ViewMode = .tile
    @Published var watchlistViewMode: ViewMode = .tile
    @Published var collectionViewMode: ViewMode = .tile
    @Published var sortOption: SortOption = .tmdbRating
    @Published var sortDirection: SortDirection = .descending

    @Published var searchFiltersExpanded = false
    @Published var expandedSearchFilterSections: Set<SearchFilterSection> = []
    @Published var selectedRuntimeFilters: Set<SearchRuntimeFilter> = []
    @Published var selectedDateFilters: Set<SearchDateFilter> = []
    @Published var minimumTMDbRatingFilter: SearchRatingFilter?
    @Published var searchText = ""
    @Published var searchFilter: SearchFilter = .all
    @Published var searchFieldIsFocused = false
    @Published var trending: [MediaItem] = []
    @Published var popular: [MediaItem] = []
    @Published var newReleases: [MediaItem] = []
    @Published var upcoming: [MediaItem] = []
    @Published var topRatedMovies: [MediaItem] = []
    @Published var topRatedShows: [MediaItem] = []
    @Published var recommendations: [MediaItem] = []
    @Published var moreLikeLastWatched: [MediaItem] = []
    @Published var moreLikeFavourite: [MediaItem] = []
    @Published var fromTopGenre: [MediaItem] = []
    @Published var trySomethingNewRecommendations: [MediaItem] = []
    @Published var seriesNext: [MediaItem] = []
    @Published var searchResults: [MediaItem] = []
    @Published var searchPeopleResults: [PersonSummary] = []
    @Published var genreResults: [String: [MediaItem]] = [:]
    @Published var detailsCache: [MediaKey: MediaDetail] = [:]
    @Published var externalRatingsCache: [MediaKey: ExternalRatings] = [:]
    @Published var providerCache: [MediaKey: [StreamingOption]] = [:]
    @Published var tmdbFallbackKeys: Set<MediaKey> = []
    private var watchmodeBackgroundRetried: Set<MediaKey> = []
    var describeItResultsCache: [String: [ThematicSearchResult]] = [:]

    @Published var relatedMediaCache: [MediaKey: [RelatedMediaSection]] = [:]
    @Published var personCreditsCache: [Int: PersonCreditBundle] = [:]
    @Published var personDetails: [Int: PersonDetail] = [:]
    private var archetypeInferenceCache: [MediaKey: ArchetypeInference] = [:]
    @Published var collectionRecommendations: [UUID: [MediaItem]] = [:]
    @Published var pendingRatingPromptItem: MediaItem?
    @Published var pendingRatingPromptValue: Double = 0
    @Published var pendingRatingPromptMakeFavourite = false
    @Published var pendingRatingPromptRestoreWatchlist = false
    
    @Published var library = UserLibrary()
    @Published var settings = AppSettings()
    @Published var selectedItem: MediaItem? {
        didSet { if let item = selectedItem { recordRecentlyViewed(item) } }
    }
    @Published var selectedPerson: PersonSummary?
    @Published var homePath: [HomeRoute] = []
    @Published var searchPath: [SearchRoute] = []
    @Published var isLoading = false
    @Published var errorText: String?
    @Published var exportDocument = ExportDocument(text: "")
    @Published var exportFormat: ExportFormat = .text
    @Published var showExporter = false
    @Published var pendingFavouriteReplacement: MediaItem?
    @Published var showFavouriteReplacementAlert = false
    @Published var friendDetailContext: FriendProfile? = nil
    @Published var friendsResetToken = UUID()
    @Published var watchlistResetToken = UUID()
    @Published var collectionsResetToken = UUID()
    @Published var imageRefreshToken = 0
    @Published var showStreamingSetup = false
    @Published var calendarEventIDs: [MediaKey: String] = [:]
    @Published var showOMDbLimitAlert = false
    @Published var friends: [FriendProfile] = []
    @Published var friendsLoading = false
    @Published var friendsDiagnostic: String = ""
    @Published var publishDiagnostic: String = ""
    @Published var pendingFriendAdd: PendingFriendAdd? = nil
    @Published var userAvatarData: Data? = nil

    var myInviteURL: String { "vestigo://friend?id=\(settings.socialInviteID)" }


    struct HomeSectionLoadResult {
        let section: HomeSectionKind
        let items: [MediaItem]
        let errorText: String?
    }

    
    private let tmdb = TMDbService()
    // TasteDive is intentionally disabled because the current recommendation system no longer calls it.
    // Keep this wiring nearby in case we decide to re-evaluate TasteDive as a future supplemental source.
    // private let tasteDive = TasteDiveService()
    private let streaming = StreamingAvailabilityService()
    private let relatedMedia = RelatedMediaService()
    private let backend = VestigoBackendClient()
    private let releaseCalendar = ReleaseCalendarService()
    private let publicSync = CloudPublicSyncService()
    private let externalRatingBatchLimit = 8
    private var externalRatingEmptyRefreshes: Set<MediaKey> = []
    private var externalRatingInFlight: Set<MediaKey> = []
    private var searchTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var recommendationsRefreshTask: Task<Void, Never>?
    private var publishTask: Task<Void, Never>?
    private var searchRequestID = UUID()
    private var isApplyingCloudSnapshot = false
    private var mediaSearchCache: [String: [MediaItem]] = [:]
    private var peopleSearchCache: [String: [PersonSummary]] = [:]
    // Disabled with TasteDiveService; no active path should credit or query TasteDive right now.
    // private var tasteDiveSimilarCache: [MediaKey: [MediaItem]] = [:]
    private var tmdbExpandedSimilarCache: [MediaKey: [MediaItem]] = [:]
    private var franchiseRecommendationCache: [MediaKey: [MediaItem]] = [:]
    private var pickForMeThematicCache: [String: [MediaItem]] = [:]

    // In-memory session state — survives tab switches but not app quit
    var pickForMeSessionAnswers: PickForMeAnswers? = nil
    var pickForMeSessionResults: [MediaItem] = []

    func refreshImages() {
        imageRefreshToken &+= 1
        URLCache.shared.removeAllCachedResponses()
        #if canImport(UIKit)
        ImageCache.shared.clear()
        #endif
    }
    
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

    private static func isLowestAgeRating(_ rawRating: String) -> Bool {
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
    
    func bootstrap() async {
        URLCache.shared = URLCache(
            memoryCapacity: 50 * 1024 * 1024,
            diskCapacity: 300 * 1024 * 1024
        )

        loadLocal()
        loadUserAvatar()
        offerStreamingSetupIfNeeded()

        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleExternalKVChange() }
        }

        await loadHome()

        Task {
            await syncFromCloudOnLaunch()
            await loadHome()
        }
    }

    func clearExternalRatingsCache() {
        externalRatingsCache = [:]
        UserDefaults.standard.removeObject(forKey: "Vestigo.externalRatings")
    }

    func refreshVisibleExternalRatings() {
        guard settings.preferredRatingSource == .imdb else { return }
        guard !settings.omdbPrimaryKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        // Strip empty sentinel entries so the fetch guard doesn't skip them
        externalRatingsCache = externalRatingsCache.filter { $0.value.hasAnyRating }
        let visible = (trending + popular + newReleases + upcoming + recommendations
            + moreLikeLastWatched + moreLikeFavourite + fromTopGenre + seriesNext
            + trySomethingNewRecommendations + searchResults)
        Task { await loadExternalRatings(for: visible) }
    }

    func addReleaseToCalendar(_ item: MediaItem) {
        guard let releaseDate = item.releaseDateValue else {
            errorText = "No release date is available for this title."
            return
        }

        let previousID = calendarEventIDs[item.key]

        Task {
            do {
                let newID = try await releaseCalendar.addReleaseEvent(for: item, releaseDate: releaseDate, replacing: previousID)
                await MainActor.run {
                    if let newID {
                        self.calendarEventIDs[item.key] = newID
                    }
                    self.saveLocalSoon()
                }
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    func hasCalendarEvent(for item: MediaItem) -> Bool {
        calendarEventIDs[item.key] != nil
    }

    func loadHome() async {
        applyCachedHomeFeedIfAvailable()

        isLoading = true
        errorText = nil
        defer { isLoading = false }

        var loadErrors: [String] = []
        var refreshedSections: Set<HomeSectionKind> = []

        await withTaskGroup(of: HomeSectionLoadResult.self) { group in
            group.addTask { await self.loadHomeSection(.trending) }
            group.addTask { await self.loadHomeSection(.popular) }
            group.addTask { await self.loadHomeSection(.newReleases) }
            group.addTask { await self.loadHomeSection(.upcoming) }

            for await result in group {
                if let sectionError = result.errorText {
                    loadErrors.append(sectionError)
                    continue
                }

                guard !result.items.isEmpty else { continue }

                refreshedSections.insert(result.section)

                switch result.section {
                case .trending:
                    trending = result.items
                case .popular:
                    popular = result.items
                case .newReleases:
                    newReleases = result.items
                case .upcoming:
                    upcoming = result.items
                }

                refineHomeSection(result.section, items: result.items)
            }
        }

        if !refreshedSections.isEmpty {
            saveCurrentHomeFeedCache()
        }

        await loadSmartRecommendations()

        if trending.isEmpty,
           popular.isEmpty,
           newReleases.isEmpty,
           upcoming.isEmpty,
           let firstError = loadErrors.first {
            errorText = firstError
        }

        prefetchPosters(for: trending + popular + newReleases + recommendations + moreLikeLastWatched + moreLikeFavourite)
    }

    private func loadHomeSection(_ section: HomeSectionKind) async -> HomeSectionLoadResult {
        do {
            let loadedItems: [MediaItem]
            switch section {
            case .trending:
                loadedItems = try await tmdb.trending(filter: mediaFilter)
            case .popular:
                loadedItems = try await tmdb.popular(filter: mediaFilter)
            case .newReleases:
                loadedItems = try await tmdb.newReleases(filter: mediaFilter)
            case .upcoming:
                let items = try await tmdb.upcoming(filter: mediaFilter)
                let today = Calendar.current.startOfDay(for: Date())
                loadedItems = items.filter { item in
                    guard let releaseDate = item.releaseDateValue else { return false }
                    return releaseDate > today
                }
            }

            let prepared = preparedResults(loadedItems, hideWatched: settings.hideWatchedFromHome)
            let loaded = await filteredContentCleanupIfNeeded(
                prepared,
                hideShortFilms: settings.hideShortFilmsFromHome,
                hideExtrasAndPromos: settings.hideExtrasAndPromosFromHome,
                loadMissingDetails: false
            )

            return HomeSectionLoadResult(section: section, items: loaded, errorText: nil)
        } catch {
            if !LoadErrorFilter.shouldIgnore(error) {
                return HomeSectionLoadResult(section: section, items: [], errorText: error.localizedDescription)
            }
            return HomeSectionLoadResult(section: section, items: [], errorText: nil)
        }
    }

    private func applyCachedHomeFeedIfAvailable() {
        guard let cache = Storage.loadNewestHomeFeedCache(for: mediaFilter) else { return }

        if !cache.trending.isEmpty { trending = cache.trending }
        if !cache.popular.isEmpty { popular = cache.popular }
        if !cache.newReleases.isEmpty { newReleases = cache.newReleases }
        if !cache.upcoming.isEmpty { upcoming = cache.upcoming }
        if !cache.recommendations.isEmpty { recommendations = cache.recommendations }
    }

    private func saveCurrentHomeFeedCache() {
        let cache = HomeFeedCache(
            cachedAt: Date(),
            filter: mediaFilter,
            trending: trending,
            popular: popular,
            newReleases: newReleases,
            upcoming: upcoming,
            recommendations: recommendations
        )
        Storage.saveHomeFeedCache(cache)
    }

    private func refineHomeSection(_ section: HomeSectionKind, items: [MediaItem]) {
        guard settings.hideShortFilmsFromHome || settings.hideExtrasAndPromosFromHome || settings.hideLowestAgeRatings else { return }

        Task { [weak self] in
            guard let self else { return }
            let refinedItems = await self.filteredContentCleanupIfNeeded(
                items,
                hideShortFilms: self.settings.hideShortFilmsFromHome,
                hideExtrasAndPromos: self.settings.hideExtrasAndPromosFromHome,
                loadMissingDetails: true
            )

            guard refinedItems.map(\.key) != items.map(\.key) else { return }

            switch section {
            case .trending:
                self.trending = refinedItems
            case .popular:
                self.popular = refinedItems
            case .newReleases:
                self.newReleases = refinedItems
            case .upcoming:
                self.upcoming = refinedItems
            }

            self.saveCurrentHomeFeedCache()
        }
    }

    func refreshHome() async {
        await loadHome()
    }
    
    private func prefetchPosters(for items: [MediaItem]) {
        let urls = items.prefix(50).compactMap { $0.posterURL(displayWidth: 148) }
        Task.detached(priority: .utility) {
            await withTaskGroup(of: Void.self) { group in
                for url in urls {
                    group.addTask {
                        #if canImport(UIKit)
                        let already = await MainActor.run { ImageCache.shared[url] != nil }
                        guard !already else { return }
                        guard let (data, _) = try? await URLSession.shared.data(from: url),
                              let raw = UIImage(data: data) else { return }
                        let decoded = raw.preparingForDisplay() ?? raw
                        await MainActor.run { ImageCache.shared[url] = decoded }
                        #endif
                    }
                }
            }
        }
    }

    func loadSmartRecommendations() async {
        let watchedHistory = library.watchedItems
        guard watchedHistory.count >= 3 else {
            recommendations = []
            moreLikeLastWatched = []
            moreLikeFavourite = []
            fromTopGenre = []
            trySomethingNewRecommendations = []
            seriesNext = []
            return
        }
        
        let strength = min(max(settings.recommendationStrength, 1), 5)
        let normalizedStrength = (strength - 1) / 4
        // Lower values broaden recommendations; higher values lean harder on highly rated watched history.
        let unratedWatchedWeight = 0.65 - (normalizedStrength * 0.45)
        let ratingInfluence = 0.35 + (normalizedStrength * 0.65)
        let lowRatingPenaltyMultiplier = 0.15 + (normalizedStrength * 0.85)
        
        func historyWeight(for historyItem: MediaItem) -> Double {
            let rating = library.ratings[historyItem.key]
            
            if let rating {
                let centeredRating = (rating - 2.5) / 2.5
                if centeredRating >= 0 {
                    return 1.0 + centeredRating * ratingInfluence
                } else {
                    return centeredRating * lowRatingPenaltyMultiplier
                }
            } else {
                return unratedWatchedWeight
            }
        }
        
        func genreSimilarity(_ candidate: MediaItem, _ historyItem: MediaItem) -> Double {
            let candidateGenres = Set(candidate.genreIDs)
            let historyGenres = Set(historyItem.genreIDs)
            guard !candidateGenres.isEmpty, !historyGenres.isEmpty else { return 0 }
            
            let overlap = candidateGenres.intersection(historyGenres).count
            let possible = max(candidateGenres.union(historyGenres).count, 1)
            return Double(overlap) / Double(possible)
        }
        
        let historyLimit = strength >= 4 ? 10 : 14
        let rankedHistory = watchedHistory
            .sorted { lhs, rhs in
                let lhsRating = library.ratings[lhs.key] ?? 2.5
                let rhsRating = library.ratings[rhs.key] ?? 2.5
                
                if lhsRating != rhsRating {
                    return lhsRating > rhsRating
                }
                
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            .prefix(historyLimit)
        
        var scoredRecommendations: [MediaKey: (item: MediaItem, score: Double)] = [:]
        var nextItems: [MediaItem] = []

        let notInterestedSeeds = library.notInterestedItems

        func notInterestedDownweight(for candidate: MediaItem) -> Double {
            if library.isNotInterested(candidate.key) {
                return 0.03
            }

            guard !notInterestedSeeds.isEmpty else { return 1.0 }

            let candidateGenres = Set(candidate.genreIDs)
            guard !candidateGenres.isEmpty else { return 1.0 }

            for seed in notInterestedSeeds {
                let seedGenres = Set(seed.genreIDs)
                guard !seedGenres.isEmpty else { continue }
                let overlap = candidateGenres.intersection(seedGenres).count
                let union = candidateGenres.union(seedGenres).count
                let similarity = union == 0 ? 0.0 : Double(overlap) / Double(union)
                if similarity >= 0.75 && candidate.kind == seed.kind {
                    return 0.75
                }
            }

            return 1.0
        }

        for record in rankedHistory {
            let weight = historyWeight(for: record)

            do {
                let rec = try await tmdb.recommendations(for: record.key)

                for (index, candidate) in rec.enumerated() {
                    guard !library.isWatched(candidate.key) else { continue }
                    guard !library.isNeverShowAgain(candidate.key) else { continue }

                    let positionScore = 1.0 / (1.0 + Double(index) * 0.08)
                    let similarityBoost = genreSimilarity(candidate, record) * (0.35 + normalizedStrength * 0.45)
                    let score = (positionScore + similarityBoost) * weight * notInterestedDownweight(for: candidate)

                    var entry = scoredRecommendations[candidate.key] ?? (candidate, 0)
                    entry.score += score
                    scoredRecommendations[candidate.key] = entry
                }

                let related = try await tmdb.sameSeriesOrSimilar(for: record.key)
                nextItems.append(contentsOf: related)
            } catch { }
        }
        
        let sortedRecommendations = scoredRecommendations.values
            .filter { $0.score > 0 }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                
                let lhsRating = ratingSortValue(for: lhs.item)
                let rhsRating = ratingSortValue(for: rhs.item)
                if lhsRating != rhsRating {
                    return lhsRating > rhsRating
                }
                
                return (lhs.item.releaseDateValue ?? .distantPast) > (rhs.item.releaseDateValue ?? .distantPast)
            }
            .map(\.item)
        
        let visibleRecommendations = preparedResults(
            sortedRecommendations.filter { !library.isWatched($0.key) && !library.isNeverShowAgain($0.key) },
            hideWatched: true
        )
        recommendations = await filteredContentCleanupIfNeeded(
            visibleRecommendations,
            hideShortFilms: settings.hideShortFilmsFromRecommended,
            hideExtrasAndPromos: settings.hideExtrasAndPromosFromRecommended
        )
        seriesNext = await filteredContentCleanupIfNeeded(
            preparedResults(nextItems.uniqued().filter { !library.isWatched($0.key) && !library.isNeverShowAgain($0.key) && $0.kind == .tv }, hideWatched: true),
            hideShortFilms: settings.hideShortFilmsFromRecommended,
            hideExtrasAndPromos: settings.hideExtrasAndPromosFromRecommended
        )

        if let lastWatched = library.lastWatchedItem {
            let prepared = preparedResults(
                await universalMoreLikeThis(for: lastWatched, hideWatched: true, limit: 80),
                hideWatched: true
            )
            if prepared.isEmpty {
                moreLikeLastWatched = []
            } else {
                moreLikeLastWatched = await filteredContentCleanupIfNeeded(
                    prepared,
                    hideShortFilms: settings.hideShortFilmsFromRecommended,
                    hideExtrasAndPromos: settings.hideExtrasAndPromosFromRecommended
                )
            }
        } else {
            moreLikeLastWatched = []
        }

        var favouriteRecommendations: [MediaItem] = []
        let favouriteSeeds = library.favouriteItems
            .sorted { lhs, rhs in
                let lhsRating = library.ratings[lhs.key] ?? 2.5
                let rhsRating = library.ratings[rhs.key] ?? 2.5
                if lhsRating != rhsRating { return lhsRating > rhsRating }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }

        for favourite in favouriteSeeds.prefix(6) {
            favouriteRecommendations.append(contentsOf: await universalMoreLikeThis(for: favourite, hideWatched: true, limit: 35))
        }

        if !favouriteSeeds.isEmpty {
            let prepared = preparedResults(
                favouriteRecommendations.uniqued(),
                hideWatched: true
            )
            moreLikeFavourite = await filteredContentCleanupIfNeeded(
                prepared,
                hideShortFilms: settings.hideShortFilmsFromRecommended,
                hideExtrasAndPromos: settings.hideExtrasAndPromosFromRecommended
            )
        } else {
            moreLikeFavourite = []
        }

        let watchedGenreIDs = watchedHistory.flatMap(\.genreIDs)
        if let topGenreID = watchedGenreIDs.frequencySorted().first {
            let preparedTopGenre = visibleRecommendations
                .filter { $0.shouldShowInDiscovery && !$0.isUpcoming && $0.genreIDs.contains(topGenreID) }
                .filter { !library.isNeverShowAgain($0.key) }
                .filter { settings.prioritiseEnglish ? (($0.originalLanguage ?? "en") == "en") : true }

            fromTopGenre = await filteredContentCleanupIfNeeded(
                preparedTopGenre,
                hideShortFilms: settings.hideShortFilmsFromRecommended,
                hideExtrasAndPromos: settings.hideExtrasAndPromosFromRecommended
            )
        } else {
            fromTopGenre = []
        }

        let watchedGenreSet = Set(watchedGenreIDs)
        let trySomethingNewPool = (popular + trending + newReleases)
                .uniqued()
                .filter { item in
                    !item.isUpcoming &&
                    !library.isWatched(item.key) &&
                    !library.isNeverShowAgain(item.key) &&
                    watchedGenreSet.isDisjoint(with: Set(item.genreIDs)) &&
                    (settings.prioritiseEnglish ? ((item.originalLanguage ?? "en") == "en") : true)
                }

        let preparedTrySomethingNew = preparedResults(
            trySomethingNewPool
                .sorted { lhs, rhs in
                    let lhsRating = ratingSortValue(for: lhs)
                    let rhsRating = ratingSortValue(for: rhs)
                    if lhsRating != rhsRating {
                        return lhsRating > rhsRating
                    }

                    return (lhs.releaseDateValue ?? .distantPast) > (rhs.releaseDateValue ?? .distantPast)
                },
            hideWatched: true
        )

        trySomethingNewRecommendations = await filteredContentCleanupIfNeeded(
            preparedTrySomethingNew,
            hideShortFilms: settings.hideShortFilmsFromRecommended,
            hideExtrasAndPromos: settings.hideExtrasAndPromosFromRecommended
        )

        saveCurrentHomeFeedCache()
    }

    func loadTopRated(kind: MediaKind) async {
        guard kind == .movie || kind == .tv else { return }
        do {
            let items = try await tmdb.topRated(kind: kind)
            let prepared = preparedResults(items)
            let pool = settings.prioritiseEnglish
                ? prepared.filter { ($0.originalLanguage ?? "en") == "en" }
                : prepared

            if settings.preferredRatingSource != .imdb {
                let sorted = pool.sorted { $0.voteAverage > $1.voteAverage }
                if kind == .movie { topRatedMovies = sorted } else { topRatedShows = sorted }
                return
            }

            for item in pool {
                await loadExternalRatings(item)
            }
            let imdbSorted = pool.sorted { lhs, rhs in
                let lIMDb = externalRatingsCache[lhs.key]?.imdbRating
                let rIMDb = externalRatingsCache[rhs.key]?.imdbRating
                if let l = lIMDb, let r = rIMDb { return l > r }
                if lIMDb != nil { return true }
                if rIMDb != nil { return false }
                return lhs.voteAverage > rhs.voteAverage
            }
            if kind == .movie { topRatedMovies = imdbSorted } else { topRatedShows = imdbSorted }
        } catch { }
    }

    func pickForMeRecommendations(for answers: PickForMeAnswers) async -> [MediaItem] {
        let effectiveFilter = answers.effectiveMediaFilter
        let watchProviderIDs: Set<Int>? = {
            guard answers.myServicesOnly == true, !settings.subscribedServiceNames.isEmpty else { return nil }
            let ids = KnownStreamingService.tmdbProviderIDs(for: settings.subscribedServiceNames)
            return ids.isEmpty ? nil : ids
        }()
        let watchRegion = settings.streamingRegion.rawValue
        let wantsNewReleaseResults = answers.releaseAge == .newReleases
        var sourceMaterialCandidateKeys: Set<MediaKey> = []
        var sourceMaterialItems: [MediaItem] = []

        // -- GROQ PATH (disabled — re-enable by setting useGroq = true) --
        // let useGroq = false
        // let thematicQuery = answers.pickForMeGroqFullQuery ?? answers.pickForMeThematicQuery
        // var thematicCandidates: [MediaItem] = []
        // var rerankScores: [MediaKey: Int] = [:]
        // if useGroq, let query = thematicQuery {
        //     thematicCandidates = await pickForMeThematicCandidates(query: query, filter: effectiveFilter)
        //     if thematicCandidates.count >= 5 {
        //         rerankScores = await pickForMeGroqRerank(candidates: thematicCandidates, query: query)
        //     }
        // }
        // -- END GROQ PATH --

        if let sourceMaterial = answers.sourceMaterial, sourceMaterial != .noPreference {
            do {
                let sm = try await tmdb.discoverSourceMaterial(sourceMaterial, filter: effectiveFilter)
                sourceMaterialCandidateKeys = Set(sm.map(\.key))
                sourceMaterialItems = sm
            } catch { }
        }

        // Run primary broad discovery + all archetype-specific genre combos in parallel
        let primaryGenreIDs = pickForMeDiscoveryGenreIDs(for: answers)
        let supplementalGroups = pickForMeSupplementalDiscoveryGenreIDs(for: answers)

        var discoveredItems: [MediaItem] = []
        await withTaskGroup(of: [MediaItem].self) { group in
            // Primary discovery — OR genres, 3 pages
            if !primaryGenreIDs.isEmpty {
                group.addTask { [weak self] in
                    guard let self else { return [] }
                    return (try? await self.tmdb.discoverPickForMe(
                        filter: effectiveFilter,
                        genreIDs: primaryGenreIDs,
                        runtimeRange: answers.runtimeRange,
                        minimumRating: 0,
                        includeAdult: !self.settings.hideAdultResults,
                        sortBy: "vote_average.desc",
                        watchProviderIDs: watchProviderIDs,
                        watchRegion: watchRegion
                    )) ?? []
                }
            }
            // Supplemental archetype combos — AND genres via discoverThematic (2 pages each)
            for genreGroup in supplementalGroups {
                let ids = genreGroup
                group.addTask { [weak self] in
                    guard let self else { return [] }
                    return (try? await self.tmdb.discoverThematic(
                        personIDs: [],
                        keywordIDs: [],
                        genreIDs: ids,
                        filter: effectiveFilter,
                        watchProviderIDs: watchProviderIDs,
                        watchRegion: watchRegion
                    )) ?? []
                }
            }
            // Keyword discovery for primary archetypes — finds archetype-specific films that
            // may not appear in the top pages of a genre-sorted list (e.g. heist films with
            // a 7.2 rating sit past page 3 of the Crime genre sorted by vote_average.desc)
            for archetype in answers.archetypes where !archetype.isAnyOption {
                for kw in archetype.discoveryKeywords {
                    let keyword = kw
                    group.addTask { [weak self] in
                        guard let self else { return [] }
                        let kwIDs = (try? await self.tmdb.keywordIDs(for: keyword)) ?? []
                        guard !kwIDs.isEmpty else { return [] }
                        return (try? await self.tmdb.discoverThematic(
                            personIDs: [],
                            keywordIDs: kwIDs,
                            genreIDs: [],
                            filter: effectiveFilter,
                            watchProviderIDs: watchProviderIDs,
                            watchRegion: watchRegion
                        )) ?? []
                    }
                }
            }
            for await items in group {
                discoveredItems.append(contentsOf: items)
            }
        }

        var pool = (
            recommendations +
            moreLikeLastWatched +
            moreLikeFavourite +
            fromTopGenre +
            seriesNext +
            library.watchlistItems
        )
        if wantsNewReleaseResults {
            pool.append(contentsOf: newReleases + trySomethingNewRecommendations)
        }
        pool.append(contentsOf: discoveredItems)
        pool.append(contentsOf: sourceMaterialItems)
        let uniqueCandidates = pool.uniqued()

        await loadPickForMeStrictFilterDetails(for: uniqueCandidates, answers: answers)

        // Load external ratings for the first 60 candidates (RT penalty + IMDb sort)
        await withTaskGroup(of: Void.self) { group in
            for item in uniqueCandidates.prefix(60) where externalRatingsCache[item.key] == nil {
                group.addTask { await self.loadExternalRatings(item) }
            }
        }

        let filtered = uniqueCandidates
            .uniqued()
            .filter { item in
                guard !library.isNeverShowAgain(item.key) else { return false }
                guard !settings.hideUpcomingFromRecommended || !item.isUpcoming else { return false }
                guard effectiveFilter == .both || item.kind.rawValue == effectiveFilter.rawValue else { return false }

                // Exclude obscure titles with very few votes — prevents tag-matched noise from surfacing
                if let count = item.voteCount, count < 200 { return false }

                if !pickForMeRuntimeAllows(item, runtimeRange: answers.runtimeRange) {
                    return false
                }

                if !pickForMeReleaseAgeAllows(item, releaseAge: answers.releaseAge) {
                    return false
                }

                if !pickForMeDocumentaryAllows(item, answers: answers) {
                    return false
                }

                if !pickForMeFictionAllows(item, answers: answers) {
                    return false
                }

                if !pickForMeHistoryAllows(item, answers: answers) {
                    return false
                }

                if !answers.contentRatings.isEmpty && !answers.contentRatings.contains(.any) {
                    if let detailRating = detailsCache[item.key]?.ageRating,
                       !detailRating.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       !PickForMeContentRating.selectionAllows(answers.contentRatings, rating: detailRating) {
                        return false
                    }
                }

                if answers.dealBreakers.contains(where: { pickForMeFastDealBreakerMatches(item: item, dealBreaker: $0) }) {
                    return false
                }

                if let minimumRating = answers.minimumRating, let min = minimumRating.minimumRating {
                    let rating = ratingSortValue(for: item)
                    if rating > 0, rating < min - 0.5 {
                        return false
                    }
                }

                if !pickForMePrimaryArchetypeAllows(item, answers: answers) {
                    return false
                }

                if answers.myServicesOnly == true, !settings.subscribedServiceNames.isEmpty {
                    if let options = providerCache[item.key] {
                        let subscribed = settings.subscribedServiceNames
                        let available = options.contains { option in
                            let t = option.type.lowercased()
                            return ["subscription", "sub", "free"].contains(t) && option.isSubscribed(in: subscribed)
                        }
                        if !available { return false }
                    }
                }

                return true
            }

        let prepared = preparedResults(filtered, hideWatched: false)
        let visible = prepared.filter { item in
            if shouldHideAsShortFilm(item, enabled: true) {
                return false
            }

            if shouldHideAsSupplementalContent(item, enabled: settings.hideExtrasAndPromosFromRecommended) {
                return false
            }

            return true
        }

        let sorted = visible
            .sorted { lhs, rhs in
                let lhsScore = pickForMeScore(lhs, answers: answers, sourceMaterialCandidateKeys: sourceMaterialCandidateKeys)
                let rhsScore = pickForMeScore(rhs, answers: answers, sourceMaterialCandidateKeys: sourceMaterialCandidateKeys)

                if lhsScore != rhsScore {
                    return lhsScore > rhsScore
                }

                let lhsRating = ratingSortValue(for: lhs)
                let rhsRating = ratingSortValue(for: rhs)
                if lhsRating != rhsRating {
                    return lhsRating > rhsRating
                }

                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }

        let lateFiltered = pickForMeApplyLateContentDealBreakers(to: sorted, answers: answers)

        return balancedPickForMeResults(lateFiltered, filter: effectiveFilter, limit: 120)
    }

    private func pickForMeDiscoveryGenreIDs(for answers: PickForMeAnswers) -> Set<Int> {
        var genreIDs: Set<Int> = []

        if answers.wantsStrictHistorical {
            genreIDs.formUnion(pickForMeHistoricalGenreIDs)
        }

        if answers.wantsHumanTriumph {
            genreIDs.insert(18)
        }

        for genrePreference in answers.genrePreferences {
            switch genrePreference {
            case .history:
                break
            case .war:
                genreIDs.formUnion(pickForMeWarGenreIDs)
            case .crime:
                genreIDs.insert(80)
            case .sciFi:
                genreIDs.formUnion([878, 10765])
            case .fantasy:
                genreIDs.formUnion([14, 10765])
            case .horror:
                genreIDs.insert(27)
            case .romance:
                genreIDs.insert(10749)
            case .animation:
                genreIDs.insert(16)
            case .family:
                genreIDs.formUnion([10751, 10762])
            case .action:
                genreIDs.insert(28)
            case .comedy:
                genreIDs.insert(35)
            case .space:
                genreIDs.formUnion([878, 10765])  // Sci-Fi — closest available TMDb genre for space
            case .noPreference:
                break
            }
        }

        return genreIDs
    }

    private func pickForMeSupplementalDiscoveryGenreIDs(for answers: PickForMeAnswers) -> [Set<Int>] {
        var genreIDs: [Set<Int>] = []

        func append(_ ids: Set<Int>) {
            guard !ids.isEmpty, !genreIDs.contains(ids) else { return }
            genreIDs.append(ids)
        }

        let archetypes = answers.archetypes.union(answers.secondaryArchetypes)
        for archetype in archetypes {
            switch archetype {
            case .feelGood:
                append([35, 10751])  // Comedy AND Family
                append([35])
            case .comedy:
                append([35])
            case .mystery:
                append([9648])
                append([9648, 53])   // Mystery AND Thriller
            case .thriller:
                append([53])
                append([53, 9648])   // Thriller AND Mystery
            case .smartProblems:
                append([18, 53])     // Drama AND Thriller
                append([18, 80])     // Drama AND Crime
            case .mission:
                append([28, 53])     // Action AND Thriller
                append([28])
            case .heist:
                append([80, 53])     // Crime AND Thriller — Ocean's Eleven, Heat
                append([53])         // Thriller alone — catches sophisticated capers not tagged Crime
                append([80])         // Crime alone — broader net
                append([35, 80])     // Comedy AND Crime — caper comedies
            case .adventure:
                append([12])
                append([12, 28])     // Adventure AND Action
            case .characterRelationships:
                append([18, 10749])  // Drama AND Romance
                append([18, 10751])  // Drama AND Family
                append([18])
            case .humanTriumph:
                append([18])
                append([18, 36])     // Drama AND History — biopics, real triumph stories
            case .documentary:
                append([99])
            case .historical:
                append([36])
                append([36, 18])     // History AND Drama
            case .war:
                append(pickForMeWarGenreIDs)
                append([10752, 18])  // War AND Drama
            case .epicSpectacle:
                append([12, 14])     // Adventure AND Fantasy
                append([12, 878])    // Adventure AND Sci-Fi
                append([28, 12])     // Action AND Adventure
            case .mindBending:
                append([9648, 878])  // Mystery AND Sci-Fi
                append([9648, 53])   // Mystery AND Thriller
                append([878, 53])    // Sci-Fi AND Thriller
            case .horror:
                append([27])
                append([27, 53])     // Horror AND Thriller
            case .thoughtfulSciFi:
                append([878, 18])    // Sci-Fi AND Drama
                append([878])
            case .surprise, .noPreference:
                break
            }
        }

        return Array(genreIDs.prefix(6))
    }

    private func balancedPickForMeResults(_ items: [MediaItem], filter: MediaFilter, limit: Int) -> [MediaItem] {
        guard filter == .both else { return items.prefixArray(limit) }

        let limitedItems = items.prefixArray(limit)
        let maximumPerKind = max(Int(ceil(Double(limitedItems.count) * 0.8)), 1)
        var counts: [MediaKind: Int] = [:]
        var balanced: [MediaItem] = []

        for item in items {
            guard balanced.count < limit else { break }
            let currentCount = counts[item.kind, default: 0]
            guard currentCount < maximumPerKind else { continue }

            balanced.append(item)
            counts[item.kind, default: 0] = currentCount + 1
        }

        return balanced
    }

    private func pickForMeRuntimeAllows(_ item: MediaItem, runtimeRange: PickForMeRuntimeRange) -> Bool {
        guard item.kind == .movie else { return true }
        guard runtimeRange.hasConstraint else { return true }
        guard let minutes = detailsCache[item.key]?.runtime ?? item.runtime else { return true }

        return runtimeRange.contains(minutes)
    }

    private func loadPickForMeStrictFilterDetails(for items: [MediaItem], answers: PickForMeAnswers) async {
        await withTaskGroup(of: Void.self) { group in
            for item in items.prefix(120) where detailsCache[item.key] == nil {
                group.addTask { [weak self] in
                    guard let self else { return }
                    do {
                        let detail = try await self.tmdb.detail(for: item, regionCode: self.settings.streamingRegion.rawValue)
                        await MainActor.run { self.detailsCache[item.key] = detail }
                    } catch { }
                }
            }
        }
    }

    private func pickForMeReleaseAgeAllows(_ item: MediaItem, releaseAge: PickForMeReleaseAge?) -> Bool {
        guard let releaseAge, releaseAge != .noPreference else { return true }
        guard let releaseDate = item.releaseDateValue else { return false }
        let now = Date()
        guard releaseDate <= now else { return false }

        if releaseAge == .newReleases {
            guard let cutoffDate = Calendar.current.date(byAdding: .month, value: -6, to: now) else {
                return false
            }
            return releaseDate >= cutoffDate
        }

        let yearsOld = Calendar.current.dateComponents([.year], from: releaseDate, to: now).year ?? 0

        if let maximumYearsOld = releaseAge.maximumYearsOld {
            return yearsOld <= maximumYearsOld
        }

        if let minimumYearsOld = releaseAge.minimumYearsOld {
            return yearsOld > minimumYearsOld
        }

        return true
    }

    private func pickForMeDocumentaryAllows(_ item: MediaItem, answers: PickForMeAnswers) -> Bool {
        guard answers.wantsDocumentary else { return true }
        return item.genreIDs.contains(99)
    }

    private func pickForMeSourceMaterialAllows(_ item: MediaItem, sourceMaterial: PickForMeSourceMaterial?, sourceMaterialCandidateKeys: Set<MediaKey>) -> Bool {
        guard let sourceMaterial, sourceMaterial != .noPreference else { return true }
        if sourceMaterialCandidateKeys.contains(item.key) { return true }

        let text = pickForMeSearchableText(for: item)
        return pickForMeSourceMaterialTextMatches(text, sourceMaterial: sourceMaterial)
    }

    private func pickForMeSourceMaterialScore(item: MediaItem, text: String, sourceMaterial: PickForMeSourceMaterial, sourceMaterialCandidateKeys: Set<MediaKey>) -> Double {
        guard sourceMaterial != .noPreference else { return 0 }
        if sourceMaterialCandidateKeys.contains(item.key) || pickForMeSourceMaterialTextMatches(text, sourceMaterial: sourceMaterial) {
            return 18.0
        }

        return -1.5
    }

    private func pickForMeSourceMaterialTextMatches(_ text: String, sourceMaterial: PickForMeSourceMaterial) -> Bool {
        switch sourceMaterial {
        case .book:
            return text.containsAny(["based on the novel", "based on a novel", "based on the book", "based on a book", "adapted from the novel", "adapted from a novel", "book by", "novel by"])
        case .game:
            return text.containsAny(["based on the video game", "based on a video game", "video game", "videogame", "game series", "computer game"])
        case .noPreference:
            return true
        }
    }

    private func pickForMeFictionAllows(_ item: MediaItem, answers: PickForMeAnswers) -> Bool {
        guard let pref = answers.fictionPreference, !pref.isAnyOption else { return true }
        let genres = Set(item.genreIDs)
        let text = pickForMeSearchableText(for: item)

        switch pref {
        case .nonFiction:
            return genres.contains(99) || pickForMeIsNonfictionOrTrueEvent(genres: genres, text: text)
        case .basedOnTrueStory:
            return pickForMeIsNonfictionOrTrueEvent(genres: genres, text: text)
        case .fiction, .noPreference:
            return true
        }
    }

    private func pickForMeHistoryAllows(_ item: MediaItem, answers: PickForMeAnswers) -> Bool {
        guard answers.wantsStrictHistorical else { return true }

        let historicalScore = pickForMeHistoricalEventScore(genres: Set(item.genreIDs), text: pickForMeSearchableText(for: item))
        return historicalScore > 0
    }

    private func pickForMeScore(_ item: MediaItem, answers: PickForMeAnswers, sourceMaterialCandidateKeys: Set<MediaKey>) -> Double {
        let primaryAlignment = pickForMePrimaryArchetypeAlignmentScore(item, answers: answers)
        var score = primaryAlignment * 15.0  // was 13.0 — compensates for removed Groq +20 bonus
        let genreIDs = Set(item.genreIDs)
        let text = pickForMeSearchableText(for: item)

        if library.isNotInterested(item.key) {
            score -= 40.0
        }

        if library.isNeverShowAgain(item.key) {
            score -= 250.0
        }

        score += pickForMePrimaryArchetypeSoftGateAdjustment(primaryAlignment, answers: answers)

        let primaryArchetypeScores = answers.archetypes.map { archetype in
            pickForMeArchetypeScore(item: item, archetype: archetype)
        }

        for (archetype, archetypeScore) in zip(answers.archetypes, primaryArchetypeScores) {
            score += archetypeScore * (archetype == .surprise ? 0.65 : 1.0)
        }

        for secondaryArchetype in answers.secondaryArchetypes where !secondaryArchetype.isAnyOption {
            score += pickForMeArchetypeScore(item: item, archetype: secondaryArchetype) * 0.42
        }

        score += pickForMeArchetypeCombinationBonus(primaryScores: primaryArchetypeScores)

        for genrePreference in answers.genrePreferences where !genrePreference.isAnyOption {
            score += pickForMeGenrePreferenceScore(genres: genreIDs, text: text, genrePreference: genrePreference)
        }

        if let sourceMaterial = answers.sourceMaterial {
            score += pickForMeSourceMaterialScore(item: item, text: text, sourceMaterial: sourceMaterial, sourceMaterialCandidateKeys: sourceMaterialCandidateKeys)
        }

        score += pickForMeAnswerFulfillmentScore(
            item: item,
            genres: genreIDs,
            text: text,
            answers: answers,
            sourceMaterialCandidateKeys: sourceMaterialCandidateKeys
        )

        if let minimumRating = answers.minimumRating {
            score += pickForMeMinimumRatingScore(for: item, minimumRating: minimumRating)
        }

        score -= pickForMeRottenTomatoesPenalty(for: item)

        if item.genreIDs.contains(99) && !answers.wantsDocumentary {
            score -= pickForMeDocumentaryDownweight(for: answers)
        }

        score += pickForMeAnimationAdultThemeAdjustment(genres: genreIDs, answers: answers)
        score += pickForMeChildAnimationSettingsAdjustment(item: item, genres: genreIDs, answers: answers)

        score -= pickForMeArchetypeMismatchPenalty(genres: genreIDs, text: text, answers: answers)

        if answers.wantsHistorical && !genreIDs.intersection(pickForMeWarGenreIDs).isEmpty && !answers.wantsWar {
            score -= pickForMeHistoricalWarDownweight(for: answers)
        }

        if shouldPenalizeMissingContentRating(item, answers: answers) {
            score -= 1.5
        }

        score += max(ratingSortValue(for: item), 0) * 0.25

        if library.isInWatchlist(item.key) {
            score += 0.5
        }

        if recommendations.contains(where: { $0.key == item.key }) ||
            moreLikeLastWatched.contains(where: { $0.key == item.key }) ||
            moreLikeFavourite.contains(where: { $0.key == item.key }) {
            score += 0.3
        }

        score += pickForMePersonalizationScore(for: item) * 0.22  // was 0.18 — library signal more important without Groq

        // -- GROQ SCORE BONUSES (disabled with Groq path) --
        // if thematicCandidateKeys.contains(item.key) { score += 20.0 }
        // if let rank = rerankScores[item.key] { score += max(0.0, 16.0 - Double(rank - 1) * 1.5) }
        // -- END GROQ BONUSES --

        return score
    }

    private func pickForMePrimaryArchetypeAllows(_ item: MediaItem, answers: PickForMeAnswers) -> Bool {
        guard pickForMeHasDominantPrimaryArchetype(answers) else { return true }
        return pickForMePrimaryArchetypeAlignmentScore(item, answers: answers) >= 3.2
    }

    private func pickForMePrimaryArchetypeSoftGateAdjustment(_ alignment: Double, answers: PickForMeAnswers) -> Double {
        guard pickForMeHasDominantPrimaryArchetype(answers) else { return 0 }

        if alignment >= 6.5 {
            return 18.0  // was 14.0
        }

        if alignment >= 4.5 {
            return 8.0   // was 6.0
        }

        if alignment >= 3.2 {
            return -14.0
        }

        return -240.0
    }

    private func pickForMePrimaryArchetypeAlignmentScore(_ item: MediaItem, answers: PickForMeAnswers) -> Double {
        let primaryArchetypes = answers.archetypes.filter { archetype in
            !archetype.isAnyOption && archetype != .surprise
        }

        guard !primaryArchetypes.isEmpty else { return 0 }
        return primaryArchetypes.map { pickForMeArchetypeScore(item: item, archetype: $0) }.max() ?? 0
    }

    private func pickForMeHasDominantPrimaryArchetype(_ answers: PickForMeAnswers) -> Bool {
        answers.archetypes.contains { archetype in
            !archetype.isAnyOption && archetype != .surprise
        }
    }

    private func pickForMeAnswerFulfillmentScore(item: MediaItem, genres: Set<Int>, text: String, answers: PickForMeAnswers, sourceMaterialCandidateKeys: Set<MediaKey>) -> Double {
        var score = 0.0

        for secondaryArchetype in answers.secondaryArchetypes where !secondaryArchetype.isAnyOption {
            let match = pickForMeArchetypeScore(item: item, archetype: secondaryArchetype)
            if match >= 4.0 {
                score += 4.0
            } else if match >= 2.0 {
                score += 1.5
            }
        }

        for genrePreference in answers.genrePreferences where !genrePreference.isAnyOption {
            if pickForMeGenrePreferenceScore(genres: genres, text: text, genrePreference: genrePreference) > 0 {
                score += 2.5
            }
        }

        if let sourceMaterial = answers.sourceMaterial, sourceMaterial != .noPreference {
            if sourceMaterialCandidateKeys.contains(item.key) || pickForMeSourceMaterialTextMatches(text, sourceMaterial: sourceMaterial) {
                score += 5.0
            }
        }

        if let minimumRating = answers.minimumRating, let minimum = minimumRating.minimumRating, ratingSortValue(for: item) >= minimum {
            score += 5.0
        }

        if !answers.contentRatings.isEmpty && !answers.contentRatings.contains(.any) {
            score += 1.0
        }

        if answers.runtimeRange.hasConstraint {
            score += 1.0
        }

        if answers.releaseAge != nil && answers.releaseAge != .noPreference {
            score += 1.0
        }

        return score
    }

    private func cachedArchetypeInference(for item: MediaItem) -> ArchetypeInference? {
        guard let detail = detailsCache[item.key], !detail.keywordNames.isEmpty else { return nil }
        if let cached = archetypeInferenceCache[item.key] { return cached }
        let input = ArchetypeInferenceInput(
            genreIDs: item.genreIDs,
            keywordNames: detail.keywordNames,
            networkNames: detail.networkNames,
            numberOfSeasons: detail.seasons.isEmpty ? nil : detail.seasons.count,
            runtime: detail.runtime,
            isInCollection: detail.tmdbCollectionID != nil,
            isTV: item.kind == .tv
        )
        let inference = ArchetypeInferenceEngine.infer(from: input)
        archetypeInferenceCache[item.key] = inference
        return inference
    }

    private func pickForMeArchetypeScore(item: MediaItem, archetype: PickForMeArchetype) -> Double {
        let genres = Set(item.genreIDs)
        let text = pickForMeSearchableText(for: item)
        let inferenceBonus = (cachedArchetypeInference(for: item)?.confidence(for: archetype) ?? 0) * 5.0

        let base: Double
        switch archetype {
        case .feelGood:
            base = pickForMeKeywordScore(text, ["optimistic", "heartwarming", "friendship", "family", "personal growth", "inspiring", "uplifting", "feel-good", "new beginning"]) * 1.8 +
                (genres.intersection([35, 10751, 18, 12]).isEmpty ? 0 : 4.2) -
                (genres.intersection([27, 10752]).isEmpty ? 0 : 1.8)
        case .comedy:
            base = pickForMeKeywordScore(text, ["satire", "buddy comedy", "workplace comedy", "funny", "comedian", "laugh"]) * 1.7 +
                (genres.contains(35) ? 5.0 : 0)
        case .mystery:
            base = pickForMeKeywordScore(text, ["detective", "investigation", "conspiracy", "murder mystery", "whodunnit", "clue", "secret"]) * 2.0 +
                (genres.intersection([9648, 53, 80]).isEmpty ? 0 : 4.6)
        case .thriller:
            base = pickForMeKeywordScore(text, ["danger", "survival", "suspense", "pursuit", "fugitive", "threat", "uncertainty", "crime"]) * 1.8 +
                (genres.intersection([53, 80, 28]).isEmpty ? 0 : 4.5)
        case .smartProblems:
            let kwScore = pickForMeKeywordScore(text, ["investigation", "journalist", "scientist", "engineer", "rescue mission", "courtroom", "legal", "historical event", "based on true", "expert", "team", "strategic", "intelligence"]) * 2.0
            var s = kwScore
            let hasGenreMatch = !genres.intersection([18, 53, 36]).isEmpty
            // Genre alone (no keyword signal) gives reduced credit — drama is too broad otherwise
            s += hasGenreMatch ? (kwScore > 0 ? 4.0 : 1.5) : 0
            if genres.contains(14) || genres.contains(27) { s -= 2.5 }
            if genres.contains(35) && !genres.contains(18) { s -= 1.2 }
            base = s
        case .mission:
            base = pickForMeKeywordScore(text, ["mission", "operation", "rescue", "espionage", "military objective", "survival objective", "special operations", "spy", "objective"]) * 2.0 +
                (genres.intersection([53, 28, 10752, 80, 36]).isEmpty ? 0 : 4.2)
        case .heist:
            let caperSignals = ["heist", "caper", "con artist", "con man", "con woman", "con game", "grifter", "confidence trick", "casino", "infiltrat", "scheme", "mastermind", "getaway", "elaborate", "jewel"]
            let bruteSignals = ["robbery", "theft", "steal", "thief", "extraction"]
            let caperCount = caperSignals.filter { text.contains($0) }.count
            let bruteCount = bruteSignals.filter { text.contains($0) }.count
            let caperScore = Double(caperCount) * 4.5
            let bruteScore = Double(bruteCount) * 0.8
            // GenreBase only meaningful when there are actual heist-related signals in the text;
            // without signals, Crime/Thriller alone isn't enough to score well as a heist film.
            let genreBase = genres.intersection([80, 53]).isEmpty ? 0.0 :
                (caperCount > 0 ? 5.5 : (bruteCount > 0 ? 4.0 : 3.5))
            base = caperScore + bruteScore + genreBase
        case .adventure:
            base = pickForMeKeywordScore(text, ["treasure", "expedition", "exploration", "archaeology", "quest", "journey", "travel"]) * 2.0 +
                (genres.intersection([12, 28, 10759]).isEmpty ? 0 : 4.4)
        case .characterRelationships:
            base = pickForMeKeywordScore(text, ["family", "friendship", "relationship", "relationships", "coming of age", "personal growth", "love"]) * 1.7 +
                (genres.intersection([18, 35, 10749]).isEmpty ? 0 : 4.0)
        case .humanTriumph:
            base = pickForMeKeywordScore(text, pickForMeHumanTriumphSignals) * 2.1 +
                (genres.intersection([18, 36]).isEmpty ? 0 : 3.2) -
                (genres.intersection([27, 878, 14]).isEmpty ? 0 : 2.0)
        case .documentary:
            base = pickForMeKeywordScore(text, ["documentary", "docuseries", "true story", "real-life", "real life", "interview", "archive", "behind the scenes"]) * 2.1 +
                (genres.contains(99) ? 6.0 : 0)
        case .historical:
            base = pickForMeHistoricalEventScore(genres: genres, text: text) * 1.65
        case .war:
            base = pickForMeKeywordScore(text, pickForMeWarDealBreakerSignals) * 2.1 +
                (genres.intersection(pickForMeWarGenreIDs).isEmpty ? 0 : 6.0)
        case .epicSpectacle:
            var s = pickForMeKeywordScore(text, pickForMeEpicSpectacleSignals) * 2.4
            if genres.contains(878) || genres.contains(10752) || genres.contains(10768) { s += 4.8 }
            if genres.contains(12) || genres.contains(14) { s += 3.4 }
            if genres.contains(28) { s += text.containsAny(pickForMeEpicSpectacleSignals) ? 2.4 : 0.8 }
            base = s
        case .mindBending:
            base = pickForMeKeywordScore(text, ["memory", "nonlinear", "alternate reality", "twist", "puzzle", "mind-bending", "reality", "dream", "subconscious", "perception", "illusion", "layers"]) * 2.1 +
                (genres.intersection([9648, 878, 53]).isEmpty ? 0 : 4.0)
        case .horror:
            base = pickForMeKeywordScore(text, ["supernatural", "monster", "possession", "slasher", "psychological horror", "terror", "dread", "haunted"]) * 2.0 +
                (genres.contains(27) ? 5.0 : 0)
        case .thoughtfulSciFi:
            base = pickForMeKeywordScore(text, ["artificial intelligence", "ethics", "future society", "technology", "consciousness", "philosophical", "experiment"]) * 2.1 +
                (genres.intersection([878, 18]).isEmpty ? 0 : 4.1) -
                (genres.intersection([28, 10752]).isEmpty ? 0 : 1.0)
        case .surprise:
            return ratingSortValue(for: item) + (library.isInWatchlist(item.key) ? 2.0 : 0)
        case .noPreference:
            return 0
        }
        return base + inferenceBonus
    }

    private func pickForMeArchetypeCombinationBonus(primaryScores: [Double]) -> Double {
        let strongMatches = primaryScores.filter { $0 >= 3.5 }.count
        guard strongMatches >= 2 else { return 0 }
        return Double(strongMatches - 1) * 2.4
    }

    private func pickForMeGenrePreferenceScore(genres: Set<Int>, text: String, genrePreference: PickForMeGenrePreference) -> Double {
        switch genrePreference {
        case .space:
            return genres.contains(878) || text.containsAny(["space", "planet", "astronaut", "galaxy"]) ? 1.4 : 0
        case .fantasy:
            return genres.contains(14) || text.containsAny(["magic", "fantasy", "kingdom"]) ? 1.2 : 0
        case .sciFi:
            return genres.contains(878) || genres.contains(10765) ? 1.25 : 0
        case .history:
            let historicalScore = pickForMeHistoricalEventScore(genres: genres, text: text)
            return historicalScore > 0 ? 1.0 + min(historicalScore * 0.35, 2.2) : 0
        case .crime:
            return genres.contains(80) || text.containsAny(["crime", "detective", "police"]) ? 1.15 : 0
        case .war:
            return genres.contains(10752) || genres.contains(10768) || text.contains("war") ? 1.15 : 0
        case .romance:
            return genres.contains(10749) ? 1.0 : 0
        case .animation:
            return genres.contains(16) ? 1.0 : 0
        case .family:
            return genres.contains(10751) || genres.contains(10762) ? 1.0 : 0
        case .horror:
            return genres.contains(27) ? 1.1 : 0
        case .action:
            return genres.contains(28) || text.containsAny(["action", "chase", "explosive", "combat", "fight"]) ? 1.3 : 0
        case .comedy:
            return genres.contains(35) || text.containsAny(["comedy", "comedic", "humorous", "funny"]) ? 1.2 : 0
        case .noPreference:
            return 0
        }
    }

    private func pickForMeIsSpeculative(genres: Set<Int>, text: String) -> Bool {
        !genres.intersection([878, 14, 10765]).isEmpty || text.containsAny(["superhero", "magic", "alien", "monster"])
    }

    private func pickForMeIsNonfictionOrTrueEvent(genres: Set<Int>, text: String) -> Bool {
        genres.contains(99) || pickForMeHistoricalEventScore(genres: genres, text: text) > 0
    }

    private func pickForMeMinimumRatingScore(for item: MediaItem, minimumRating: PickForMeMinimumRating) -> Double {
        guard let minimum = minimumRating.minimumRating else { return 0 }
        let rating = ratingSortValue(for: item)

        if rating >= minimum {
            return 8.0 + min((rating - minimum) * 4.5, 13.0)
        }

        if rating >= minimum - 0.4 {
            return -12.0
        }

        if rating >= minimum - 0.8 {
            return -28.0
        }

        return -55.0
    }

    private func pickForMeRottenTomatoesPenalty(for item: MediaItem) -> Double {
        guard let rt = externalRatingsCache[item.key]?.rottenTomatoesRating else { return 0 }
        if rt < 20 { return 18.0 }
        if rt < 30 { return 12.0 }
        if rt < 40 { return 6.0 }
        if rt < 50 { return 2.5 }
        return 0
    }

    private func shouldPenalizeMissingContentRating(_ item: MediaItem, answers: PickForMeAnswers) -> Bool {
        guard !answers.contentRatings.isEmpty, !answers.contentRatings.contains(.any) else { return false }
        guard let rawRating = detailsCache[item.key]?.ageRating else { return true }
        return rawRating.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func pickForMeDocumentaryDownweight(for answers: PickForMeAnswers) -> Double {
        if answers.dealBreakers.contains(.documentary) {
            return 250.0
        }

        if answers.wantsHistorical {
            return 10.0
        }

        if answers.fictionPreference == .nonFiction || answers.fictionPreference == .basedOnTrueStory {
            return 5.0
        }

        return 8.0
    }

    private func pickForMeHistoricalWarDownweight(for answers: PickForMeAnswers) -> Double {
        if answers.archetypes.contains(.mission) || answers.secondaryArchetypes.contains(.mission) {
            return 8.0
        }
        return 14.0
    }

    private func pickForMeAnimationAdultThemeAdjustment(genres: Set<Int>, answers: PickForMeAnswers) -> Double {
        guard genres.contains(16), answers.prefersAdultLeaningMood, !answers.genrePreferences.contains(.animation) else {
            return 0
        }

        return -2.0
    }

    private func pickForMeChildAnimationSettingsAdjustment(item: MediaItem, genres: Set<Int>, answers: PickForMeAnswers) -> Double {
        guard settings.hideLowestAgeRatings, genres.contains(16), !answers.genrePreferences.contains(.animation) else {
            return 0
        }

        let hasFamilyGenre = genres.contains(10751) || genres.contains(10762)
        let hasLowestAgeRating = detailsCache[item.key]?.ageRating.map(Self.isLowestAgeRating) ?? false

        return hasFamilyGenre || hasLowestAgeRating ? -3.0 : 0
    }

    private func pickForMeArchetypeMismatchPenalty(genres: Set<Int>, text: String, answers: PickForMeAnswers) -> Double {
        var penalty = 0.0

        if answers.wantsHumanTriumph {
            let triumphSignalCount = pickForMeKeywordScore(text, pickForMeHumanTriumphSignals)
            let hasTriumphGenreShape = !genres.intersection([18, 36]).isEmpty && genres.isDisjoint(with: [27, 878, 14])

            if triumphSignalCount == 0 && !hasTriumphGenreShape {
                penalty += 9.0
            }

            if triumphSignalCount == 0 && !genres.intersection([80, 9648]).isEmpty {
                penalty += 10.0
            }

            if !genres.intersection([27, 878, 14]).isEmpty {
                penalty += 8.0
            }

            let actionOrWarGenres = Set([53, 28]).union(pickForMeWarGenreIDs)
            if !genres.intersection(actionOrWarGenres).isEmpty && !text.containsAny(pickForMeHumanTriumphSignals) {
                penalty += 8.0
            }
        }

        // Children's/family animation (Pixar, Disney kids, etc.) is a poor fit for deeper archetypes.
        // Adult animation (Ghost in the Shell, Paprika, Waking Life) is fine and should not be penalized.
        // Family/Kids genre (10751, 10762) combined with Animation (16) reliably identifies children's content.
        let isChildrenAnimation = genres.contains(16) && !genres.intersection([10751, 10762]).isEmpty

        // Thoughtful SciFi: kids animation almost never fits
        if answers.archetypes.contains(.thoughtfulSciFi) || answers.secondaryArchetypes.contains(.thoughtfulSciFi) {
            if isChildrenAnimation {
                penalty += 12.0
            }
            let isHighAction = !genres.intersection([28, 10752]).isEmpty && !genres.contains(18) && !genres.contains(9648)
            if isHighAction && !text.containsAny(["artificial intelligence", "consciousness", "ethics", "philosophical", "society", "human nature", "future of"]) {
                penalty += 4.0
            }
        }

        // Mind-Bending: kids animation and superhero blockbusters without specific mind-bending signals
        if answers.archetypes.contains(.mindBending) || answers.secondaryArchetypes.contains(.mindBending) {
            if isChildrenAnimation {
                penalty += 8.0
            }
            // Action + Adventure without Mystery genre and no specific mind-bending text → likely a superhero blockbuster.
            // "reality" and "mind" excluded — appear in nearly every blockbuster ("his will on all of reality", "Mind Stone").
            if genres.contains(28) && genres.contains(12) && !genres.contains(9648) &&
                !text.containsAny(["nonlinear", "alternate reality", "illusion", "paradox", "consciousness", "surreal", "mind-bending", "time loop", "unreliable"]) {
                penalty += 7.0
            }
        }

        // Smart Problems: romance content and kids animation without intellectual signals don't fit
        if answers.archetypes.contains(.smartProblems) || answers.secondaryArchetypes.contains(.smartProblems) {
            if genres.contains(10749) {
                penalty += 5.0
            }
            if text.containsAny(["forbidden love", "telenovela", "second chance at love", "love triangle", "star-crossed lovers"]) {
                penalty += 4.0
            }
            if isChildrenAnimation && !text.containsAny(["investigat", "scientist", "engineer", "journalist", "legal", "court", "expert"]) {
                penalty += 4.5
            }
        }

        return penalty
    }

    private func pickForMePersonalizationScore(for item: MediaItem) -> Double {
        let itemGenres = Set(item.genreIDs)
        guard !itemGenres.isEmpty else { return 0 }

        let highlyRatedItems = library.ratings.compactMap { key, rating in
            rating >= 4 ? library.items[key] : nil
        }

        let favouriteScore = pickForMeGenreOverlapScore(itemGenres: itemGenres, sourceItems: library.favouriteItems, weight: 0.85, cap: 3.4)
        let highlyRatedScore = pickForMeGenreOverlapScore(itemGenres: itemGenres, sourceItems: highlyRatedItems, weight: 0.7, cap: 3.0)
        let watchedScore = pickForMeGenreOverlapScore(itemGenres: itemGenres, sourceItems: library.watchedItems, weight: 0.22, cap: 2.0)
        return favouriteScore + highlyRatedScore + watchedScore
    }

    private func pickForMeGenreOverlapScore(itemGenres: Set<Int>, sourceItems: [MediaItem], weight: Double, cap: Double) -> Double {
        let overlapCount = sourceItems.uniqued().reduce(0) { partialResult, other in
            partialResult + (itemGenres.isDisjoint(with: Set(other.genreIDs)) ? 0 : 1)
        }

        return min(Double(overlapCount) * weight, cap)
    }

    private func pickForMeFastDealBreakerMatches(item: MediaItem, dealBreaker: PickForMeDealBreaker) -> Bool {
        guard !dealBreaker.requiresLateDescriptionPass else { return false }
        return pickForMeDealBreakerMatches(item: item, dealBreaker: dealBreaker)
    }

    private func pickForMeApplyLateContentDealBreakers(to items: [MediaItem], answers: PickForMeAnswers) -> [MediaItem] {
        let lateDealBreakers = answers.dealBreakers.filter(\.requiresLateDescriptionPass)
        guard !lateDealBreakers.isEmpty else { return items }

        return items.filter { item in
            !lateDealBreakers.contains { dealBreaker in
                pickForMeLateContentDealBreakerMatches(item: item, dealBreaker: dealBreaker)
            }
        }
    }

    private func pickForMeLateContentDealBreakerMatches(item: MediaItem, dealBreaker: PickForMeDealBreaker) -> Bool {
        let description = item.overview.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else { return false }

        switch dealBreaker {
        case .graphicViolence:
            let strongGraphicSignals = ["gore", "gory", "blood-soaked", "gruesome", "massacre", "torture", "dismember", "slasher"]
            let violenceSignals = ["bloody", "brutal", "violent", "violence", "killing", "killings", "murder spree"]
            return description.containsAny(strongGraphicSignals) || pickForMeKeywordScore(description, violenceSignals) >= 2
        case .sexualContent:
            let explicitSexualSignals = ["erotic", "sex worker", "prostitute", "brothel", "stripper", "nude", "nudity", "pornographic"]
            let sexualSignals = ["sexual", "sex", "seduction", "seduces", "affair", "lust"]
            return description.containsAny(explicitSexualSignals) || pickForMeKeywordScore(description, sexualSignals) >= 2
        default:
            return false
        }
    }

    private func pickForMeDealBreakerMatches(item: MediaItem, dealBreaker: PickForMeDealBreaker) -> Bool {
        guard dealBreaker != .none else { return false }

        let genres = Set(item.genreIDs)
        let text = pickForMeSearchableText(for: item)

        switch dealBreaker {
        case .horror:
            return genres.contains(27) || text.containsAny(["horror", "slasher", "haunted", "demon"])
        case .romanceHeavy:
            return genres.contains(10749) && genres.intersection([28, 12, 878, 9648, 53]).isEmpty
        case .animation:
            return genres.contains(16)
        case .documentary:
            return genres.contains(99) ||
                text.containsAny(["documentary", "docuseries", "nonfiction", "non-fiction", "concert", "live in", "live at", "world tour", "tour film", "live performance", "behind the scenes"]) ||
                (genres.contains(10402) && text.containsAny(["live", "tour", "concert", "performance"]))
        case .war:
            return !genres.intersection(pickForMeWarGenreIDs).isEmpty || text.containsAny(pickForMeWarDealBreakerSignals)
        case .graphicViolence, .sexualContent:
            return false
        case .superhero:
            return text.containsAny(["superhero", "super hero", "marvel", "dc comics", "batman", "superman", "spider-man", "spider man", "avengers", "x-men", "comic book", "mutant", "wolverine", "iron man", "captain america", "thor", "supervillain", "super villain", "gotham", "kryptonite", "professor x", "black widow", "black panther", "deadpool", "aquaman", "wonder woman", "justice league", "guardians of the galaxy", "ant-man", "doctor strange"])
        case .verySad:
            return text.containsAny(["grief", "tragedy", "terminal", "mourning", "devastating", "death of"])
        case .foreignLanguage:
            return item.originalLanguage != nil && item.originalLanguage != "en"
        case .longRuntime:
            guard item.kind == .movie else { return false }
            let minutes = detailsCache[item.key]?.runtime ?? item.runtime
            return (minutes ?? 0) >= 180
        case .sciFi:
            return genres.intersection([878, 10765]).count > 0 || text.containsAny(["sci-fi", "science fiction", "dystopian future", "space station", "artificial intelligence", "robot uprising", "cyberpunk"])
        case .heavyFantasy:
            return genres.contains(14) || text.containsAny(["magic", "sorcery", "wizard", "witch", "dragon", "elf", "dwarf", "hobbit", "enchanted", "dark lord", "mystical realm", "mythical creature"])
        case .none:
            return false
        }
    }

    private func pickForMeKeywordScore(_ text: String, _ keywords: [String]) -> Double {
        Double(keywords.filter { text.contains($0) }.count)
    }

    private func pickForMeHistoricalYearScore(_ text: String) -> Double {
        guard let currentYear = Calendar.current.dateComponents([.year], from: Date()).year else { return 0 }
        let historicalCutoffYear = currentYear - 20
        let pattern = #"\b(1[5-9][0-9]{2}|20[0-9]{2})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)

        for match in matches {
            guard let yearRange = Range(match.range, in: text),
                  let year = Int(text[yearRange]),
                  year <= historicalCutoffYear else {
                continue
            }

            return year <= 1975 ? 2.8 : 1.6
        }

        return 0
    }

    private func pickForMeHistoricalEventScore(genres: Set<Int>, text: String) -> Double {
        let trueEventSignalCount = pickForMeKeywordScore(text, pickForMeHistoricalTrueEventSignals)
        let historicalContextSignalCount = pickForMeKeywordScore(text, pickForMeHistoricalContextSignals)
        let historicalYearScore = pickForMeHistoricalYearScore(text)
        let nonHistoricalDocumentarySignalCount = pickForMeKeywordScore(text, pickForMeNonHistoricalDocumentarySignals)
        let hasHistoricalGenre = !genres.intersection(pickForMeHistoricalGenreIDs).isEmpty
        let isDocumentary = genres.contains(99)

        let hasHistoricalYearEvidence = historicalYearScore > 0 && (trueEventSignalCount > 0 || hasHistoricalGenre)

        if historicalContextSignalCount > 0 || hasHistoricalYearEvidence {
            let keywordScore = trueEventSignalCount * 1.2 + historicalContextSignalCount * 3.4 + (hasHistoricalYearEvidence ? historicalYearScore : 0)
            let genreBonus = hasHistoricalGenre ? 3.4 : 0
            let documentaryPenalty = isDocumentary && nonHistoricalDocumentarySignalCount > 0 ? 5.0 : 0
            let generalDocumentaryPenalty = isDocumentary ? 1.8 : 0
            return keywordScore + genreBonus - documentaryPenalty - generalDocumentaryPenalty
        }

        if hasHistoricalGenre {
            let genreBonus = genres.contains(36) ? 4.0 : 3.2
            let trueEventBonus = min(trueEventSignalCount * 1.2, 2.4)
            let documentaryPenalty = isDocumentary ? 2.5 : 0
            return genreBonus + trueEventBonus - documentaryPenalty
        }

        if isDocumentary {
            return -4.0
        }

        return nonHistoricalDocumentarySignalCount > 0 ? -1.5 : 0
    }

    private func pickForMeSearchableText(for item: MediaItem) -> String {
        "\(item.title) \(item.overview)".lowercased()
    }

    private func pickForMeThematicCandidates(query: String, filter: MediaFilter) async -> [MediaItem] {
        if let cached = pickForMeThematicCache[query] { return cached }
        var results = await pickForMeGroqCandidates(query: query, filter: filter)
        if results.isEmpty {
            #if canImport(FoundationModels)
            results = await pickForMeAppleIntelligenceCandidates(query: query, filter: filter)
            #endif
        }
        pickForMeThematicCache[query] = results
        return results
    }

    private func pickForMeGroqRerank(candidates: [MediaItem], query: String) async -> [MediaKey: Int] {
        let candidateData: [[String: Any]] = candidates.map { item in
            var d: [String: Any] = ["title": item.title]
            if let year = thematicReleaseYear(of: item) { d["year"] = year }
            if !item.overview.isEmpty { d["overview"] = String(item.overview.prefix(180)) }
            return d
        }
        guard let body = try? JSONSerialization.data(withJSONObject: ["query": query, "candidates": candidateData]) else { return [:] }
        var req = URLRequest(url: VestigoBackendConfiguration.baseURL.appending(path: "groq-rerank"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body

        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rankings = json["rankings"] as? [[String: Any]] else { return [:] }

        var result: [MediaKey: Int] = [:]
        for (rankIndex, entry) in rankings.enumerated() {
            guard let title = entry["title"] as? String else { continue }
            let year = entry["year"] as? Int ?? 0
            let norm = normalizeThematicTitle(title)
            if let match = candidates.first(where: {
                normalizeThematicTitle($0.title) == norm ||
                (year > 0 && thematicReleaseYear(of: $0) == year && normalizeThematicTitle($0.title).contains(norm))
            }) {
                if result[match.key] == nil { result[match.key] = rankIndex + 1 }
            }
        }
        return result
    }

    private func pickForMeGroqCandidates(query: String, filter: MediaFilter) async -> [MediaItem] {
        let filterParams: [String]
        switch filter {
        case .movie: filterParams = ["movie"]
        case .tv:    filterParams = ["tv"]
        case .both:  filterParams = ["movie", "tv"]
        }

        // Build requests on MainActor before entering nonisolated task group to avoid Codable actor-isolation warnings
        let requests: [(URLRequest, MediaFilter)] = filterParams.compactMap { filterParam in
            guard let body = try? JSONSerialization.data(withJSONObject: ["query": query, "filter": filterParam]) else { return nil }
            var req = URLRequest(url: VestigoBackendConfiguration.baseURL.appending(path: "thematic-recommend"))
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
            return (req, filterParam == "tv" ? .tv : .movie)
        }

        return await withTaskGroup(of: [MediaItem].self) { group in
            for (req, mediaFilter) in requests {
                group.addTask {
                    do {
                        let (data, response) = try await URLSession.shared.data(for: req)
                        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
                        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let titles = json["titles"] as? [[String: Any]] else { return [] }
                        let suggestions: [(String, Int)] = titles.compactMap { dict in
                            guard let title = dict["title"] as? String else { return nil }
                            return (title, dict["year"] as? Int ?? 0)
                        }
                        return await withTaskGroup(of: MediaItem?.self) { inner in
                            for (title, year) in suggestions {
                                inner.addTask { await self.resolveThematicTitle(title, year: year, filter: mediaFilter) }
                            }
                            var items: [MediaItem] = []
                            for await item in inner { if let item { items.append(item) } }
                            return items
                        }
                    } catch { return [] }
                }
            }
            var all: [MediaItem] = []
            for await items in group { all.append(contentsOf: items) }
            return all
        }
    }

    #if canImport(FoundationModels)
    private func pickForMeAppleIntelligenceCandidates(query: String, filter: MediaFilter) async -> [MediaItem] {
        guard SystemLanguageModel.default.isAvailable else { return [] }
        let session = LanguageModelSession()
        let mediaType: String
        switch filter {
        case .movie: mediaType = "films"
        case .tv: mediaType = "TV shows"
        case .both: mediaType = "films and TV shows"
        }
        let prompt = "List 15 \(query) \(mediaType). Format each title exactly as: Title (Year). One per line. Only the title and year — no other text."
        guard let response = try? await session.respond(to: prompt) else { return [] }
        return await resolveThematicTitles(from: response.content, filter: filter)
    }
    #endif

    private func resolveThematicTitles(from text: String, filter: MediaFilter) async -> [MediaItem] {
        let pattern = try? NSRegularExpression(pattern: #"(.+?)\s*\((\d{4})\)"#)
        let nsText = text as NSString
        let matches = pattern?.matches(in: text, range: NSRange(location: 0, length: nsText.length)) ?? []
        let suggestions: [(String, Int)] = matches.compactMap { match in
            guard match.numberOfRanges >= 3,
                  let titleRange = Range(match.range(at: 1), in: text),
                  let yearRange = Range(match.range(at: 2), in: text),
                  let year = Int(text[yearRange]) else { return nil }
            return (String(text[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines), year)
        }
        return await withTaskGroup(of: MediaItem?.self) { group in
            for (title, year) in suggestions {
                group.addTask { await self.resolveThematicTitle(title, year: year, filter: filter) }
            }
            var results: [MediaItem] = []
            for await item in group { if let item { results.append(item) } }
            return results
        }
    }

    private func resolveThematicTitle(_ title: String, year: Int, filter: MediaFilter) async -> MediaItem? {
        guard let results = try? await tmdb.search(query: title, filter: filter), !results.isEmpty else { return nil }
        let normalized = normalizeThematicTitle(title)
        if let exact = results.first(where: { normalizeThematicTitle($0.title) == normalized }) { return exact }
        if let yearMatch = results.first(where: { thematicReleaseYear(of: $0) == year }) { return yearMatch }
        let first = results[0]
        let firstNorm = normalizeThematicTitle(first.title)
        if firstNorm.contains(normalized) || normalized.contains(firstNorm) { return first }
        return nil
    }

    private func normalizeThematicTitle(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: #"[^a-z0-9 ]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\b(the|a|an)\b"#, with: "", options: .regularExpression)
            .components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func thematicReleaseYear(of item: MediaItem) -> Int? {
        guard let date = item.releaseDate, date.count >= 4 else { return nil }
        return Int(date.prefix(4))
    }

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

    private func searchMediaResults(query: String, filter: MediaFilter) async throws -> [MediaItem] {
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

    private func finalizedSearchResults(_ items: [MediaItem], query: String) -> [MediaItem] {
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

    private func refreshSearchRatingsIfCurrent(_ items: [MediaItem], query: String, requestID: UUID, cacheKey: String) {
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

    private func instantSearchRefinement(for query: String) -> [MediaItem] {
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
    
    private func fuzzySearchQueries(from rawQuery: String) -> [String] {
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

    private func fuzzySearchRelevanceScore(item: MediaItem, query: String) -> Int {
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

    private func searchTitleContinuationScore(title: String, query: String) -> Int {
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

    private func isOrdinalContinuationToken(_ token: String) -> Bool {
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

    private func normalizedSearchText(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .split(separator: " ")
            .joined(separator: " ")
    }

    private func normalizedSearchCacheKey(_ query: String, filter: SearchFilter) -> String {
        let minimumRatingKey = minimumTMDbRatingFilter.map { String($0.rawValue) } ?? "none"
        return "\(filter.rawValue)|\(normalizedSearchText(query))|\(settings.prioritiseEnglish)|\(settings.hideAdultResults)|\(settings.hideWatchedFromSearch)|\(settings.hideLowestAgeRatings)|\(minimumRatingKey)|\(selectedRuntimeFilters.map(\.rawValue).sorted().joined(separator: ","))|\(settings.hideShortFilmsFromSearch)|\(settings.hideExtrasAndPromosFromSearch)"
    }

    private func levenshteinDistance(_ a: String, _ b: String) -> Int {
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
    
    private func enrichSearchResultsWithRuntimeIfNeeded(_ items: [MediaItem]) async -> [MediaItem] {
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

    func loadBasicDetailIfNeeded(_ item: MediaItem) async {
        guard detailsCache[item.key] == nil else { return }
        do {
            detailsCache[item.key] = try await tmdb.detail(for: item, regionCode: settings.streamingRegion.rawValue)
        } catch { }
    }

    private func filterShorts(from trailers: [TrailerVideo]) async -> [TrailerVideo] {
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

    private static func isYouTubeShort(_ key: String) async -> Bool {
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

    private func scheduleWatchmodeRetryIfNeeded(_ item: MediaItem) {
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

    private func universalMoreLikeThis(for item: MediaItem, hideWatched: Bool, limit: Int) async -> [MediaItem] {
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

    private func expandedTMDbSimilarCandidates(for item: MediaItem, detail: MediaDetail) async throws -> [MediaItem] {
        if let cached = tmdbExpandedSimilarCache[item.key] {
            return cached
        }

        let candidates = try await tmdb.keywordDiscoveryCandidates(for: item, keywordIDs: detail.keywordIDs)
            .uniqued()
            .filter { $0.shouldShowInDiscovery && !$0.isUpcoming && $0.key != item.key }
        tmdbExpandedSimilarCache[item.key] = candidates
        return candidates
    }

    private func franchiseRecommendationCandidates(for item: MediaItem) async throws -> [MediaItem] {
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

    private func incrementOMDbDailyCount() {
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
    
    func toggleWatchlist(_ item: MediaItem) {
        library.toggleWatchlist(item)
        saveLocalSoon()
    }
    
    func toggleWatched(_ item: MediaItem, showsRatingPrompt: Bool = true) {
        let wasWatched = library.isWatched(item.key)
        
        library.items[item.key] = item
        library.toggleWatched(item)
        library.recordWatchOrderChange(for: item)
        
        if library.isWatched(item.key) {
            library.setWatchedDateIfUnset(for: item.key)
            removeFromForYouRecommendations(item)
        }
        if library.isWatched(item.key) {
            removeFromCollectionRecommendations(item)
        }
        
        let isNowWatched = library.isWatched(item.key)

        // If the item was watched and is now unwatched, remove it from all collections and clear collection recommendations
        if wasWatched, !isNowWatched {
            for index in library.collections.indices {
                library.collections[index].itemKeys.remove(item.key)
            }
            collectionRecommendations.removeAll()
        }
        
        let shouldRestoreWatchlistIfPromptCancelled = !wasWatched && isNowWatched && settings.removeItemsFromWatchlist && library.isInWatchlist(item.key)

        if !wasWatched, isNowWatched, settings.removeItemsFromWatchlist {
            library.watchlist.remove(item.key)
        }
        
        if showsRatingPrompt && library.isWatched(item.key) {
            requestRatingPromptIfNeeded(for: item, restoreWatchlistOnCancel: shouldRestoreWatchlistIfPromptCancelled)
        }
        
        if isNowWatched {
            generateDynamicCollections(from: item)
        }
        saveLocalSoon()
        
        if isNowWatched {
            let cachedCollectionIDs = Array(collectionRecommendations.keys)
            Task {
                for collectionID in cachedCollectionIDs {
                    await loadCollectionRecommendations(for: collectionID)
                }
            }
        }
    }
    
    func requestRatingPromptIfNeeded(for item: MediaItem, restoreWatchlistOnCancel: Bool = false) {
        guard settings.promptToRateAfterMarkingWatched else { return }
        guard library.isWatched(item.key) else { return }
        guard item.kind == .movie || item.kind == .tv else { return }

        pendingRatingPromptItem = item
        pendingRatingPromptValue = library.ratings[item.key] ?? 0
        pendingRatingPromptMakeFavourite = library.isFavourite(item)
        pendingRatingPromptRestoreWatchlist = restoreWatchlistOnCancel
    }

    func confirmPendingRatingPrompt() {
        guard let item = pendingRatingPromptItem else { return }
        let shouldMakeFavourite = pendingRatingPromptMakeFavourite

        setRating(pendingRatingPromptValue, for: item)
        pendingRatingPromptItem = nil
        pendingRatingPromptValue = 0
        pendingRatingPromptMakeFavourite = false
        pendingRatingPromptRestoreWatchlist = false

        if shouldMakeFavourite, !library.isFavourite(item) {
            requestToggleFavourite(item)
        }
    }

    func dismissPendingRatingPrompt() {
        if let item = pendingRatingPromptItem {
            withdrawPendingRatingPromptWatchedStatus(for: item)
        }

        pendingRatingPromptItem = nil
        pendingRatingPromptValue = 0
        pendingRatingPromptMakeFavourite = false
        pendingRatingPromptRestoreWatchlist = false
    }

    private func withdrawPendingRatingPromptWatchedStatus(for item: MediaItem) {
        guard library.isWatched(item.key) else { return }

        library.toggleWatched(item)
        library.ratings.removeValue(forKey: item.key)
        library.favouriteKeys.remove(item.key)

        if pendingRatingPromptRestoreWatchlist {
            library.watchlist.insert(item.key)
            library.items[item.key] = item
        }

        for index in library.collections.indices {
            library.collections[index].itemKeys.remove(item.key)
        }

        collectionRecommendations.removeAll()
        saveLocalSoon()
        scheduleRecommendationsRefresh()
    }

    private func removeFromForYouRecommendations(_ item: MediaItem) {
        recommendations.removeAll { $0.key == item.key }
        moreLikeLastWatched.removeAll { $0.key == item.key }
        moreLikeFavourite.removeAll { $0.key == item.key }
        fromTopGenre.removeAll { $0.key == item.key }
        trySomethingNewRecommendations.removeAll { $0.key == item.key }
        seriesNext.removeAll { $0.key == item.key }
    }
    
    private func removeFromCollectionRecommendations(_ item: MediaItem) {
        for key in collectionRecommendations.keys {
            collectionRecommendations[key]?.removeAll { $0.key == item.key }
        }
    }
    
    func loadCollectionRecommendations(for collectionID: UUID) async {
        guard let collection = library.collections.first(where: { $0.id == collectionID }) else {
            collectionRecommendations[collectionID] = []
            return
        }

        let collectionItems = collection.itemKeys.compactMap { library.items[$0] }
        guard !collectionItems.isEmpty else {
            collectionRecommendations[collectionID] = []
            return
        }

        let existingKeys = Set(collection.itemKeys)
        var candidates: [MediaItem] = []

        for item in collectionItems.prefix(12) {
            do {
                candidates.append(contentsOf: try await tmdb.sameSeriesOrSimilar(for: item.key))
                candidates.append(contentsOf: try await tmdb.recommendations(for: item.key))
            } catch { }
        }

        let filteredCandidates = candidates
            .uniqued()
            .filter { item in
                (!settings.hideUpcomingFromCollectionRecommendations || !item.isUpcoming) &&
                !existingKeys.contains(item.key) &&
                !library.isWatched(item.key) &&
                (settings.prioritiseEnglish ? ((item.originalLanguage ?? "en") == "en") : true) &&
                (!collection.isDynamic || DynamicCollections.item(item, belongsToCollectionNamed: collection.name))
            }

        let filtered = filteredCandidates
            .sorted { lhs, rhs in
                let lhsRating = ratingSortValue(for: lhs)
                let rhsRating = ratingSortValue(for: rhs)
                if lhsRating != rhsRating {
                    return lhsRating > rhsRating
                }

                return (lhs.releaseDateValue ?? .distantPast) > (rhs.releaseDateValue ?? .distantPast)
            }

        let prepared = preparedResults(filtered, hideWatched: true)
        let visibleItems = await filteredContentCleanupIfNeeded(
            prepared,
            hideShortFilms: settings.hideShortFilmsFromCollectionRecommendations,
            hideExtrasAndPromos: settings.hideExtrasAndPromosFromCollectionRecommendations
        )
        collectionRecommendations[collectionID] = visibleItems
    }
    
    func setWatchedDate(_ date: Date, for item: MediaItem) {
        library.watchedDates[item.key] = date
        saveLocalSoon()
    }

    func clearWatchedDate(for item: MediaItem) {
        library.watchedDates.removeValue(forKey: item.key)
        saveLocalSoon()
    }

    // MARK: - User Avatar

    private var avatarFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("vestigo-user-avatar.jpg")
    }

    func loadUserAvatar() {
        userAvatarData = try? Data(contentsOf: avatarFileURL)
    }

    func saveUserAvatar(_ data: Data) {
        userAvatarData = data
        try? data.write(to: avatarFileURL, options: .atomic)
        schedulePublicProfilePublish()
    }

    #if canImport(UIKit)
    func saveUserAvatar(image: UIImage) {
        let maxDim: CGFloat = 300
        let scale = min(maxDim / image.size.width, maxDim / image.size.height, 1.0)
        let sized: UIImage
        if scale < 1.0 {
            let newSize = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
            let renderer = UIGraphicsImageRenderer(size: newSize)
            sized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        } else {
            sized = image
        }
        if let jpeg = sized.jpegData(compressionQuality: 0.8) {
            saveUserAvatar(jpeg)
        }
    }
    #endif

    func clearUserAvatar() {
        userAvatarData = nil
        try? FileManager.default.removeItem(at: avatarFileURL)
        schedulePublicProfilePublish()
    }

    // MARK: - Recently Viewed

    func recordRecentlyViewed(_ item: MediaItem) {
        var recent = settings.recentlyViewedItems
        recent.removeAll { $0.key == item.key }
        recent.insert(item, at: 0)
        if recent.count > 10 { recent = Array(recent.prefix(10)) }
        settings.recentlyViewedItems = recent
        saveSettings()
    }

    func setRating(_ rating: Double, for item: MediaItem) {
        guard library.isWatched(item.key) else { return }
        library.items[item.key] = item
        library.ratings[item.key] = rating
        generateDynamicCollections(from: item)
        saveLocalSoon()
        scheduleRecommendationsRefresh()
    }

    func requestToggleFavourite(_ item: MediaItem) {
        guard item.kind == .movie || item.kind == .tv else { return }
        guard library.isWatched(item.key) else { return }

        library.toggleFavourite(item)
        saveLocalSoon()
        scheduleRecommendationsRefresh()
    }

    func toggleNeverShowAgain(_ item: MediaItem) {
        guard item.kind == .movie || item.kind == .tv else { return }

        library.toggleNeverShowAgain(item)

        if library.isNeverShowAgain(item.key) {
            removeFromForYouRecommendations(item)
        }

        saveLocalSoon()
        scheduleRecommendationsRefresh()
    }

    func toggleNotInterested(_ item: MediaItem) {
        guard item.kind == .movie || item.kind == .tv else { return }

        library.toggleNotInterested(item)

        if library.isNotInterested(item.key) {
            removeFromForYouRecommendations(item)
        }

        saveLocalSoon()
        scheduleRecommendationsRefresh()
    }

    func confirmFavouriteReplacement() {
        pendingFavouriteReplacement = nil
        showFavouriteReplacementAlert = false
    }

    func currentFavourite(for kind: MediaKind) -> MediaItem? {
        library.favouriteItems.first { $0.kind == kind }
    }

    func toggleEpisode(show: MediaItem, season: Int, episode: Int) {
        library.toggleEpisode(showKey: show.key, season: season, episode: episode)
        saveLocalSoon()
    }

    func markSeason(show: MediaItem, season: Int, episodeCount: Int, watched: Bool) {
        for ep in 1...max(episodeCount, 1) {
            library.setEpisode(showKey: show.key, season: season, episode: ep, watched: watched)
        }
        if watched { library.markWatched(show) }
        saveLocalSoon()
    }

    func addToCollection(_ item: MediaItem, collectionID: UUID) {
        guard let index = library.collections.firstIndex(where: { $0.id == collectionID }) else { return }
        library.collections[index].itemKeys.insert(item.key)
        library.items[item.key] = item
        saveLocalSoon()
    }

    func removeFromCollection(_ item: MediaItem, collectionID: UUID) {
        guard let index = library.collections.firstIndex(where: { $0.id == collectionID }) else { return }
        library.collections[index].itemKeys.remove(item.key)
        saveLocalSoon()
    }

    func createCollection(named name: String, with item: MediaItem? = nil) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        guard !library.collections.contains(where: { $0.name.caseInsensitiveCompare(clean) == .orderedSame }) else { return }
        var collection = MediaCollection(name: clean, isDynamic: false)
        if let item {
            collection.itemKeys.insert(item.key)
            library.items[item.key] = item
        }
        library.collections.append(collection)
        saveLocalSoon()
    }

    func deleteCollection(id: UUID) {
        library.collections.removeAll { $0.id == id }
        collectionRecommendations.removeValue(forKey: id)
        saveLocalSoon()
    }

    func renameCollection(id: UUID, name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        guard let idx = library.collections.firstIndex(where: { $0.id == id }) else { return }
        library.collections[idx].name = clean
        saveLocalSoon()
    }

    private enum ImportMatchOutcome {
        case found(MediaItem)
        case ambiguous([MediaItem])
        case ambiguousYearNotFound([MediaItem])
        case notFound
    }

    func importWatchedText(_ text: String, format: WatchedImportEntry.ImportFormat = .automatic) async -> ImportResult {
        let entries = WatchedImportEntry.report(for: text, format: format).entries
        return await importEntries(entries)
    }

    func importLetterboxdText(_ text: String) async -> ImportResult {
        let entries = WatchedImportEntry.parseLetterboxd(text)
        return await importEntries(entries)
    }

    private func importEntries(_ entries: [WatchedImportEntry]) async -> ImportResult {
        guard !entries.isEmpty else { return ImportResult(notFound: [], ambiguous: []) }

        // Local library index — used only as fallback when TMDb finds nothing
        var localIndex: [String: MediaItem] = [:]
        for item in library.watchedItems {
            let key = WatchedImportEntry.normalizedTitle(item.title) + ":" + (item.kind == .tv ? "s" : "m")
            localIndex[key] = item
        }

        // Group entries by (normalizedTitle:mediaFilter) key — deduplicates network searches
        var entryGroups: [String: [WatchedImportEntry]] = [:]
        var keyOrder: [String] = []
        for entry in entries {
            let norm = WatchedImportEntry.normalizedTitle(entry.title)
            let typeKey = entry.mediaFilter == .movie ? "m" : "s"
            let key = norm + ":" + typeKey
            if entryGroups[key] == nil { keyOrder.append(key) }
            entryGroups[key, default: []].append(entry)
        }

        // Always search TMDb so ambiguous titles always surface the disambiguation popup,
        // even if the title was previously imported and is already in the library.
        var searchOutcomes: [String: ImportMatchOutcome] = [:]
        await withTaskGroup(of: (String, ImportMatchOutcome).self) { group in
            for key in keyOrder {
                let entry = entryGroups[key]![0]
                group.addTask { (key, (try? await self.findImportMatch(for: entry)) ?? .notFound) }
            }
            for await (key, outcome) in group {
                searchOutcomes[key] = outcome
            }
        }

        var notFound: [String] = []
        var ambiguous: [ImportAmbiguity] = []
        for key in keyOrder {
            let groupEntries = entryGroups[key]!
            let primaryEntry = groupEntries[0]
            // Fall back to the local library item only when TMDb finds nothing at all
            let tmdbOutcome = searchOutcomes[key] ?? .notFound
            let outcome: ImportMatchOutcome
            if case .notFound = tmdbOutcome, let local = localIndex[key] {
                outcome = .found(local)
            } else {
                outcome = tmdbOutcome
            }
            switch outcome {
            case .found(let match):
                library.markWatched(match)
                library.recordWatchOrderChange(for: match)
                library.setWatchedDateIfUnset(for: match.key, date: primaryEntry.watchedDate ?? .now)
                if let rating = primaryEntry.rating { library.ratings[match.key] = rating }
                if primaryEntry.isFavourite { library.favouriteKeys.insert(match.key) }
                generateDynamicCollections(from: match)
            case .ambiguous(let candidates):
                ambiguous.append(ImportAmbiguity(entries: groupEntries, candidates: candidates))
            case .ambiguousYearNotFound(let candidates):
                ambiguous.append(ImportAmbiguity(entries: groupEntries, candidates: candidates, yearNotFound: true))
            case .notFound:
                notFound.append(contentsOf: groupEntries.map(\.rawText))
            }
        }

        saveLocalSoon()
        scheduleRecommendationsRefresh()
        return ImportResult(notFound: notFound, ambiguous: ambiguous)
    }

    func commitAmbiguousImport(_ ambiguity: ImportAmbiguity, choices: [MediaItem]) {
        for (index, choice) in choices.enumerated() {
            library.markWatched(choice)
            library.recordWatchOrderChange(for: choice)
            let entry = ambiguity.entries[min(index, ambiguity.entries.count - 1)]
            library.setWatchedDateIfUnset(for: choice.key, date: entry.watchedDate ?? .now)
            if let rating = entry.rating { library.ratings[choice.key] = rating }
            if entry.isFavourite { library.favouriteKeys.insert(choice.key) }
            generateDynamicCollections(from: choice)
        }
        saveLocalSoon()
        scheduleRecommendationsRefresh()
    }

    func prepareExport(format: ExportFormat = .text) {
        let entries = library.watchedItems
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            .map { item in
                WatchedImportEntry.exportLine(
                    for: item,
                    rating: library.ratings[item.key],
                    isFavourite: library.isFavourite(item)
                )
            }

        exportDocument = ExportDocument(text: entries.joined(separator: format.separator))
        exportFormat = format
        showExporter = true
    }

    private func findImportMatch(for entry: WatchedImportEntry) async throws -> ImportMatchOutcome {
        let filter = entry.mediaFilter
        let results = try await tmdb.search(query: entry.title, filter: filter, includeAdult: !settings.hideAdultResults)
        let normalizedTitle = WatchedImportEntry.normalizedTitle(entry.title)

        let filtered = results.filter { $0.kind == .movie || $0.kind == .tv }
        var exactMatches = filtered.filter {
            WatchedImportEntry.matchScore($0.title, normalizedTitle: normalizedTitle) == 100
        }

        if let year = entry.year {
            let yearFiltered = exactMatches.filter { $0.releaseYearInt == year }
            if !yearFiltered.isEmpty {
                exactMatches = yearFiltered
            } else if !exactMatches.isEmpty {
                // Exact title matches exist but none have this year — show popup with year hint
                return .ambiguousYearNotFound(exactMatches)
            }
            // No exact title matches — fall through to partial match + year logic below
        }

        if exactMatches.count > 1 { return .ambiguous(exactMatches) }
        if let one = exactMatches.first { return .found(one) }

        // No exact title match — prefer results with a matching year (handles spelling diffs)
        if let year = entry.year {
            let yearMatches = filtered.filter { $0.releaseYearInt == year }
            if yearMatches.count == 1 { return .found(yearMatches[0]) }
            if yearMatches.count > 1 { return .ambiguous(yearMatches) }
            // Year provided but no result matches it at all
            if !filtered.isEmpty { return .ambiguousYearNotFound(filtered) }
        }

        let best = filtered.sorted { lhs, rhs in
            let l = WatchedImportEntry.matchScore(lhs.title, normalizedTitle: normalizedTitle)
            let r = WatchedImportEntry.matchScore(rhs.title, normalizedTitle: normalizedTitle)
            return l != r ? l > r : lhs.voteAverage > rhs.voteAverage
        }.first

        return best.map { .found($0) } ?? .notFound
    }

    func clearAllData() {
        library = UserLibrary()
        settings = AppSettings()

        searchFilter = settings.defaultSearchFilter
        mediaFilter = settings.defaultHomeFilter
        searchFiltersExpanded = false
        expandedSearchFilterSections.removeAll()
        selectedRuntimeFilters.removeAll()
        selectedDateFilters.removeAll()
        minimumTMDbRatingFilter = nil

        searchText = ""
        searchResults = []
        searchPeopleResults = []

        selectedItem = nil
        selectedPerson = nil
        homePath.removeAll()
        searchPath.removeAll()

        saveLocal()
        Task { await loadHome() }
    }

    func selectTab(_ tab: AppTab) {
        guard tab != selectedTab else {
            reselectCurrentTab()
            return
        }

        tabTransitionDirection = tab.sortIndex > selectedTab.sortIndex ? .forward : .backward
        selectedTab = tab
    }

    func reselectCurrentTab() {
        if selectedTab == .search && searchFieldIsFocused {
            searchFieldIsFocused = false
            return
        }
        if isAtRoot(selectedTab) {
            reloadRoot(for: selectedTab)
        } else {
            resetPath(for: selectedTab)
        }
    }

    func goBack() {
        if selectedPerson != nil {
            selectedPerson = nil
            return
        }

        if selectedItem != nil {
            selectedItem = nil
            return
        }

        switch selectedTab {
        case .home:
            if !homePath.isEmpty { homePath.removeLast() }
        case .search:
            if !searchPath.isEmpty { searchPath.removeLast() }
        case .watchlist, .collections, .friends:
            break
        }
    }

    private func isAtRoot(_ tab: AppTab) -> Bool {
        switch tab {
        case .home:
            return homePath.isEmpty && selectedItem == nil && selectedPerson == nil
        case .search:
            return searchPath.isEmpty && selectedItem == nil && selectedPerson == nil
        case .watchlist, .collections, .friends:
            return selectedItem == nil && selectedPerson == nil
        }
    }

    private func resetPath(for tab: AppTab) {
        selectedItem = nil
        selectedPerson = nil

        switch tab {
        case .home:
            homePath.removeAll()
        case .search:
            searchPath.removeAll()
        case .watchlist, .collections, .friends:
            break
        }
    }

    private func reloadRoot(for tab: AppTab) {
        selectedItem = nil
        selectedPerson = nil

        switch tab {
        case .home:
            homePath.removeAll()
            mediaFilter = settings.defaultHomeFilter
            homeViewMode = .tile
            Task { await loadHome() }
            Task { await loadSmartRecommendations() }

        case .search:
            searchPath.removeAll()
            searchViewMode = .tile
            searchText = ""
            searchResults = []
            searchPeopleResults = []
            searchFieldIsFocused = false
            searchFiltersExpanded = false
            expandedSearchFilterSections.removeAll()
            selectedRuntimeFilters.removeAll()
            selectedDateFilters.removeAll()
            minimumTMDbRatingFilter = nil
            searchFilter = settings.defaultSearchFilter

        case .friends:
            friendsResetToken = UUID()

        case .watchlist:
            sortOption = .tmdbRating
            watchlistResetToken = UUID()
            objectWillChange.send()

        case .collections:
            collectionsResetToken = UUID()
            objectWillChange.send()
        }
    }

    private func generateDynamicCollections(from item: MediaItem) {
        library.items[item.key] = item
        let seriesNames = DynamicCollections.inferredSeriesNames(for: item)
        let broadNames = DynamicCollections.broadCollections(for: item)
        for name in (seriesNames + broadNames) {
            if let index = library.collections.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                library.collections[index].itemKeys.insert(item.key)
            } else {
                var collection = MediaCollection(name: name, isDynamic: true)
                collection.itemKeys.insert(item.key)
                library.collections.append(collection)
            }
        }
    }

    private func loadLocal() {
        library = Storage.load(UserLibrary.self, key: "Vestigo.library") ?? UserLibrary()
        settings = Storage.load(AppSettings.self, key: "Vestigo.settings") ?? AppSettings()
        externalRatingsCache = Storage.load([MediaKey: ExternalRatings].self, key: "Vestigo.externalRatings") ?? [:]
        calendarEventIDs = Storage.load([MediaKey: String].self, key: "Vestigo.calendarEventIDs") ?? [:]
        describeItResultsCache = Storage.load([String: [ThematicSearchResult]].self, key: "Vestigo.describeItCache") ?? [:]
        providerCache = Storage.load([MediaKey: [StreamingOption]].self, key: "Vestigo.providerCache") ?? [:]
        searchFilter = settings.defaultSearchFilter
        mediaFilter = settings.defaultHomeFilter

        // Ensure .recommendations appears before .newReleases (migration for existing installs)
        if let recIdx = settings.homeCarouselOrder.firstIndex(of: .recommendations),
           let newRelIdx = settings.homeCarouselOrder.firstIndex(of: .newReleases),
           recIdx > newRelIdx {
            settings.homeCarouselOrder.remove(at: recIdx)
            let insertAt = settings.homeCarouselOrder.firstIndex(of: .newReleases) ?? min(1, settings.homeCarouselOrder.count)
            settings.homeCarouselOrder.insert(.recommendations, at: insertAt)
        }

        // Ensure all non-forYou sub-carousels are hidden by default for existing installs
        let subCarousels: Set<ForYouCarousel> = [.moreLikeLast, .moreLikeFavourite, .watchlistPicks, .seriesNext]
        if settings.forYouCarouselHidden.isDisjoint(with: subCarousels) {
            settings.forYouCarouselHidden.formUnion(subCarousels)
        }
    }

    private func syncFromCloudOnLaunch() async {
        guard let snapshot = Storage.loadKVSnapshot() else {
            saveLocalSoon()
            return
        }

        let localModifiedAt = Storage.load(Date.self, key: "Vestigo.localSnapshotModifiedAt") ?? .distantPast
        guard snapshot.modifiedAt > localModifiedAt else {
            if localModifiedAt > snapshot.modifiedAt {
                saveLocalSoon()
            }
            return
        }

        applyKVSnapshot(snapshot)
        Storage.save(snapshot.modifiedAt, key: "Vestigo.localSnapshotModifiedAt")
    }

    func handleExternalKVChange() {
        guard let snapshot = Storage.loadKVSnapshot() else { return }
        let localModifiedAt = Storage.load(Date.self, key: "Vestigo.localSnapshotModifiedAt") ?? .distantPast
        guard snapshot.modifiedAt > localModifiedAt else { return }
        applyKVSnapshot(snapshot)
        Storage.save(snapshot.modifiedAt, key: "Vestigo.localSnapshotModifiedAt")
    }

    private func offerStreamingSetupIfNeeded() {
        if !settings.hasSeenStreamingSetup {
            showStreamingSetup = true
        }
    }

    func completeStreamingSetup() {
        settings.hasSeenStreamingSetup = true
        showStreamingSetup = false
        saveLocalSoon()
    }

    func toggleSubscribedService(_ serviceID: String) {
        if settings.subscribedServiceNames.contains(serviceID) {
            settings.subscribedServiceNames.remove(serviceID)
        } else {
            settings.subscribedServiceNames.insert(serviceID)
        }
        saveLocalSoon()
    }

    func saveSettings() {
        saveLocalSoon()
        schedulePublicProfilePublish()
    }

    private func schedulePublicProfilePublish() {
        publishTask?.cancel()
        publishTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let self else { return }
            let result = await self.publicSync.publishProfile(settings: self.settings, library: self.library, avatarData: self.userAvatarData)
            await MainActor.run { self.publishDiagnostic = result }
        }
    }

    func publishPublicProfile() async {
        publishDiagnostic = await publicSync.publishProfile(settings: settings, library: library, avatarData: userAvatarData)
    }

    func loadFriends() async {
        friendsLoading = true
        let (profiles, diagnostic) = await publicSync.fetchFriends(recordIDs: settings.socialConfirmedFriendIDs)
        friends = profiles
        friendsDiagnostic = diagnostic
        friendsLoading = false
    }

    func handleFriendLink(inviteID: String) async {
        guard let result = await publicSync.fetchProfile(byInviteID: inviteID) else {
            pendingFriendAdd = PendingFriendAdd(id: inviteID, name: "this person")
            return
        }
        pendingFriendAdd = PendingFriendAdd(id: result.recordID, name: result.name)
    }

    func addFriend(recordID: String) {
        guard !settings.socialConfirmedFriendIDs.contains(recordID) else {
            pendingFriendAdd = nil
            return
        }
        settings.socialConfirmedFriendIDs.append(recordID)
        saveSettings()
        Task { await loadFriends() }
        pendingFriendAdd = nil
    }

    func removeFriend(recordID: String) {
        settings.socialConfirmedFriendIDs.removeAll { $0 == recordID }
        friends.removeAll { $0.id == recordID }
        saveSettings()
    }

    private func scheduleRecommendationsRefresh() {
        recommendationsRefreshTask?.cancel()
        recommendationsRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.loadSmartRecommendations()
        }
    }

    func savePickForMeRecentSearch(_ answers: PickForMeAnswers) {
        let recent = PickForMeRecentSearch(date: Date(), answers: answers)
        var searches = settings.pickForMeRecentSearches
        searches.removeAll { $0.answers.summaryTags == recent.answers.summaryTags }
        searches.insert(recent, at: 0)
        if searches.count > 10 { searches = Array(searches.prefix(10)) }
        settings.pickForMeRecentSearches = searches
        saveLocalSoon()
    }

    func saveDescribeItRecentSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var searches = settings.describeItRecentSearches
        searches.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        searches.insert(trimmed, at: 0)
        settings.describeItRecentSearches = Array(searches.prefix(10))
        saveLocalSoon()
    }

    func removePickForMeRecentSearch(_ search: PickForMeRecentSearch) {
        settings.pickForMeRecentSearches.removeAll { $0.id == search.id }
        saveLocalSoon()
    }

    func removeDescribeItRecentSearch(_ query: String) {
        settings.describeItRecentSearches.removeAll { $0.caseInsensitiveCompare(query) == .orderedSame }
        saveLocalSoon()
    }

    private func saveLocalSoon() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            await MainActor.run { self?.saveLocal() }
        }
    }

    private func saveLocal() {
        Storage.save(library, key: "Vestigo.library")
        Storage.save(settings, key: "Vestigo.settings")
        Storage.save(externalRatingsCache, key: "Vestigo.externalRatings")
        Storage.save(calendarEventIDs, key: "Vestigo.calendarEventIDs")
        Storage.save(describeItResultsCache.filter { !$0.value.isEmpty }, key: "Vestigo.describeItCache")
        let watchmodeOnly = providerCache.filter { !tmdbFallbackKeys.contains($0.key) }
        Storage.save(watchmodeOnly, key: "Vestigo.providerCache")

        guard !isApplyingCloudSnapshot else { return }

        Storage.saveKVSnapshot(library: library, settings: settings)
    }

    private func applyKVSnapshot(_ snapshot: KVLibrarySnapshot) {
        guard !isApplyingCloudSnapshot else { return }
        isApplyingCloudSnapshot = true
        defer { isApplyingCloudSnapshot = false }
        library = snapshot.library
        settings = snapshot.settings
        searchFilter = settings.defaultSearchFilter
        mediaFilter = settings.defaultHomeFilter
        saveLocal()
    }

    func thematicSearch(query: String, filter: MediaFilter) async throws -> [ThematicSearchResult] {
        let service = ThematicSearchService(tmdb: tmdb)
        return try await service.search(rawQuery: query, filter: filter)
    }
}

