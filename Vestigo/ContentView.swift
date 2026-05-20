import SwiftUI
#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#endif
import Foundation
import Combine
import UniformTypeIdentifiers


// MARK: - App Entry

struct ContentView: View {
    @StateObject private var model = VestigoModel()
    @Namespace private var tabNamespace
    @State private var showSettingsSheet = false

    private var selectedTabBinding: Binding<AppTab> {
        Binding(
            get: { model.selectedTab },
            set: { model.selectTab($0) }
        )
    }

    var body: some View {
        TabView(selection: selectedTabBinding) {
            AppTabRoot(tab: .home, model: model)
                .tabItem {
                    Label(AppTab.home.title, systemImage: AppTab.home.icon)
                }
                .tag(AppTab.home)

            AppTabRoot(tab: .search, model: model)
                .tabItem {
                    Label(AppTab.search.title, systemImage: AppTab.search.icon)
                }
                .tag(AppTab.search)
            
            AppTabRoot(tab: .forYou, model: model)
                .tabItem {
                    Label(AppTab.forYou.title, systemImage: AppTab.forYou.icon)
                }
                .tag(AppTab.forYou)

            AppTabRoot(tab: .watchlist, model: model)
                .tabItem {
                    Label(AppTab.watchlist.title, systemImage: AppTab.watchlist.icon)
                }
                .tag(AppTab.watchlist)

            AppTabRoot(tab: .collections, model: model)
                .tabItem {
                    Label(AppTab.collections.title, systemImage: AppTab.collections.icon)
                }
                .tag(AppTab.collections)
        }
        .tint(model.settings.accentColor)
        #if os(iOS)
        .tabBarMinimizeBehavior(.onScrollDown)
        .background(
            TabBarRetapObserver(selectedTab: model.selectedTab) {
                model.reselectCurrentTab()
            }
        )
        #endif
        .preferredColorScheme(model.settings.appearance == .dark ? .dark : .light)
        .task { await model.bootstrap() }
        .sheet(item: $model.selectedItem) { item in
            DetailView(item: item, model: model)
        }
        .sheet(item: $model.selectedPerson) { person in
            PersonDetailView(person: person, model: model)
        }
        .sheet(isPresented: $showSettingsSheet) {
            SettingsSheetSurface(model: model)
                .presentationBackground(.clear)
                .presentationCornerRadius(54)
        }
        .environment(\.openSettingsSheet, OpenSettingsSheetAction {
            showSettingsSheet = true
        })
        .favouriteReplacementOverlay(model: model)
        .ratingPromptOverlay(model: model)
    }
}

#if os(iOS)
private struct TabBarRetapObserver: UIViewControllerRepresentable {
    let selectedTab: AppTab
    let onRetap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onRetap: onRetap)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()

        DispatchQueue.main.async {
            context.coordinator.attach(from: controller, selectedIndex: selectedTab.sortIndex)
        }

        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.onRetap = onRetap

        DispatchQueue.main.async {
            context.coordinator.attach(from: uiViewController, selectedIndex: selectedTab.sortIndex)
        }
    }

    final class Coordinator: NSObject, UITabBarControllerDelegate {
        var onRetap: () -> Void
        private weak var tabBarController: UITabBarController?
        private var lastSelectedIndex: Int?

        init(onRetap: @escaping () -> Void) {
            self.onRetap = onRetap
        }

        func attach(from viewController: UIViewController, selectedIndex: Int) {
            guard let tabBarController = viewController.tabBarController else { return }

            if self.tabBarController !== tabBarController {
                self.tabBarController = tabBarController
                tabBarController.delegate = self
            }

            lastSelectedIndex = selectedIndex
        }

        func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
            let selectedIndex = tabBarController.selectedIndex

            if selectedIndex == lastSelectedIndex {
                onRetap()
            }

            lastSelectedIndex = selectedIndex
        }
    }
}
#endif

private struct OpenSettingsSheetAction {
    let action: () -> Void

    func callAsFunction() {
        action()
    }
}

private struct OpenSettingsSheetKey: EnvironmentKey {
    static let defaultValue = OpenSettingsSheetAction {}
}

private extension EnvironmentValues {
    var openSettingsSheet: OpenSettingsSheetAction {
        get { self[OpenSettingsSheetKey.self] }
        set { self[OpenSettingsSheetKey.self] = newValue }
    }
}


// MARK: - Root Navigation

private struct AppTabRoot: View {
    let tab: AppTab
    @ObservedObject var model: VestigoModel

    var body: some View {
        Group {
            switch tab {
            case .home:
                ZStack {
                    AppBackground(settings: model.settings)
                        .ignoresSafeArea()

                    NavigationStack(path: $model.homePath) {
                        HomeView(model: model)
                            .background(AppBackground(settings: model.settings).ignoresSafeArea())
                            .navigationDestination(for: SectionRoute.self) { route in
                                FullSectionView(route: route, model: model)
                                    .background(AppBackground(settings: model.settings).ignoresSafeArea())
                            }
                    }
                    .scrollContentBackground(.hidden)
                    #if os(iOS)
                    .toolbarBackground(.hidden, for: .navigationBar)
                    #endif
                    .background(Color.clear)
                }

            case .search:
                ZStack {
                    AppBackground(settings: model.settings)
                        .ignoresSafeArea()

                    NavigationStack(path: $model.searchPath) {
                        SearchView(model: model)
                            .background(AppBackground(settings: model.settings).ignoresSafeArea())
                            .navigationDestination(for: GenreRoute.self) { route in
                                GenreResultsView(route: route, model: model)
                                    .background(AppBackground(settings: model.settings).ignoresSafeArea())
                            }
                    }
                    .scrollContentBackground(.hidden)
                    #if os(iOS)
                    .toolbarBackground(.hidden, for: .navigationBar)
                    #endif
                    .background(Color.clear)
                }
                
            case .forYou:
                ForYouView(model: model)

            case .watchlist:
                WatchlistView(model: model)

            case .collections:
                CollectionsView(model: model)

            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }
}


// MARK: - MediaItem

// Try to find the MediaItem type and add the displayKindLabel computed property.
// If MediaItem is defined elsewhere, this is a placeholder for the property to add there.

extension MediaItem {
    /// Returns a user-visible label for the kind, mapping short movies to "Short film".
    var displayKindLabel: String {
        kind.displayLabel(runtime: runtime)
    }
}

@MainActor
private final class VestigoModel: ObservableObject {
    @Published var selectedTab: AppTab = .home
    @Published var tabTransitionDirection: TabTransitionDirection = .forward
    @Published var mediaFilter: MediaFilter = .both
    @Published var homeViewMode: ViewMode = .tile
    @Published var searchViewMode: ViewMode = .tile
    @Published var watchlistViewMode: ViewMode = .tile
    @Published var collectionViewMode: ViewMode = .tile
    @Published var sortOption: SortOption = .tmdbRating
    
    @Published var searchFiltersExpanded = false
    @Published var expandedSearchFilterSections: Set<SearchFilterSection> = []
    @Published var selectedRuntimeFilters: Set<SearchRuntimeFilter> = []
    @Published var selectedDateFilters: Set<SearchDateFilter> = []
    @Published var minimumTMDbRatingFilter: SearchRatingFilter? = .one
    @Published var searchText = ""
    @Published var searchFilter: SearchFilter = .movie
    @Published var searchFieldIsFocused = false
    @Published var trending: [MediaItem] = []
    @Published var popular: [MediaItem] = []
    @Published var newReleases: [MediaItem] = []
    @Published var upcoming: [MediaItem] = []
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
    @Published var providerCache: [MediaKey: [StreamingOption]] = [:]
    @Published var personCreditsCache: [Int: [MediaItem]] = [:]
    @Published var collectionRecommendations: [UUID: [MediaItem]] = [:]
    @Published var pendingRatingPromptItem: MediaItem?
    @Published var pendingRatingPromptValue: Double = 0
    @Published var pendingRatingPromptMakeFavourite = false
    
    @Published var library = UserLibrary()
    @Published var settings = AppSettings()
    @Published var selectedItem: MediaItem?
    @Published var selectedPerson: PersonSummary?
    @Published var homePath: [SectionRoute] = []
    @Published var searchPath: [GenreRoute] = []
    @Published var isLoading = false
    @Published var errorText: String?
    @Published var exportDocument = ExportDocument(text: "")
    @Published var showExporter = false
    @Published var pendingFavouriteReplacement: MediaItem?
    @Published var showFavouriteReplacementAlert = false
    @Published var forYouResetToken = UUID()
    @Published var watchlistResetToken = UUID()
    @Published var collectionsResetToken = UUID()
    
    private let tmdb = TMDbService()
    private let streaming = StreamingAvailabilityService()
    private var searchTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    
    var filteredSearchResults: [MediaItem] {
        searchResults.filter { item in
            guard searchFilter != .people else { return true }
            
            if let minimumTMDbRatingFilter, item.voteAverage < minimumTMDbRatingFilter.minimumRating {
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
        guard let runtime = detailsCache[item.key]?.runtime else { return false }

        return runtime > 0 && runtime <= 40
    }

    func filteredShortFilmsIfNeeded(_ items: [MediaItem], enabled: Bool) async -> [MediaItem] {
        guard enabled else { return items }

        var filtered: [MediaItem] = []

        for item in items {
            guard item.kind == .movie else {
                filtered.append(item)
                continue
            }

            if detailsCache[item.key] == nil {
                await loadDetail(item)
            }

            if !shouldHideAsShortFilm(item, enabled: enabled) {
                filtered.append(item)
            }
        }

        return filtered
    }
    
    func preparedResults(_ items: [MediaItem], hideWatched: Bool = false) -> [MediaItem] {
        filteredForWatchedPreference(
            filteredForAnimePreference(
                prioritisedForLanguage(items)
            ),
            hideWatched: hideWatched
        )
    }
    
    func playSheetDismissHaptic() {
    #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    #endif
    }
    
    func clearSearchFilters() {
        selectedRuntimeFilters.removeAll()
        selectedDateFilters.removeAll()
        minimumTMDbRatingFilter = nil
        refreshRuntimeFilteredSearchIfNeeded()
    }
    
    func bootstrap() async {
        loadLocal()
        await loadHome()
    }
    
    func loadHome() async {
        isLoading = true
        errorText = nil
        do {
            async let tr = tmdb.trending(filter: mediaFilter)
            async let pop = tmdb.popular(filter: mediaFilter)
            async let now = tmdb.newReleases(filter: mediaFilter)
            async let soon = tmdb.upcoming(filter: mediaFilter)
            let today = Calendar.current.startOfDay(for: Date())
            let realUpcoming = (try await soon).filter { item in
                guard let releaseDate = item.releaseDateValue else { return false }
                return releaseDate > today
            }

            let preparedTrending = preparedResults(try await tr, hideWatched: settings.hideWatchedFromHome)
            let preparedPopular = preparedResults(try await pop, hideWatched: settings.hideWatchedFromHome)
            let preparedNewReleases = preparedResults(try await now, hideWatched: settings.hideWatchedFromHome)
            let preparedUpcoming = preparedResults(realUpcoming, hideWatched: settings.hideWatchedFromHome)

            trending = await filteredShortFilmsIfNeeded(preparedTrending, enabled: settings.hideShortFilmsFromHome)
            popular = await filteredShortFilmsIfNeeded(preparedPopular, enabled: settings.hideShortFilmsFromHome)
            newReleases = await filteredShortFilmsIfNeeded(preparedNewReleases, enabled: settings.hideShortFilmsFromHome)
            upcoming = await filteredShortFilmsIfNeeded(preparedUpcoming, enabled: settings.hideShortFilmsFromHome)
            await loadSmartRecommendations()
        } catch {
            if LoadErrorFilter.shouldIgnore(error) {
                return
            }
            errorText = error.localizedDescription
        }
        isLoading = false
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
        
        func relatedResults(_ items: [MediaItem], seed: MediaItem) -> [MediaItem] {
            var results = items
                .uniqued()
                .filter { item in
                    !item.isUpcoming && !library.isWatched(item.key)
                }
            
            if settings.prioritiseEnglish {
                results = results.filter { item in
                    (item.originalLanguage ?? "en") == "en"
                }
            }
            
            return results.sortedBySimilarity(to: seed)
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
                
                return lhs.voteAverage > rhs.voteAverage
            }
            .prefix(historyLimit)
        
        var scoredRecommendations: [MediaKey: (item: MediaItem, score: Double)] = [:]
        var nextItems: [MediaItem] = []
        
        for record in rankedHistory {
            let weight = historyWeight(for: record)
            
            do {
                let rec = try await tmdb.recommendations(for: record.key)
                
                for (index, candidate) in rec.enumerated() {
                    guard !library.isWatched(candidate.key) else { continue }
                    
                    let positionScore = 1.0 / (1.0 + Double(index) * 0.08)
                    let similarityBoost = genreSimilarity(candidate, record) * (0.35 + normalizedStrength * 0.45)
                    let tmdbBoost = min(candidate.voteAverage, 10) * 0.025
                    let score = (positionScore + similarityBoost + tmdbBoost) * weight
                    
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
                
                if lhs.item.voteAverage != rhs.item.voteAverage {
                    return lhs.item.voteAverage > rhs.item.voteAverage
                }
                
                return (lhs.item.releaseDateValue ?? .distantPast) > (rhs.item.releaseDateValue ?? .distantPast)
            }
            .map(\.item)
        
        let visibleRecommendations = preparedResults(
            sortedRecommendations.filter { !library.isWatched($0.key) },
            hideWatched: true
        )
        recommendations = await filteredShortFilmsIfNeeded(
            visibleRecommendations,
            enabled: settings.hideShortFilmsFromRecommended
        )
        seriesNext = await filteredShortFilmsIfNeeded(
            preparedResults(nextItems.uniqued().filter { !library.isWatched($0.key) }, hideWatched: true),
            enabled: settings.hideShortFilmsFromRecommended
        )

        if let lastWatched = library.lastWatchedItem {
            do {
                let prepared = preparedResults(
                    relatedResults(try await tmdb.recommendations(for: lastWatched.key), seed: lastWatched),
                    hideWatched: true
                )
                moreLikeLastWatched = await filteredShortFilmsIfNeeded(
                    prepared,
                    enabled: settings.hideShortFilmsFromRecommended
                )
            } catch {
                moreLikeLastWatched = []
            }
        } else {
            moreLikeLastWatched = []
        }

        var favouriteRecommendations: [MediaItem] = []
        for favourite in [library.favouriteMovie, library.favouriteSeries].compactMap({ $0 }) {
            do {
                favouriteRecommendations.append(contentsOf: try await tmdb.recommendations(for: favourite.key))
            } catch { }
        }

        if let primaryFavouriteSeed = [library.favouriteMovie, library.favouriteSeries].compactMap({ $0 }).first {
            let prepared = preparedResults(
                relatedResults(favouriteRecommendations, seed: primaryFavouriteSeed),
                hideWatched: true
            )
            moreLikeFavourite = await filteredShortFilmsIfNeeded(
                prepared,
                enabled: settings.hideShortFilmsFromRecommended
            )
        } else {
            moreLikeFavourite = []
        }

        let watchedGenreIDs = watchedHistory.flatMap(\.genreIDs)
        if let topGenreID = watchedGenreIDs.frequencySorted().first {
            let preparedTopGenre = visibleRecommendations
                .filter { !$0.isUpcoming && $0.genreIDs.contains(topGenreID) }
                .filter { settings.prioritiseEnglish ? (($0.originalLanguage ?? "en") == "en") : true }

            fromTopGenre = await filteredShortFilmsIfNeeded(
                preparedTopGenre,
                enabled: settings.hideShortFilmsFromRecommended
            )
        } else {
            fromTopGenre = []
        }

        let watchedGenreSet = Set(watchedGenreIDs)
        let preparedTrySomethingNew = preparedResults(
            (popular + trending + newReleases)
                .uniqued()
                .filter { item in
                    !item.isUpcoming &&
                    !library.isWatched(item.key) &&
                    watchedGenreSet.isDisjoint(with: Set(item.genreIDs)) &&
                    (settings.prioritiseEnglish ? ((item.originalLanguage ?? "en") == "en") : true)
                }
                .sorted { lhs, rhs in
                    if lhs.voteAverage != rhs.voteAverage {
                        return lhs.voteAverage > rhs.voteAverage
                    }

                    return (lhs.releaseDateValue ?? .distantPast) > (rhs.releaseDateValue ?? .distantPast)
                },
            hideWatched: true
        )

        trySomethingNewRecommendations = await filteredShortFilmsIfNeeded(
            preparedTrySomethingNew,
            enabled: settings.hideShortFilmsFromRecommended
        )
    }
    
    func updateSearch() {
        searchTask?.cancel()
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = []
            searchPeopleResults = []
            return
        }
        
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard let self, !Task.isCancelled else { return }
            do {
                if self.searchFilter == .people {
                    let people = try await tmdb.searchPeople(query: query, includeAdult: !self.settings.hideAdultResults)
                    await MainActor.run {
                        self.searchPeopleResults = people
                        self.searchResults = []
                    }
                } else if let filter = self.searchFilter.mediaFilter {
                    let searchQueries = self.fuzzySearchQueries(from: query)
                    var collectedResults: [MediaItem] = []

                    for searchQuery in searchQueries {
                        collectedResults.append(contentsOf: try await tmdb.search(query: searchQuery, filter: filter, includeAdult: !self.settings.hideAdultResults))
                        collectedResults.append(contentsOf: try await tmdb.contextualSearch(query: searchQuery, filter: filter, includeAdult: !self.settings.hideAdultResults))
                    }

                    let baseResults = preparedResults(
                        collectedResults
                            .uniqued()
                            .sorted { lhs, rhs in
                                let lhsScore = self.fuzzySearchRelevanceScore(item: lhs, query: query)
                                let rhsScore = self.fuzzySearchRelevanceScore(item: rhs, query: query)

                                if lhsScore != rhsScore {
                                    return lhsScore > rhsScore
                                }

                                if lhs.voteAverage != rhs.voteAverage {
                                    return lhs.voteAverage > rhs.voteAverage
                                }

                                return (lhs.releaseDateValue ?? .distantPast) > (rhs.releaseDateValue ?? .distantPast)
                            },
                        hideWatched: self.settings.hideWatchedFromSearch
                    )
                    
                    let enrichedResults: [MediaItem]
                    if !self.selectedRuntimeFilters.isEmpty {
                        enrichedResults = await self.enrichSearchResultsWithRuntimeIfNeeded(baseResults)
                    } else {
                        enrichedResults = baseResults
                    }
                    
                    let visibleResults = await self.filteredShortFilmsIfNeeded(
                        enrichedResults,
                        enabled: self.settings.hideShortFilmsFromSearch
                    )

                    await MainActor.run {
                        self.searchResults = visibleResults
                        self.searchPeopleResults = []
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
        let queryTokens = query
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count >= 2 }

        guard !queryTokens.isEmpty else { return 0 }

        let cleanQuery = query.lowercased()
        let title = item.title.lowercased()
        let overview = item.overview.lowercased()
        var score = 0

        if title == cleanQuery {
            score += 120
        }

        if title.contains(cleanQuery) {
            score += 80
        }

        for token in queryTokens {
            if title.contains(token) {
                score += 18
            } else if overview.contains(token) {
                score += 6
            }
        }

        let titleTokens = title
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
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

        score += Int(item.voteAverage * 2)
        return score
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
                let detail = try await tmdb.detail(for: item)
                detailsCache[item.key] = detail
                enriched.append(item.withRuntime(detail.runtime))
            } catch {
                enriched.append(item)
            }
        }
        
        return enriched
    }
    
    func loadGenre(_ genre: GenreDefinition, filter: MediaFilter = .both, sort: GenreSort = .tmdbRating) async {
        let cacheKey = genreCacheKey(genreID: genre.tmdbID, filter: filter, sort: sort)

        do {
            let items = try await tmdb.discover(
                genreID: genre.tmdbID,
                filter: filter,
                sort: sort
            )

            let preparedItems = preparedResults(items, hideWatched: settings.hideWatchedFromSearch)
            let visibleItems = await filteredShortFilmsIfNeeded(preparedItems, enabled: settings.hideShortFilmsFromSearch)

            await MainActor.run {
                genreResults[cacheKey] = visibleItems
            }
        } catch {
            await MainActor.run {
                genreResults[cacheKey] = []
            }
        }
    }
    
    func genreCacheKey(genreID: Int, filter: MediaFilter = .both, sort: GenreSort = .tmdbRating) -> String {
        "\(genreID)-category-\(filter.rawValue)-\(sort.rawValue)"
    }
    
    func loadDetail(_ item: MediaItem) async {
        if detailsCache[item.key] == nil {
            do { detailsCache[item.key] = try await tmdb.detail(for: item) } catch { }
        }
        if providerCache[item.key] == nil {
            do {
                providerCache[item.key] = try await streaming.providers(for: item)
            } catch {
                providerCache[item.key] = []
            }
        }
    }
    
    func loadPersonCredits(_ person: PersonSummary) async {
        guard personCreditsCache[person.id] == nil else { return }
        do {
            personCreditsCache[person.id] = try await tmdb.personCredits(personID: person.id)
        } catch {
            personCreditsCache[person.id] = []
        }
    }
    
    func toggleWatchlist(_ item: MediaItem) {
        library.toggleWatchlist(item)
        saveLocalSoon()
    }
    
    func toggleWatched(_ item: MediaItem) {
        let wasWatched = library.isWatched(item.key)
        
        library.items[item.key] = item
        library.toggleWatched(item)
        library.recordWatchOrderChange(for: item)
        
        if library.isWatched(item.key) {
            removeFromForYouRecommendations(item)
        }
        if library.isWatched(item.key) {
            removeFromCollectionRecommendations(item)
        }
        
        let isNowWatched = library.isWatched(item.key)
        
        if !wasWatched, isNowWatched, settings.removeItemsFromWatchlist {
            library.watchlist.remove(item.key)
        }
        
        if library.isWatched(item.key) {
            requestRatingPromptIfNeeded(for: item)
        }
        
        generateDynamicCollections(from: item)
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
    
    func requestRatingPromptIfNeeded(for item: MediaItem) {
        guard settings.promptToRateAfterMarkingWatched else { return }
        guard library.isWatched(item.key) else { return }
        guard item.kind == .movie || item.kind == .tv else { return }

        pendingRatingPromptItem = item
        pendingRatingPromptValue = library.ratings[item.key] ?? 0
        pendingRatingPromptMakeFavourite = library.isFavourite(item)
    }

    func confirmPendingRatingPrompt() {
        guard let item = pendingRatingPromptItem else { return }
        let shouldMakeFavourite = pendingRatingPromptMakeFavourite

        setRating(pendingRatingPromptValue, for: item)
        pendingRatingPromptItem = nil
        pendingRatingPromptValue = 0
        pendingRatingPromptMakeFavourite = false

        if shouldMakeFavourite, !library.isFavourite(item) {
            requestToggleFavourite(item)
        }
    }

    func dismissPendingRatingPrompt() {
        pendingRatingPromptItem = nil
        pendingRatingPromptValue = 0
        pendingRatingPromptMakeFavourite = false
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

        let collectionGenreIDs = Set(collectionItems.flatMap(\.genreIDs))

        let filtered = candidates
            .uniqued()
            .filter { item in
                (!settings.hideUpcomingFromCollectionRecommendations || !item.isUpcoming) &&
                !existingKeys.contains(item.key) &&
                !library.isWatched(item.key) &&
                (settings.prioritiseEnglish ? ((item.originalLanguage ?? "en") == "en") : true) &&
                (collectionGenreIDs.isEmpty || !collectionGenreIDs.isDisjoint(with: Set(item.genreIDs)))
            }
            .sorted { lhs, rhs in
                if lhs.voteAverage != rhs.voteAverage {
                    return lhs.voteAverage > rhs.voteAverage
                }

                return (lhs.releaseDateValue ?? .distantPast) > (rhs.releaseDateValue ?? .distantPast)
            }

        let prepared = preparedResults(filtered, hideWatched: true)
        let visibleItems = await filteredShortFilmsIfNeeded(
            prepared,
            enabled: settings.hideShortFilmsFromCollectionRecommendations
        )
        collectionRecommendations[collectionID] = visibleItems
    }
    
    func setRating(_ rating: Double, for item: MediaItem) {
        guard library.isWatched(item.key) else { return }
        library.items[item.key] = item
        library.ratings[item.key] = rating
        generateDynamicCollections(from: item)
        saveLocalSoon()
        Task { await loadSmartRecommendations() }
    }
    
    func requestToggleFavourite(_ item: MediaItem) {
        guard item.kind == .movie || item.kind == .tv else { return }
        guard library.isWatched(item.key) else { return }

        if library.isFavourite(item) {
            library.clearFavourite(for: item.kind)
            saveLocalSoon()
            objectWillChange.send()
            return
        }

        if let current = currentFavourite(for: item.kind), current.key != item.key {
            if settings.warnBeforeReplacingFavourite {
                pendingFavouriteReplacement = item
                showFavouriteReplacementAlert = true
                objectWillChange.send()
                return
            } else {
                library.setFavourite(item)
                saveLocalSoon()
                objectWillChange.send()
                return
            }
        }

        library.setFavourite(item)
        saveLocalSoon()
        objectWillChange.send()
    }

    func confirmFavouriteReplacement() {
        guard let item = pendingFavouriteReplacement else { return }

        library.setFavourite(item)
        pendingFavouriteReplacement = nil
        showFavouriteReplacementAlert = false
        saveLocalSoon()
        objectWillChange.send()
    }

    func currentFavourite(for kind: MediaKind) -> MediaItem? {
        library.favouriteItem(for: kind)
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

    func importWatchedText(_ text: String) async {
        let titles = text
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for title in titles {
            do {
                if let first = try await tmdb.search(query: title, filter: .both, includeAdult: !settings.hideAdultResults).first {
                    library.markWatched(first)
                    library.recordWatchOrderChange(for: first)
                    generateDynamicCollections(from: first)
                }
            } catch { }
        }
        saveLocalSoon()
    }

    func prepareExport() {
        let lines = library.watchedItems
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            .map { "\($0.title) (\($0.displayKindLabel), \($0.releaseYearText))" }
            .joined(separator: "\n")
        exportDocument = ExportDocument(text: lines)
        showExporter = true
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
        minimumTMDbRatingFilter = .one

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
        case .forYou, .watchlist, .collections:
            break
        }
    }

    private func isAtRoot(_ tab: AppTab) -> Bool {
        switch tab {
        case .home:
            return homePath.isEmpty && selectedItem == nil && selectedPerson == nil
        case .search:
            return searchPath.isEmpty && selectedItem == nil && selectedPerson == nil
        case .forYou, .watchlist, .collections:
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
        case .forYou, .watchlist, .collections:
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
            minimumTMDbRatingFilter = .one
            searchFilter = settings.defaultSearchFilter

        case .forYou:
            forYouResetToken = UUID()
            Task { await loadSmartRecommendations() }

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
        searchFilter = settings.defaultSearchFilter
        mediaFilter = settings.defaultHomeFilter
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
    }
}

private extension View {
    func favouriteReplacementOverlay(model: VestigoModel) -> some View {
        overlay {
            if model.showFavouriteReplacementAlert,
               let candidate = model.pendingFavouriteReplacement,
               let current = model.currentFavourite(for: candidate.kind) {
                FavouriteReplacementOverlay(
                    current: current,
                    candidate: candidate,
                    cancel: {
                        model.pendingFavouriteReplacement = nil
                        model.showFavouriteReplacementAlert = false
                    },
                    replace: {
                        model.confirmFavouriteReplacement()
                    }
                )
            }
        }
    }
}

private struct FavouriteReplacementOverlay: View {
    let current: MediaItem
    let candidate: MediaItem
    let cancel: () -> Void
    let replace: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.34)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                Text("Replace favourite?")
                    .font(.title3.bold())
                    .foregroundStyle(.primary)

                Text("You can only have one favourite \(candidate.displayKindLabel.lowercased()). \(current.title) will no longer be marked favourite.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button("Cancel") {
                        cancel()
                    }
                    .buttonStyle(.plain)
                    .font(.headline.bold())
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .liquidGlass(cornerRadius: 22)

                    Button("Replace") {
                        replace()
                    }
                    .buttonStyle(.plain)
                    .font(.headline.bold())
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .liquidGlass(cornerRadius: 22)
                }
            }
            .padding(18)
            .frame(maxWidth: 330)
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.black.opacity(0.42))
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1.1)
            }
            .padding(.horizontal, 26)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
        .zIndex(999)
    }
}


// MARK: - Home

private struct HomeView: View {
    @ObservedObject var model: VestigoModel
    @Environment(\.openSettingsSheet) private var openSettingsSheet
    
    var body: some View {
        BaseScreen(
            title: "Vestigo",
            filter: $model.mediaFilter,
            settings: model.settings,
            headerAccessory: AnyView(
                Button {
                    openSettingsSheet()
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(width: 42, height: 42)
                        .liquidGlass(cornerRadius: 21)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
            )
        ) {
            VStack(spacing: 22) {
                if let error = model.errorText {
                    StatusBubble(title: "Load error", text: error)
                }

                FilterPills(filter: $model.mediaFilter, options: [.movie, .tv, .both]) {
                    Task { await model.loadHome() }
                }

                if !model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    EmptyView()
                } else {
                    MediaSection(title: "Trending now", items: model.trending, hideWatchedForUpcoming: false, model: model) {
                        model.homePath.append(.trending)
                    }

                    MediaSection(title: "Popular", items: model.popular, hideWatchedForUpcoming: false, model: model) {
                        model.homePath.append(.popular)
                    }

                    MediaSection(title: "New releases", items: model.newReleases, hideWatchedForUpcoming: false, model: model) {
                        model.homePath.append(.newReleases)
                    }

                    if model.settings.showUpcomingReleases, !model.upcoming.isEmpty {
                        MediaSection(title: "Upcoming releases", items: model.upcoming, hideWatchedForUpcoming: true, model: model) {
                            model.homePath.append(.upcoming)
                        }
                    }
                }
            }
        }
        .onChange(of: model.mediaFilter) { _, _ in Task { await model.loadHome() } }
    }
}

private struct FullSectionView: View {
    let route: SectionRoute
    @ObservedObject var model: VestigoModel

    var items: [MediaItem] {
        switch route {
        case .trending: return model.trending
        case .popular: return model.popular
        case .newReleases: return model.newReleases
        case .upcoming: return model.upcoming
        }
    }

    var body: some View {
        BaseScreen(title: route.title, filter: $model.mediaFilter, settings: model.settings) {
            MediaGridOrList(items: items, hideWatchedForUpcoming: route == .upcoming, model: model)
        }
    }
}

// MARK: - Search

private struct SearchView: View {
    @ObservedObject var model: VestigoModel
    @State private var searchHistory: [String] = []
    @FocusState private var searchIsFocused: Bool
    private let maxSearchHistoryCount = 8
    
    var body: some View {
        BaseScreen(title: "Search", filter: .constant(model.searchFilter.mediaFilter ?? .movie), settings: model.settings) {
            VStack(spacing: 18) {
                SearchBubble(text: $model.searchText, isFocused: $searchIsFocused) {
                    commitSearchInput()
                }
                .onChange(of: model.searchText) { _, _ in model.updateSearch() }
                .onChange(of: searchIsFocused) { _, newValue in
                    if !newValue {
                        commitSearchInput()
                    } else {
                        model.searchFieldIsFocused = true
                    }
                }
                if !model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    SearchFilterPills(filter: $model.searchFilter) {
                        model.updateSearch()
                    }

                    if model.searchFilter != .people {
                        SearchFiltersPanel(model: model)
                    }
                }

                if model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if !searchHistory.isEmpty {
                        SearchHistoryList(entries: searchHistory) { entry in
                            model.searchText = entry
                            model.updateSearch()
                        } clearEntry: { entry in
                            searchHistory.removeAll { $0 == entry }
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Genres")
                            .sectionTitle()
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                            ForEach(GenreDefinition.all) { genre in
                                Button {
                                    searchIsFocused = false
                                    model.searchFieldIsFocused = false
                                    model.searchPath.append(GenreRoute(genre: genre))
                                } label: {
                                    GenreIconTile(genre: genre)
                                }
                                .buttonStyle(.plain)
                                .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            }
                        }
                    }
                } else {
                    if model.searchFilter == .people {
                        PeopleSearchResults(people: model.searchPeopleResults, model: model)
                    } else {
                        MediaGridOrList(items: model.filteredSearchResults, hideWatchedForUpcoming: false, model: model)
                    }
                }
            }
        }
    }
    
    private func commitSearchInput() {
        searchIsFocused = false
        model.searchFieldIsFocused = false
        model.searchText = model.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        saveCurrentSearchToHistory()
        model.updateSearch()
    }
    
    private func saveCurrentSearchToHistory() {
        let trimmed = model.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        searchHistory.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        searchHistory.insert(trimmed, at: 0)

        if searchHistory.count > maxSearchHistoryCount {
            searchHistory = Array(searchHistory.prefix(maxSearchHistoryCount))
        }
    }
}

private struct SearchHistoryList: View {
    let entries: [String]
    let selectEntry: (String) -> Void
    let clearEntry: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent searches")
                .sectionTitle()

            VStack(spacing: 8) {
                ForEach(entries, id: \.self) { entry in
                    HStack(spacing: 10) {
                        Button {
                            selectEntry(entry)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.caption.bold())
                                Text(entry)
                                    .font(.subheadline.bold())
                                    .lineLimit(1)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Button {
                            clearEntry(entry)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 42)
                    .liquidGlass(cornerRadius: 18)
                }
            }
        }
    }
}

private struct SearchFilterPills: View {
    @Binding var filter: SearchFilter
    let onChange: () -> Void

    var body: some View {
        Picker("Search type", selection: $filter) {
            ForEach(SearchFilter.allCases) { item in
                Text(item.title).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .liquidGlass(cornerRadius: 18)
        .onChange(of: filter) { _, _ in
            onChange()
        }
    }
}

private struct GenreSortPicker: View {
    @Binding var sort: GenreSort
    let onChange: () -> Void

    var body: some View {
        Picker("Sort", selection: $sort) {
            ForEach(GenreSort.allCases) { item in
                Text(item.title).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .liquidGlass(cornerRadius: 18)
        .onChange(of: sort) { _, _ in
            onChange()
        }
    }
}

private struct SearchFiltersPanel: View {
    @ObservedObject var model: VestigoModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                    model.searchFiltersExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Label(filterButtonTitle, systemImage: "line.3.horizontal.decrease.circle")
                        .font(.caption.bold())

                    Spacer(minLength: 0)

                    if model.searchFiltersExpanded {
                        Button {
                            model.clearSearchFilters()
                        } label: {
                            Text("Clear all")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                    }

                    Image(systemName: "chevron.down")
                        .font(.caption.bold())
                        .rotationEffect(.degrees(model.searchFiltersExpanded ? 180 : 0))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .frame(height: 34)
            }
            .buttonStyle(.plain)
            .focusable(false)

            if model.searchFiltersExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    runtimeSection
                    ratingSection
                    dateSection
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(3)
        .liquidGlass(cornerRadius: 18)
    }

    private var filterButtonTitle: String {
        let count = model.activeSearchFilterCount
        return count == 0 ? "Filters" : "Filters (\(count))"
    }

    private var runtimeSection: some View {
        SearchFilterDisclosureSection(
            section: .runtime,
            expandedSections: $model.expandedSearchFilterSections,
            summary: runtimeSummary
        ) {
            SearchChipWrap {
                ForEach(SearchRuntimeFilter.allCases) { filter in
                    SearchFilterChip(
                        title: filter.title,
                        isSelected: model.selectedRuntimeFilters.contains(filter)
                    ) {
                        if model.selectedRuntimeFilters.contains(filter) {
                            model.selectedRuntimeFilters.remove(filter)
                        } else {
                            model.selectedRuntimeFilters.insert(filter)
                        }

                        model.refreshRuntimeFilteredSearchIfNeeded()
                    }
                }
            }
        }
    }

    private var ratingSection: some View {
        SearchFilterDisclosureSection(
            section: .rating,
            expandedSections: $model.expandedSearchFilterSections,
            summary: ratingSummary
        ) {
            SearchChipWrap {
                ForEach(SearchRatingFilter.allCases) { filter in
                    SearchFilterChip(
                        title: filter.title,
                        isSelected: model.minimumTMDbRatingFilter == filter
                    ) {
                        if model.minimumTMDbRatingFilter == filter {
                            model.minimumTMDbRatingFilter = nil
                        } else {
                            model.minimumTMDbRatingFilter = filter
                        }
                    }
                }
            }
        }
    }

    private var dateSection: some View {
        SearchFilterDisclosureSection(
            section: .date,
            expandedSections: $model.expandedSearchFilterSections,
            summary: dateSummary
        ) {
            SearchChipWrap {
                ForEach(SearchDateFilter.allCases) { filter in
                    SearchFilterChip(
                        title: filter.title,
                        isSelected: model.selectedDateFilters.contains(filter)
                    ) {
                        if model.selectedDateFilters.contains(filter) {
                            model.selectedDateFilters.remove(filter)
                        } else {
                            model.selectedDateFilters.insert(filter)
                        }
                    }
                }
            }
        }
    }

    private var runtimeSummary: String? {
        guard !model.selectedRuntimeFilters.isEmpty else { return nil }

        return SearchRuntimeFilter.allCases
            .filter { model.selectedRuntimeFilters.contains($0) }
            .map(\.title)
            .joined(separator: ", ")
    }

    private var ratingSummary: String? {
        model.minimumTMDbRatingFilter?.title
    }

    private var dateSummary: String? {
        guard !model.selectedDateFilters.isEmpty else { return nil }

        return SearchDateFilter.allCases
            .filter { model.selectedDateFilters.contains($0) }
            .map(\.title)
            .joined(separator: ", ")
    }
}

private struct SearchFilterDisclosureSection<Content: View>: View {
    let section: SearchFilterSection
    @Binding var expandedSections: Set<SearchFilterSection>
    let summary: String?
    @ViewBuilder let content: Content

    private var isExpanded: Bool {
        expandedSections.contains(section)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    if isExpanded {
                        expandedSections.remove(section)
                    } else {
                        expandedSections.insert(section)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(summary == nil ? section.title : "\(section.title) • \(summary!)")
                        .font(.caption.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.down")
                        .font(.caption.bold())
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(.white.opacity(summary == nil ? 0.08 : 0.14), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            }
            .buttonStyle(.plain)
            .focusable(false)

            if isExpanded {
                content
                    .padding(.horizontal, 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(8)
        .liquidGlass(cornerRadius: 22)
    }
}

private struct SearchChipWrap<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 8)], alignment: .leading, spacing: 8) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SearchFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(.white.opacity(isSelected ? 0.20 : 0.08), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(isSelected ? 0.24 : 0.10), lineWidth: 1)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}

private struct PeopleSearchResults: View {
    let people: [PersonSummary]
    @ObservedObject var model: VestigoModel

    var body: some View {
        if people.isEmpty {
            StatusBubble(title: "No people found", text: "No actors, directors, producers, or other credited people matched this search.")
        } else {
            VStack(spacing: 12) {
                ForEach(people) { person in
                    Button {
                        model.selectedPerson = person
                    } label: {
                        HStack(spacing: 12) {
                            PersonImageView(person: person, width: 58, height: 76)

                            VStack(alignment: .leading, spacing: 5) {
                                Text(person.name)
                                    .font(.headline.bold())
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)

                                Text(person.role.isEmpty ? "Known for" : person.role)
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .liquidGlass(cornerRadius: 22)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct GenreResultsView: View {
    let route: GenreRoute
    @ObservedObject var model: VestigoModel
    @State private var genreFilter: MediaFilter = .both
    @State private var genreSort: GenreSort = .tmdbRating

    private var cacheKey: String {
        model.genreCacheKey(genreID: route.genre.tmdbID, filter: genreFilter, sort: genreSort)
    }

    var body: some View {
        BaseScreen(title: route.genre.name, filter: $genreFilter, settings: model.settings) {
            VStack(spacing: 14) {
                FilterPills(filter: $genreFilter, options: [.movie, .tv, .both]) {
                    Task { await model.loadGenre(route.genre, filter: genreFilter, sort: genreSort) }
                }

                GenreSortPicker(sort: $genreSort) {
                    Task { await model.loadGenre(route.genre, filter: genreFilter, sort: genreSort) }
                }

                MediaGridOrList(
                    items: model.genreResults[cacheKey] ?? [],
                    hideWatchedForUpcoming: false,
                    model: model
                )
            }
        }
        .task {
            genreSort = model.settings.defaultCategorySort
            await model.loadGenre(route.genre, filter: genreFilter, sort: genreSort)
        }
        .onChange(of: genreFilter) { _, newValue in
            Task { await model.loadGenre(route.genre, filter: newValue, sort: genreSort) }
        }
        .onChange(of: genreSort) { _, newValue in
            Task { await model.loadGenre(route.genre, filter: genreFilter, sort: newValue) }
        }
    }
}


// MARK: - For You

private struct ForYouView: View {
    @ObservedObject var model: VestigoModel
    @State private var forYouFilter: MediaFilter = .both
    @State private var forYouPath: [ForYouSection] = []

    private var recentWatchedItem: MediaItem? {
        model.library.lastWatchedItem
    }

    private var favouriteItem: MediaItem? {
        switch forYouFilter {
        case .movie:
            return model.library.favouriteMovie
        case .tv:
            return model.library.favouriteSeries
        case .both:
            return model.library.favouriteMovie ?? model.library.favouriteSeries
        }
    }

    private var topGenreTitle: String {
        let watchedGenreIDs = filteredForYou(model.library.watchedItems).flatMap(\.genreIDs)
        guard let topGenreID = watchedGenreIDs.frequencySorted().first else { return "your taste" }
        return GenreDefinition.all.first(where: { $0.tmdbID == topGenreID })?.name ?? "your taste"
    }

    private var watchlistPicks: [MediaItem] {
        filteredForYou(model.library.watchlistItems)
            .sorted(using: .tmdbRating, ratings: model.library.ratings)
    }

    var body: some View {
        NavigationStack(path: $forYouPath) {
            BaseScreen(title: "For You", filter: $forYouFilter, settings: model.settings) {
                VStack(spacing: 22) {
                    FilterPills(filter: $forYouFilter, options: [.movie, .tv, .both]) {}

                    if model.library.watchedItems.count < 3 {
                        StatusBubble(
                            title: "Not enough watch history yet",
                            text: "Mark at least 3 movies or series as watched to improve personalized recommendations. Ratings make this page more useful."
                        )
                    }

                    if let recentWatchedItem, !filteredForYou(model.moreLikeLastWatched).isEmpty {
                        let sectionTitle = "More like \(recentWatchedItem.title)"
                        let sectionItems = filteredForYou(model.moreLikeLastWatched)

                        MediaSection(title: sectionTitle, items: sectionItems, hideWatchedForUpcoming: false, model: model) {
                            forYouPath.append(ForYouSection(title: sectionTitle, items: sectionItems))
                        }
                    }

                    if let favouriteItem, !filteredForYou(model.moreLikeFavourite).isEmpty {
                        let sectionTitle = "More like your favourite \(favouriteItem.kind.label.lowercased()): \(favouriteItem.title)"
                        let sectionItems = filteredForYou(model.moreLikeFavourite)

                        MediaSection(title: sectionTitle, items: sectionItems, hideWatchedForUpcoming: false, model: model) {
                            forYouPath.append(ForYouSection(title: sectionTitle, items: sectionItems))
                        }
                    }

                    if !watchlistPicks.isEmpty {
                        let sectionTitle = "From your watchlist"
                        let sectionItems = watchlistPicks

                        MediaSection(title: sectionTitle, items: sectionItems, hideWatchedForUpcoming: false, model: model) {
                            forYouPath.append(ForYouSection(title: sectionTitle, items: sectionItems))
                        }
                    }

                    if !filteredForYou(model.seriesNext).isEmpty {
                        let sectionTitle = "Continue with related series"
                        let sectionItems = filteredForYou(model.seriesNext)

                        MediaSection(title: sectionTitle, items: sectionItems, hideWatchedForUpcoming: false, model: model) {
                            forYouPath.append(ForYouSection(title: sectionTitle, items: sectionItems))
                        }
                    }

                    if !filteredForYou(model.fromTopGenre).isEmpty {
                        let sectionTitle = "More from \(topGenreTitle)"
                        let sectionItems = filteredForYou(model.fromTopGenre)

                        MediaSection(title: sectionTitle, items: sectionItems, hideWatchedForUpcoming: false, model: model) {
                            forYouPath.append(ForYouSection(title: sectionTitle, items: sectionItems))
                        }
                    }

                    if !filteredForYou(model.trySomethingNewRecommendations).isEmpty {
                        let sectionTitle = "Try something new"
                        let sectionItems = filteredForYou(model.trySomethingNewRecommendations)

                        MediaSection(title: sectionTitle, items: sectionItems, hideWatchedForUpcoming: false, model: model) {
                            forYouPath.append(ForYouSection(title: sectionTitle, items: sectionItems))
                        }
                    }
                }
                .overlay(alignment: .bottom) {
                    Button {
                        // Program later.
                    } label: {
                        Label("Pick for me", systemImage: "sparkles")
                            .font(.headline.bold())
                            .padding(.horizontal, 16)
                            .frame(height: 46)
                            .liquidGlass(cornerRadius: 23)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 10)
                }
            }
            .navigationDestination(for: ForYouSection.self) { section in
                FullMediaListView(title: section.title, items: section.items, model: model)
            }
            .task {
                await model.loadSmartRecommendations()
            }
            .onChange(of: model.forYouResetToken) { _, _ in
                forYouFilter = .both
                forYouPath.removeAll()
            }
        }
    }

    private func filteredForYou(_ items: [MediaItem]) -> [MediaItem] {
        items.filter { item in
            if model.library.isWatched(item.key) {
                return false
            }

            if model.settings.hideUpcomingFromRecommended && item.isUpcoming {
                return false
            }

            switch forYouFilter {
            case .movie:
                return item.kind == .movie
            case .tv:
                return item.kind == .tv
            case .both:
                return true
            }
        }
    }
}
    
    
    // MARK: - Watchlist
    
    private struct WatchlistView: View {
        @ObservedObject var model: VestigoModel
        
        var sortedItems: [MediaItem] {
            model.library.watchlistItems.sorted(using: model.sortOption, ratings: model.library.ratings)
        }
        
        var unwatchedItems: [MediaItem] {
            sortedItems.filter { !model.library.isWatched($0.key) }
        }
        
        var watchedItems: [MediaItem] {
            sortedItems.filter { model.library.isWatched($0.key) }
        }
        
        var body: some View {
            BaseScreen(title: "Watchlist", filter: .constant(.both), settings: model.settings) {
                VStack(alignment: .leading, spacing: 14) {
                    SortPicker(sort: $model.sortOption, includeMyRating: true)
                    
                    if sortedItems.isEmpty {
                        StatusBubble(title: "No saved items", text: "Saved movies and series will appear here.")
                    } else {
                        if !unwatchedItems.isEmpty {
                            Text("Unwatched")
                                .sectionTitle()
                            
                            MediaGridOrList(items: unwatchedItems, hideWatchedForUpcoming: false, model: model, swipeContext: .watchlist)
                        }
                        
                        if !watchedItems.isEmpty {
                            Text("Watched")
                                .sectionTitle()
                                .padding(.top, unwatchedItems.isEmpty ? 0 : 8)
                            
                            MediaGridOrList(items: watchedItems, hideWatchedForUpcoming: false, model: model, swipeContext: .watchlist)
                        }
                    }
                }
            }
            .onChange(of: model.watchlistResetToken) { _, _ in
                model.sortOption = .tmdbRating
            }
        }
    }
    
    // MARK: - Collections
    // Franchises use a dedicated pushed screen from Collections.
    // TVDB wiring should stay out of this file; use app configuration or a secure API layer for the API key.
    
    private struct CollectionsView: View {
        @ObservedObject var model: VestigoModel
        @State private var newCollectionName = ""
        @State private var collectionPath: [UUID] = []
        
        var body: some View {
            NavigationStack(path: $collectionPath) {
                BaseScreen(title: "Collections", filter: .constant(.both), settings: model.settings) {
                    VStack(spacing: 16) {
                        HStack(spacing: 10) {
                            TextField("New collection", text: $newCollectionName)
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 14)
                                .frame(height: 44)
                                .liquidGlass(cornerRadius: 18)
                            
                            Button("Create") {
                                model.createCollection(named: newCollectionName)
                                newCollectionName = ""
                            }
                            .buttonStyle(.plain)
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)
                            .frame(width: 86, height: 44)
                            .liquidGlass(cornerRadius: 18)
                        }
                        
                        NavigationLink {
                            FranchiseCollectionsView(screenMode: .series, model: model)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "film.stack")
                                    .font(.system(size: 18, weight: .bold))
                                    .frame(width: 26)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Franchises")
                                        .font(.headline.bold())
                                        .foregroundStyle(.primary)

                                    Text("Browse exact TMDb movie collections discovered from your library.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }

                                Spacer(minLength: 0)

                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(14)
                            .liquidGlass(cornerRadius: 22)
                            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        
                        let favourites = [model.library.favouriteMovie, model.library.favouriteSeries].compactMap { $0 }
                        
                        if !favourites.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Favourites")
                                    .sectionTitle()
                                
                                MediaGridOrList(items: favourites, hideWatchedForUpcoming: false, model: model)
                            }
                        }
                        
                        ForEach(model.library.collections) { collection in
                            Button {
                                collectionPath.append(collection.id)
                            } label: {
                                CollectionRow(collection: collection, count: collection.itemKeys.count)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .navigationDestination(for: UUID.self) { collectionID in
                    CollectionDetailView(collectionID: collectionID, model: model)
                }
                
                
            }
            .onChange(of: model.collectionsResetToken) { _, _ in
                collectionPath.removeAll()
            }
        }
    }
    
    private struct FranchiseCollection: Identifiable, Hashable {
        let id: String
        let title: String
        let logoSystemName: String
        let logoURL: URL?
        let aliases: [String]
        let description: String
        let tvdbListQuery: String
        let tvdbListID: Int?
        let tvdbMemberTitles: Set<String>
        let usesTVDBMembership: Bool
        let tmdbCollectionID: Int?
        let exactMemberIDs: Set<String>

        init(
            id: String,
            title: String,
            logoSystemName: String,
            logoURL: URL? = nil,
            aliases: [String],
            description: String,
            tvdbListQuery: String,
            tvdbListID: Int? = nil,
            tvdbMemberTitles: Set<String> = [],
            usesTVDBMembership: Bool = false,
            tmdbCollectionID: Int? = nil,
            exactMemberIDs: Set<String> = []
        ) {
            self.id = id
            self.title = title
            self.logoSystemName = logoSystemName
            self.logoURL = logoURL
            self.aliases = aliases
            self.description = description
            self.tvdbListQuery = tvdbListQuery
            self.tvdbListID = tvdbListID
            self.tvdbMemberTitles = tvdbMemberTitles
            self.usesTVDBMembership = usesTVDBMembership
            self.tmdbCollectionID = tmdbCollectionID
            self.exactMemberIDs = exactMemberIDs
        }
    }

    private enum VestigoBackendConfiguration {
        static let baseURL = URL(string: "https://mtttuyvpjyugudkevchj.supabase.co/functions/v1/vestigo-api")!
    }

    private struct TVDBFranchiseList: Identifiable, Hashable, Decodable {
        let id: Int
        let name: String
        let overview: String?
        let memberTitles: Set<String>
    }

    private struct BackendMediaItemDTO: Decodable {
        let id: Int
        let kind: String
        let title: String
        let overview: String
        let posterPath: String?
        let backdropPath: String?
        let releaseDate: String?
        let voteAverage: Double
        let genreIDs: [Int]
        let originalLanguage: String?

        var mediaItem: MediaItem {
            MediaItem(
                id: id,
                kind: kind == "tv" ? .tv : .movie,
                title: title,
                overview: overview,
                posterPath: posterPath,
                backdropPath: backdropPath,
                releaseDate: releaseDate,
                voteAverage: voteAverage,
                genreIDs: genreIDs,
                creditRole: nil,
                runtime: nil,
                originalLanguage: originalLanguage
            )
        }
    }

    private actor VestigoBackendClient {
        private let baseURL: URL

        init(baseURL: URL = VestigoBackendConfiguration.baseURL) {
            self.baseURL = baseURL
        }

        func franchiseList(id: String, matching query: String) async throws -> TVDBFranchiseList? {
            var components = URLComponents(url: baseURL.appending(path: "franchise-membership"), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "id", value: id),
                URLQueryItem(name: "query", value: query)
            ]

            guard let url = components.url else { return nil }
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            if httpResponse.statusCode == 404 {
                return nil
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }

            let decoded = try JSONDecoder().decode(BackendFranchiseMembershipResponse.self, from: data)
            return decoded.franchise
        }
        
        func franchiseRecommendations(id: String, matching query: String) async throws -> [MediaItem] {
            var components = URLComponents(url: baseURL.appending(path: "franchise-recommendations"), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "id", value: id),
                URLQueryItem(name: "query", value: query)
            ]

            guard let url = components.url else { return [] }
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }

            let decoded = try JSONDecoder().decode(BackendFranchiseRecommendationsResponse.self, from: data)
            return decoded.results.map(\.mediaItem)
        }
        
        func tmdbCollection(for item: MediaItem) async throws -> BackendTMDbCollectionDTO? {
            guard item.kind == .movie else { return nil }

            var components = URLComponents(url: baseURL.appending(path: "tmdb-collection-for-item"), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "id", value: String(item.id))
            ]

            guard let url = components.url else { return nil }
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            if httpResponse.statusCode == 404 {
                return nil
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }

            let decoded = try JSONDecoder().decode(BackendTMDbCollectionResponse.self, from: data)
            return decoded.collection
        }

        func tmdbCollectionRecommendations(collectionID: Int) async throws -> [MediaItem] {
            var components = URLComponents(url: baseURL.appending(path: "tmdb-collection"), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "id", value: String(collectionID))
            ]

            guard let url = components.url else { return [] }
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }

            let decoded = try JSONDecoder().decode(BackendTMDbCollectionResponse.self, from: data)
            return decoded.collection?.mediaItems ?? []
        }

        static func normalizedTitle(_ value: String) -> String {
            value
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .lowercased()
                .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private struct BackendFranchiseMembershipResponse: Decodable {
        let ok: Bool
        let franchise: TVDBFranchiseList?
    }
    
    private struct BackendFranchiseRecommendationsResponse: Decodable {
        let ok: Bool
        let results: [BackendMediaItemDTO]
    }

    private struct BackendTMDbCollectionResponse: Decodable {
        let ok: Bool
        let collection: BackendTMDbCollectionDTO?
    }

    private struct BackendTMDbCollectionDTO: Decodable, Identifiable {
        let id: Int
        let name: String
        let overview: String?
        let items: [BackendMediaItemDTO]

        var mediaItems: [MediaItem] {
            items.map(\.mediaItem)
        }
    }
    
    private enum FranchiseDetailMode: String, CaseIterable, Identifiable, Hashable {
        case watched
        case recommended
        
        var id: String { rawValue }
        
        var title: String {
            switch self {
            case .watched:
                return "Watched"
            case .recommended:
                return "Recommended"
            }
        }
    }
    private enum FranchiseCollectionScreenMode {
        case all
        case series
        case universes

        var title: String {
            switch self {
            case .all:
                return "Franchises"
            case .series:
                return "Franchises"
            case .universes:
                return "Universes"
            }
        }

        var emptyTitle: String {
            switch self {
            case .all:
                return "No franchises found"
            case .series:
                return "No franchises found"
            case .universes:
                return "No universes found"
            }
        }

        var emptyText: String {
            switch self {
            case .all:
                return "Franchises appear here after matched movies or series exist in your library."
            case .series:
                return "Franchises appear here after a movie in your library belongs to a TMDb collection."
            case .universes:
                return "Universe groups appear here after matched movies or series exist in your library."
            }
        }
    }

    private struct FranchiseCollectionsView: View {
        let screenMode: FranchiseCollectionScreenMode
        @ObservedObject var model: VestigoModel
        @State private var selectedFranchise: FranchiseCollection?
        @State private var tvdbFranchises: [String: TVDBFranchiseList] = [:]
        @State private var tmdbCollectionFranchises: [FranchiseCollection] = []
        @State private var tvdbLoadError: String?
        private let backendClient = VestigoBackendClient()

        private var franchises: [FranchiseCollection] {
            let discoveredIDs = Set(tmdbCollectionFranchises.map(\.id))
            let seeded = FranchiseLibrary.defaultFranchises(
                matching: Array(model.library.items.values),
                tvdbLists: tvdbFranchises
            )
            .filter { !discoveredIDs.contains($0.id) }

            return (tmdbCollectionFranchises + seeded)
                .sorted { lhs, rhs in
                    lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
        }

        private var seriesFranchises: [FranchiseCollection] {
            tmdbCollectionFranchises
                .sorted { lhs, rhs in
                    lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
        }

        private var universeFranchises: [FranchiseCollection] {
            let seriesIDs = Set(tmdbCollectionFranchises.map(\.id))
            return franchises
                .filter { $0.tmdbCollectionID == nil && !seriesIDs.contains($0.id) }
                .sorted { lhs, rhs in
                    lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
        }
        
        private var visibleFranchisesForErrorState: [FranchiseCollection] {
            switch screenMode {
            case .all:
                return franchises
            case .series:
                return seriesFranchises
            case .universes:
                return universeFranchises
            }
        }

        private var shouldShowFranchiseLoadError: Bool {
            guard let tvdbLoadError, !tvdbLoadError.isEmpty else { return false }
            return visibleFranchisesForErrorState.isEmpty
        }

        var body: some View {
            BaseScreen(title: screenMode.title, filter: .constant(.both), settings: model.settings) {
                VStack(alignment: .leading, spacing: 14) {
                    if shouldShowFranchiseLoadError, let tvdbLoadError {
                        StatusBubble(
                            title: "Franchise load failed",
                            text: "Using local fallback matching. \(tvdbLoadError)"
                        )
                    }
                    switch screenMode {
                    case .all:
                        if franchises.isEmpty {
                            StatusBubble(
                                title: screenMode.emptyTitle,
                                text: screenMode.emptyText
                            )
                        } else {
                            if !seriesFranchises.isEmpty {
                                Text("Franchises")
                                    .sectionTitle()

                                ForEach(seriesFranchises) { franchise in
                                    Button {
                                        selectedFranchise = franchise
                                    } label: {
                                        FranchiseCollectionRow(
                                            franchise: franchise,
                                            count: FranchiseLibrary.items(in: franchise, from: Array(model.library.items.values)).count
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            if !universeFranchises.isEmpty {
                                Text("Universes")
                                    .sectionTitle()
                                    .padding(.top, seriesFranchises.isEmpty ? 0 : 10)

                                ForEach(universeFranchises) { franchise in
                                    Button {
                                        selectedFranchise = franchise
                                    } label: {
                                        FranchiseCollectionRow(
                                            franchise: franchise,
                                            count: FranchiseLibrary.items(in: franchise, from: Array(model.library.items.values)).count
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                    case .series:
                        if seriesFranchises.isEmpty {
                            StatusBubble(
                                title: screenMode.emptyTitle,
                                text: screenMode.emptyText
                            )
                        } else {
                            ForEach(seriesFranchises) { franchise in
                                Button {
                                    selectedFranchise = franchise
                                } label: {
                                    FranchiseCollectionRow(
                                        franchise: franchise,
                                        count: FranchiseLibrary.items(in: franchise, from: Array(model.library.items.values)).count
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                    case .universes:
                        if universeFranchises.isEmpty {
                            StatusBubble(
                                title: screenMode.emptyTitle,
                                text: screenMode.emptyText
                            )
                        } else {
                            ForEach(universeFranchises) { franchise in
                                Button {
                                    selectedFranchise = franchise
                                } label: {
                                    FranchiseCollectionRow(
                                        franchise: franchise,
                                        count: FranchiseLibrary.items(in: franchise, from: Array(model.library.items.values)).count
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .navigationDestination(item: $selectedFranchise) { franchise in
                FranchiseDetailView(franchise: franchise, model: model)
            }
            .task(id: screenMode.title) {
                await loadDiscoveredTMDbCollections()
                await loadTVDBFranchises()
            }
        }

        private func loadTVDBFranchises() async {
            do {
                var loaded: [String: TVDBFranchiseList] = [:]
                for franchise in FranchiseLibrary.seedFranchises {
                    if let list = try await backendClient.franchiseList(id: franchise.id, matching: franchise.tvdbListQuery) {
                        loaded[franchise.id] = list
                    }
                }

                await MainActor.run {
                    tvdbFranchises = loaded
                    tvdbLoadError = nil
                }
            } catch {
                if error is CancellationError {
                    return
                }

                if let urlError = error as? URLError, urlError.code == .cancelled {
                    return
                }

                await MainActor.run {
                    tvdbLoadError = error.localizedDescription
                }
            }
        }
        
        private func loadDiscoveredTMDbCollections() async {
            let movieItems = (Array(model.library.items.values) + model.library.watchedItems + model.library.watchlistItems)
                .uniqued()
                .filter { $0.kind == .movie }
            var collectionsByID: [Int: BackendTMDbCollectionDTO] = [:]

            for item in movieItems {
                do {
                    if let collection = try await backendClient.tmdbCollection(for: item) {
                        collectionsByID[collection.id] = collection
                    }
                } catch {
                    continue
                }
            }

            let discovered = collectionsByID.values.map { collection in
                let items = collection.mediaItems

                return FranchiseCollection(
                    id: "tmdb-collection-\(collection.id)",
                    title: collection.name.replacingOccurrences(of: " Collection", with: ""),
                    logoSystemName: "film.stack",
                    logoURL: items.first(where: { $0.posterURL != nil })?.posterURL,
                    aliases: [],
                    description: collection.overview ?? "TMDb movie collection discovered from your library.",
                    tvdbListQuery: "",
                    tmdbCollectionID: collection.id,
                    exactMemberIDs: Set(items.map { "\($0.kind.tmdbPath)-\($0.id)" })
                )
            }

            await MainActor.run {
                tmdbCollectionFranchises = discovered.sorted { lhs, rhs in
                    lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
            }
        }
    }
    
    private struct FranchiseCollectionRow: View {
        let franchise: FranchiseCollection
        let count: Int

        var body: some View {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.white.opacity(0.10))

                    if let logoURL = franchise.logoURL {
                        RemoteImageView(
                            url: logoURL,
                            fallback: AnyView(
                                Image(systemName: franchise.logoSystemName)
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundStyle(.primary)
                            )
                        )
                        .scaledToFill()
                        .frame(width: 58, height: 58)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    } else {
                        Image(systemName: franchise.logoSystemName)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.primary)
                    }
                }
                .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: 4) {
                    Text(franchise.title)
                        .font(.headline.bold())
                        .foregroundStyle(.primary)

                    Text(franchise.tmdbCollectionID != nil ? (count == 1 ? "1 franchise title" : "\(count) franchise titles") : (franchise.usesTVDBMembership ? (count == 1 ? "1 universe title" : "\(count) universe titles") : (count == 1 ? "1 locally matched universe title" : "\(count) locally matched universe titles")))
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    Text(franchise.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .liquidGlass(cornerRadius: 22)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }
    
    private struct FranchiseDetailView: View {
        let franchise: FranchiseCollection
        @ObservedObject var model: VestigoModel
        @State private var sort: SortOption = .tmdbRating
        @State private var mode: FranchiseDetailMode = .watched
        @State private var universeMediaFilter: MediaFilter = .both
        @State private var backendRecommendations: [MediaItem] = []
        @State private var backendRecommendationError: String?
        @State private var isLoadingBackendRecommendations = false
        private let backendClient = VestigoBackendClient()

        private var allItems: [MediaItem] {
            Array(model.library.items.values)
        }

        private var franchiseItems: [MediaItem] {
            FranchiseLibrary.sortedItems(
                FranchiseLibrary.items(in: franchise, from: allItems),
                using: sort,
                library: model.library
            )
        }

        private var watchedItems: [MediaItem] {
            if isSeriesCollection {
                return seriesWatchedItems
            }

            return universeWatchedItems
        }

        private var isSeriesCollection: Bool {
            franchise.tmdbCollectionID != nil
        }

        private var seriesCollectionItems: [MediaItem] {
            FranchiseLibrary.sortedItems(
                (franchiseItems + backendRecommendations).uniqued(),
                using: sort,
                library: model.library
            )
        }

        private var seriesWatchedItems: [MediaItem] {
            seriesCollectionItems.filter { model.library.isWatched($0.key) }
        }

        private var seriesRemainingItems: [MediaItem] {
            seriesCollectionItems.filter { item in
                !model.library.isWatched(item.key)
                && (!model.settings.hideUpcomingFromCollectionRecommendations || !item.isUpcoming)
            }
        }

        private var universeCollectionItems: [MediaItem] {
            FranchiseLibrary.sortedItems(
                (franchiseItems + backendRecommendations).uniqued(),
                using: sort,
                library: model.library
            )
        }

        private var universeWatchedItems: [MediaItem] {
            universeCollectionItems.filter { model.library.isWatched($0.key) }
        }
        
        private var filteredUniverseWatchedItems: [MediaItem] {
            filterUniverseItems(universeWatchedItems)
        }

        private var universeRemainingItems: [MediaItem] {
            universeCollectionItems.filter { item in
                !model.library.isWatched(item.key)
                && (!model.settings.hideUpcomingFromCollectionRecommendations || !item.isUpcoming)
            }
        }
        
        private var filteredUniverseUnwatchedItems: [MediaItem] {
            filterUniverseItems(universeRemainingItems)
        }

        private func filterUniverseItems(_ items: [MediaItem]) -> [MediaItem] {
            switch universeMediaFilter {
            case .movie:
                return items.filter { $0.kind == .movie }
            case .tv:
                return items.filter { $0.kind == .tv }
            case .both:
                return items
            }
        }

        private var isSeriesComplete: Bool {
            isSeriesCollection && !seriesCollectionItems.isEmpty && seriesRemainingItems.isEmpty
        }

        private var recommendedItems: [MediaItem] {
            if isSeriesCollection {
                return seriesRemainingItems
            }

            return universeRemainingItems
        }

        private var visibleItems: [MediaItem] {
            if isSeriesCollection {
                switch mode {
                case .watched:
                    return watchedItems
                case .recommended:
                    return recommendedItems
                }
            }

            switch mode {
            case .watched:
                return filteredUniverseWatchedItems
            case .recommended:
                return filteredUniverseUnwatchedItems
            }
        }

        private var watchedModeTitle: String {
            if isSeriesCollection {
                return "Watched (\(seriesWatchedItems.count))"
            }

            return "Watched"
        }

        private var remainingModeTitle: String {
            if isSeriesCollection {
                return "Remaining (\(seriesRemainingItems.count))"
            }

            return "Unwatched"
        }
        
        private var hasUniverseRecommendations: Bool {
            !isSeriesCollection && !universeRemainingItems.isEmpty
        }

        private var shouldShowUniverseModePicker: Bool {
            !isSeriesCollection && (!watchedItems.isEmpty || isLoadingBackendRecommendations || hasUniverseRecommendations)
        }

        private var shouldShowModePicker: Bool {
            if isSeriesComplete {
                return false
            }

            if isSeriesCollection {
                return true
            }

            return shouldShowUniverseModePicker
        }

        private var localMembershipText: String {
            if isSeriesCollection {
                return model.settings.hideUpcomingFromCollectionRecommendations ? "Remaining uses local franchise matching and hides upcoming releases." : "Remaining uses local franchise matching for unwatched titles."
            }

            return model.settings.hideUpcomingFromCollectionRecommendations ? "Unwatched uses local universe matching and hides upcoming releases." : "Unwatched uses local universe matching for unwatched titles."
        }

        private var tvdbMembershipText: String {
            if isSeriesCollection {
                return model.settings.hideUpcomingFromCollectionRecommendations ? "Remaining uses exact TMDb franchise membership and hides upcoming releases." : "Remaining uses exact TMDb franchise membership for unwatched titles."
            }

            if hasUniverseRecommendations {
                return model.settings.hideUpcomingFromCollectionRecommendations ? "Unwatched uses exact provider-backed universe membership and hides upcoming releases." : "Unwatched uses exact provider-backed universe membership for unwatched titles."
            }

            return "Watched uses local universe matching. Unwatched appears when exact provider-backed universe membership returns unwatched titles."
        }

        var body: some View {
            BaseScreen(title: franchise.title, filter: .constant(.both), settings: model.settings) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(.white.opacity(0.10))

                            if let logoURL = franchise.logoURL {
                                RemoteImageView(
                                    url: logoURL,
                                    fallback: AnyView(
                                        Image(systemName: franchise.logoSystemName)
                                            .font(.system(size: 28, weight: .bold))
                                    )
                                )
                                .scaledToFill()
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            } else {
                                Image(systemName: franchise.logoSystemName)
                                    .font(.system(size: 28, weight: .bold))
                            }
                        }
                        .frame(width: 64, height: 64)

                        VStack(alignment: .leading, spacing: 5) {
                            Text(franchise.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text((franchise.usesTVDBMembership || franchise.tmdbCollectionID != nil) ? tvdbMembershipText : localMembershipText)
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                    .liquidGlass(cornerRadius: 24)

                    SortPicker(sort: $sort, includeMyRating: true)

                    if !isSeriesCollection && shouldShowModePicker {
                        FilterPills(filter: $universeMediaFilter, options: [.movie, .tv, .both]) {}
                    }

                    if shouldShowModePicker {
                        FranchiseDetailModePicker(
                            mode: $mode,
                            watchedTitle: watchedModeTitle,
                            recommendedTitle: remainingModeTitle
                        )
                    }

                    if isLoadingBackendRecommendations && !isSeriesComplete {
                        StatusBubble(title: "Loading franchise titles", text: "Checking exact franchise membership through the Vestigo backend.")
                    } else if visibleItems.isEmpty {
                        StatusBubble(title: emptyTitle, text: emptyText)
                    } else {
                        MediaGridOrList(items: visibleItems, hideWatchedForUpcoming: false, model: model)
                    }

                    if let backendRecommendationError, mode == .recommended, isSeriesCollection || hasUniverseRecommendations {
                        StatusBubble(title: "Backend recommendations failed", text: backendRecommendationError)
                    }
                }
            }
            .task(id: franchise.id) {
                await loadBackendRecommendations()
            }
        }

        private var emptyTitle: String {
            if isSeriesCollection {
                switch mode {
                case .recommended:
                    return "Franchises complete"
                case .watched:
                    return "No watched titles"
                }
            }

            switch mode {
            case .recommended:
                return "No remaining universe titles"
            case .watched:
                return "No watched titles"
            }
        }

        private var emptyText: String {
            if isSeriesCollection {
                switch mode {
                case .recommended:
                    return "Every available title in this franchise has been marked watched."
                case .watched:
                    return "No titles in this franchise have been marked watched yet."
                }
            }

            switch mode {
            case .recommended:
                return model.settings.hideUpcomingFromCollectionRecommendations ? "No exact provider-backed universe matches were found, or every exact match has already been watched or is upcoming." : "No exact provider-backed universe matches were found, or every exact match has already been watched."
            case .watched:
                return "No matched titles in this universe have been marked watched yet."
            }
        }
        
        private func loadBackendRecommendations() async {
            await MainActor.run {
                isLoadingBackendRecommendations = true
                backendRecommendationError = nil
            }

            do {
                let results: [MediaItem]
                if let tmdbCollectionID = franchise.tmdbCollectionID {
                    results = try await backendClient.tmdbCollectionRecommendations(collectionID: tmdbCollectionID)
                } else {
                    results = try await backendClient.franchiseRecommendations(id: franchise.id, matching: franchise.tvdbListQuery)
                }
                await MainActor.run {
                    backendRecommendations = results
                    backendRecommendationError = nil
                    isLoadingBackendRecommendations = false
                }
            } catch {
                await MainActor.run {
                    backendRecommendationError = isSeriesCollection ? error.localizedDescription : nil
                    isLoadingBackendRecommendations = false

                    if !isSeriesCollection {
                        mode = .watched
                    }
                }
            }
        }
    }
    
    private struct FranchiseDetailModePicker: View {
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
    
    private enum FranchiseLibrary {
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
                sourceItems.filter { item in matches(item, franchise: franchise) },
                using: .releaseDate,
                library: UserLibrary()
            )
        }

        static func recommendations(in franchise: FranchiseCollection, from sourceItems: [MediaItem], library: UserLibrary, settings: AppSettings, sort: SortOption) -> [MediaItem] {
            let watchedGenreIDs = Set(library.watchedItems.flatMap(\.genreIDs))
            let favouriteKeys = [library.favouriteMovie?.key, library.favouriteSeries?.key].compactMap { $0 }

            return sourceItems
                .filter { item in
                    matches(item, franchise: franchise)
                    && !library.isWatched(item.key)
                    && (!settings.hideUpcomingFromCollectionRecommendations || !item.isUpcoming)
                }
                .sorted { lhs, rhs in
                    let lhsScore = recommendationScore(for: lhs, watchedGenreIDs: watchedGenreIDs, favouriteKeys: favouriteKeys, ratings: library.ratings)
                    let rhsScore = recommendationScore(for: rhs, watchedGenreIDs: watchedGenreIDs, favouriteKeys: favouriteKeys, ratings: library.ratings)

                    if lhsScore != rhsScore {
                        return lhsScore > rhsScore
                    }

                    return comesBefore(lhs, rhs, using: sort, library: library)
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

        static func sortedItems(_ items: [MediaItem], using sort: SortOption, library: UserLibrary) -> [MediaItem] {
            items.sorted { lhs, rhs in
                comesBefore(lhs, rhs, using: sort, library: library)
            }
        }

        private static func comesBefore(_ lhs: MediaItem, _ rhs: MediaItem, using sort: SortOption, library: UserLibrary) -> Bool {
            switch sort {
            case .tmdbRating:
                if lhs.voteAverage != rhs.voteAverage {
                    return lhs.voteAverage > rhs.voteAverage
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

        private static func recommendationScore(for item: MediaItem, watchedGenreIDs: Set<Int>, favouriteKeys: [MediaKey], ratings: [MediaKey: Double]) -> Double {
            let genreOverlap = Double(item.genreIDs.filter { watchedGenreIDs.contains($0) }.count) * 1.25
            let tmdbScore = item.voteAverage / 2.0
            let releaseScore = Double(max(0, min(releaseYear(for: item) - 1970, 60))) / 30.0
            let ratingScore = ratings[item.key] ?? 0
            let favouritePenalty = favouriteKeys.contains(item.key) ? 0.5 : 0

            return genreOverlap + tmdbScore + releaseScore + ratingScore - favouritePenalty
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
    
    // CollectionDetailMode enum for CollectionDetailView
    private enum CollectionDetailMode: String, CaseIterable, Identifiable, Hashable {
        case myList
        case recommended
        
        var id: String { rawValue }
        
        var title: String {
            switch self {
            case .myList:
                return "My list"
            case .recommended:
                return "Recommended"
            }
        }
    }
    
    private struct CollectionDetailView: View {
        let collectionID: UUID
        @ObservedObject var model: VestigoModel
        @State private var sort: SortOption = .tmdbRating
        @State private var mode: CollectionDetailMode = .myList
        
        private var collection: MediaCollection? {
            model.library.collections.first { $0.id == collectionID }
        }
        
        private var items: [MediaItem] {
            guard let collection else { return [] }
            return collection.itemKeys.compactMap { model.library.items[$0] }.sorted(using: sort, ratings: model.library.ratings)
        }
        
        private var recommendedItems: [MediaItem] {
            guard let collection else { return [] }
            let existingKeys = Set(collection.itemKeys)
            
            return (model.collectionRecommendations[collectionID] ?? [])
                .filter { item in
                    !existingKeys.contains(item.key)
                    && !model.library.isWatched(item.key)
                    && (!model.settings.hideUpcomingFromCollectionRecommendations || !item.isUpcoming)
                }
                .sorted(using: sort, ratings: model.library.ratings)
        }
        
        var body: some View {
            BaseScreen(title: collection?.name ?? "Collection", filter: .constant(.both), settings: model.settings) {
                VStack(spacing: 14) {
                    SortPicker(sort: $sort, includeMyRating: true)
                    
                    CollectionDetailModePicker(mode: $mode)
                    
                    if mode == .myList {
                        MediaGridOrList(items: items, hideWatchedForUpcoming: false, model: model, swipeContext: .collection(collectionID))
                    } else if recommendedItems.isEmpty {
                        StatusBubble(
                            title: "No collection recommendations",
                            text: "Recommendations for this collection will appear here when related unwatched movies or series are found."
                        )
                    } else {
                        MediaGridOrList(items: recommendedItems, hideWatchedForUpcoming: false, model: model)
                    }
                }
            }
            .task(id: collectionID) {
                await model.loadCollectionRecommendations(for: collectionID)
            }
            .onChange(of: mode) { _, newValue in
                if newValue == .recommended {
                    Task { await model.loadCollectionRecommendations(for: collectionID) }
                }
            }
            .onChange(of: model.library.watched) { _, _ in
                if mode == .recommended {
                    Task { await model.loadCollectionRecommendations(for: collectionID) }
                }
            }
        }
    }
    
    private struct CollectionDetailModePicker: View {
        @Binding var mode: CollectionDetailMode
        
        var body: some View {
            Picker("Collection view", selection: $mode) {
                Text(CollectionDetailMode.myList.title).tag(CollectionDetailMode.myList)
                Text(CollectionDetailMode.recommended.title).tag(CollectionDetailMode.recommended)
            }
            .pickerStyle(.segmented)
            .liquidGlass(cornerRadius: 18)
        }
    }
    
    // MARK: - Settings
    
    private struct SettingsSheetSurface: View {
        @ObservedObject var model: VestigoModel

        var body: some View {
            VStack(spacing: 0) {
                SettingsView(model: model)
                    .scrollBounceBehavior(.basedOnSize, axes: .vertical)
                    .overlay(alignment: .top) {
                        Capsule()
                            .fill(.white.opacity(0.50))
                            .frame(width: 48, height: 5)
                            .padding(.top, 12)
                            .allowsHitTesting(false)
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background {
                RoundedRectangle(cornerRadius: 54, style: .continuous)
                    .fill(.black.opacity(0.38))
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 54, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 54, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1.2)
            }
            .clipShape(RoundedRectangle(cornerRadius: 54, style: .continuous))
            .ignoresSafeArea(.container, edges: .bottom)
        }
    }
    
    private struct SettingsView: View {
        @ObservedObject var model: VestigoModel
        @State private var clearPresses = 0
        @State private var showClearConfirm = false
        @State private var importText = ""
        
        var body: some View {
            BaseScreen(title: "Settings", filter: .constant(.both), settings: model.settings, contentTopPadding: 18) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Display")
                        .sectionTitle()
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Dark Mode", isOn: Binding(
                            get: { model.settings.appearance == .dark },
                            set: { model.settings.appearance = $0 ? .dark : .light }
                        ))
                        .font(.headline.bold())
                        .tint(model.settings.accentColor)
                        .settingBubble()
                        
                        Toggle("Plain black/white background", isOn: $model.settings.usePlainBackground)
                            .font(.headline.bold())
                            .tint(model.settings.accentColor)
                            .settingBubble()
                        
                        ColorPicker(
                            "Accent Colour",
                            selection: Binding(
                                get: { model.settings.accentColor },
                                set: { model.settings.setAccentColor($0) }
                            ),
                            supportsOpacity: false
                        )
                        .font(.headline.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .settingBubble()
                    }
                    
                    Text("Content")
                        .sectionTitle()
                        .padding(.top, 6)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 8) {
                            Stepper(value: $model.settings.recommendationStrength, in: 1...5, step: 0.5) {
                                Text("Recommendation Strength: \(model.settings.recommendationStrength.formatted(.number.precision(.fractionLength(1))))")
                                    .font(.headline.bold())
                            }
                            
                            Text("Lower strength uses more of your watched history and may create broader suggestions. Higher strength mainly uses items you rated well, which should make recommendations stricter but less varied. Recommendations appear after you have marked enough items as watched, and improve when you rate them.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .settingBubble()
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle("Prioritise English", isOn: $model.settings.prioritiseEnglish)
                                .font(.headline.bold())
                                .tint(model.settings.accentColor)
                            
                            Text("When this is on, English-language titles are shown first when otherwise similar results are available.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .settingBubble()
                        .onChange(of: model.settings.prioritiseEnglish) { _, _ in
                            model.searchResults = model.preparedResults(model.searchResults)
                            Task { await model.loadHome() }
                        }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle("Hide adult/explicit results", isOn: $model.settings.hideAdultResults)
                                .font(.headline.bold())
                                .tint(model.settings.accentColor)
                            
                            Text("When this is on, searches and browsed results avoid adult-marked TMDb entries where the API supports that filtering. When it is off, TMDb may include adult-marked results.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .settingBubble()
                        .onChange(of: model.settings.hideAdultResults) { _, _ in
                            model.updateSearch()
                            Task { await model.loadHome() }
                        }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle("Hide anime", isOn: $model.settings.hideAnimeResults)
                                .font(.headline.bold())
                                .tint(model.settings.accentColor)
                            
                            Text("When this is on, anime and likely anime-related results are filtered out where possible. This may also hide anime-adjacent titles that are not considered actual anime.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .settingBubble()
                        .onChange(of: model.settings.hideAnimeResults) { _, _ in
                            model.searchResults = model.preparedResults(model.searchResults)
                            Task { await model.loadHome() }
                        }
                        
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 10) {
                                Toggle("Hide from Home", isOn: $model.settings.hideWatchedFromHome)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.primary)
                                    .tint(model.settings.accentColor)
                                    .padding(.trailing, 6)
                                
                                Toggle("Hide from Search", isOn: $model.settings.hideWatchedFromSearch)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.primary)
                                    .tint(model.settings.accentColor)
                                    .padding(.trailing, 6)
                            }
                            .padding(.top, 8)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Hide watched results")
                                    .font(.headline.bold())
                                    .foregroundStyle(.primary)
                                
                                Text("Choose where items you have already marked as watched should be hidden. Watchlist and Collections still show their saved contents.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .foregroundStyle(.primary)
                        .tint(model.settings.accentColor)
                        .settingBubble()
                        .onChange(of: model.settings.hideWatchedFromHome) { _, _ in
                            Task { await model.loadHome() }
                        }
                        .onChange(of: model.settings.hideWatchedFromSearch) { _, _ in
                            model.searchResults = model.preparedResults(model.searchResults, hideWatched: model.settings.hideWatchedFromSearch)
                            
                            Task {
                                for route in model.searchPath {
                                    await model.loadGenre(route.genre)
                                }
                            }
                        }
                        
                        ShortFilmsSettingsGroup(model: model)
                        
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Hide upcoming releases")
                                .font(.headline.bold())
                            
                            Text("Choose where unreleased titles should be hidden. Home does not have a toggle because Upcoming releases is its own carousel.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            Toggle("Search", isOn: $model.settings.hideUpcomingFromSearch)
                            Toggle("For You / Recommended", isOn: $model.settings.hideUpcomingFromRecommended)
                            Toggle("Collection and franchise recommendations", isOn: $model.settings.hideUpcomingFromCollectionRecommendations)
                        }
                        .settingBubble()
                        .onChange(of: model.settings.hideUpcomingFromSearch) { _, _ in
                            model.updateSearch()
                            
                            Task {
                                for route in model.searchPath {
                                    await model.loadGenre(route.genre)
                                }
                            }
                        }
                        .onChange(of: model.settings.hideUpcomingFromRecommended) { _, _ in
                            Task { await model.loadSmartRecommendations() }
                        }
                        .onChange(of: model.settings.hideUpcomingFromCollectionRecommendations) { _, _ in
                            Task {
                                for collection in model.library.collections {
                                    await model.loadCollectionRecommendations(for: collection.id)
                                }
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle("Remove items from watchlist", isOn: $model.settings.removeItemsFromWatchlist)
                                .font(.headline.bold())
                                .tint(model.settings.accentColor)
                            
                            Text("When this is on, marking a saved item as watched removes it from Watchlist. When it is off, watched saved items stay in Watchlist under the Watched section.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .settingBubble()
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle("Warn before replacing favourite", isOn: $model.settings.warnBeforeReplacingFavourite)
                                .font(.headline.bold())
                                .tint(model.settings.accentColor)
                            
                            Text("When this is on, replacing your favourite movie or favourite series asks for confirmation first.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .settingBubble()
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle("Prompt to rate after marking watched", isOn: $model.settings.promptToRateAfterMarkingWatched)
                                .font(.headline.bold())
                                .tint(model.settings.accentColor)
                            
                            Text("When this is on, marking a movie or series as watched opens a rating prompt right where you are.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .settingBubble()
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle("Show upcoming releases", isOn: $model.settings.showUpcomingReleases)
                                .font(.headline.bold())
                                .tint(model.settings.accentColor)
                            
                            Text("When this is on, Home shows unreleased movies and series in the Upcoming section.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .settingBubble()
                        .onChange(of: model.settings.showUpcomingReleases) { _, _ in
                            Task { await model.loadHome() }
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Default Home Filter")
                                .font(.headline.bold())
                            
                            FilterPills(
                                filter: Binding(
                                    get: { model.settings.defaultHomeFilter },
                                    set: { newValue in
                                        model.settings.defaultHomeFilter = newValue
                                        model.mediaFilter = newValue
                                        Task { await model.loadHome() }
                                    }
                                ),
                                options: [.movie, .tv, .both]
                            ) {
                                model.mediaFilter = model.settings.defaultHomeFilter
                                Task { await model.loadHome() }
                            }
                            
                            Text("Choose whether Home opens to movies, series, or both.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .settingBubble()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Default Search Type")
                                .font(.headline.bold())
                            
                            SearchFilterPills(
                                filter: Binding(
                                    get: { model.settings.defaultSearchFilter },
                                    set: { newValue in
                                        model.settings.defaultSearchFilter = newValue
                                        model.searchFilter = newValue
                                        model.updateSearch()
                                    }
                                )
                            ) {
                                model.searchFilter = model.settings.defaultSearchFilter
                                model.updateSearch()
                            }
                            
                            Text("Choose which type Search opens with by default.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .settingBubble()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Default Category Sort")
                                .font(.headline.bold())
                            
                            GenreSortPicker(
                                sort: Binding(
                                    get: { model.settings.defaultCategorySort },
                                    set: { newValue in
                                        model.settings.defaultCategorySort = newValue
                                    }
                                )
                            ) { }
                            
                            Text("Choose whether category pages open sorted by TMDb rating or release date.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .settingBubble()
                        
                    }
                    
                    Text("Data")
                        .sectionTitle()
                        .padding(.top, 6)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Import watched titles separated by commas, e.g. 'Star Wars, The Boys, Invincible, etc.'", text: $importText, axis: .vertical)
                                .lineLimit(3...5)
                                .textFieldStyle(.plain)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .liquidGlass(cornerRadius: 18)
                            
                            Button {
                                Task { await model.importWatchedText(importText) }
                            } label: {
                                HStack(alignment: .center, spacing: 10) {
                                    Image(systemName: "tray.and.arrow.down")
                                        .font(.system(size: 17, weight: .semibold))
                                        .frame(width: 24, height: 22, alignment: .center)
                                    
                                    Text("Import as watched")
                                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                                        .lineLimit(1)
                                        .frame(height: 22, alignment: .center)
                                    
                                    Spacer(minLength: 0)
                                }
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(height: 32, alignment: .center)
                                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(10)
                        .liquidGlass(cornerRadius: 22)
                        
                        Button {
                            model.prepareExport()
                        } label: {
                            HStack(alignment: .center, spacing: 10) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 17, weight: .semibold))
                                    .frame(width: 24, height: 22, alignment: .center)
                                
                                Text("Export watched data")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .lineLimit(1)
                                    .frame(height: 22, alignment: .center)
                                
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: 48, alignment: .center)
                            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .liquidGlass(cornerRadius: 18)
                        .fileExporter(isPresented: $model.showExporter, document: model.exportDocument, contentType: .plainText, defaultFilename: "Vestigo Watched") { _ in }
                        
                        Button("Reset settings") {
                            model.settings = AppSettings()
                            model.searchFilter = model.settings.defaultSearchFilter
                            model.mediaFilter = model.settings.defaultHomeFilter
                            model.genreResults.removeAll()
                            model.updateSearch()
                            Task { await model.loadHome() }
                        }
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .settingBubble()
                        
                        Button(clearPresses < 3 ? "Clear all data (press \(3 - clearPresses) more)" : "Confirm clear all data") {
                            clearPresses += 1
                            if clearPresses >= 3 { showClearConfirm = true }
                        }
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .settingBubble()
                    }
                    
                    VStack(alignment: .center, spacing: 8) {
                        Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, alignment: .center)
                        
                        Link("TMDB", destination: URL(string: "https://www.themoviedb.org/")!)
                            .font(.caption.bold())
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .onChange(of: model.settings) { _, _ in Storage.save(model.settings, key: "Vestigo.settings") }
            .alert("Delete all Vestigo data?", isPresented: $showClearConfirm) {
                Button("Cancel", role: .cancel) { clearPresses = 0 }
                Button("Delete", role: .destructive) {
                    model.clearAllData()
                    clearPresses = 0
                }
            } message: {
                Text("This removes watched items, ratings, watchlist, collections, episode progress, and settings from local storage.")
            }
        }
    }

        private struct ShortFilmsSettingsGroup: View {
            @ObservedObject var model: VestigoModel
            
            var body: some View {
                DisclosureGroup {
                    toggles
                } label: {
                    label
                }
                .foregroundStyle(.primary)
                .tint(model.settings.accentColor)
                .settingBubble()
                .onChange(of: model.settings.hideShortFilmsFromHome) { _, _ in
                    Task { await model.loadHome() }
                }
                .onChange(of: model.settings.hideShortFilmsFromSearch) { _, _ in
                    model.updateSearch()
                    
                    Task {
                        for route in model.searchPath {
                            await model.loadGenre(route.genre)
                        }
                    }
                }
                .onChange(of: model.settings.hideShortFilmsFromRecommended) { _, _ in
                    Task { await model.loadSmartRecommendations() }
                }
                .onChange(of: model.settings.hideShortFilmsFromCollectionRecommendations) { _, _ in
                    Task {
                        for collection in model.library.collections {
                            await model.loadCollectionRecommendations(for: collection.id)
                        }
                    }
                }
            }
            
            private var toggles: some View {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Hide from Home", isOn: $model.settings.hideShortFilmsFromHome)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                        .tint(model.settings.accentColor)
                        .padding(.trailing, 6)
                    
                    Toggle("Hide from Search", isOn: $model.settings.hideShortFilmsFromSearch)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                        .tint(model.settings.accentColor)
                        .padding(.trailing, 6)
                    
                    Toggle("Hide from Recommended", isOn: $model.settings.hideShortFilmsFromRecommended)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                        .tint(model.settings.accentColor)
                        .padding(.trailing, 6)
                    
                    Toggle("Hide from Collection Recommendations", isOn: $model.settings.hideShortFilmsFromCollectionRecommendations)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                        .tint(model.settings.accentColor)
                        .padding(.trailing, 6)
                }
                .padding(.top, 8)
            }
            
            private var label: some View {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Hide short films")
                        .font(.headline.bold())
                        .foregroundStyle(.primary)
                    
                    Text("Short films are detected from runtime after details load. Unknown runtimes stay visible.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

    private struct RatingPromptOverlay: ViewModifier {
        @ObservedObject var model: VestigoModel
        
        func body(content: Content) -> some View {
            ZStack {
                content
                
                if let item = model.pendingRatingPromptItem {
                    Color.black.opacity(0.32)
                        .ignoresSafeArea()
                        .transition(.opacity)
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Rate \(item.title)?")
                            .font(.title3.bold())
                            .foregroundStyle(.primary)
                        
                        Text("This feature can be disabled in Settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        StarRatingView(rating: $model.pendingRatingPromptValue)
                        
                        Button {
                            model.pendingRatingPromptMakeFavourite.toggle()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: model.pendingRatingPromptMakeFavourite ? "star.fill" : "star")
                                    .font(.headline.bold())
                                
                                Text(model.pendingRatingPromptMakeFavourite ? "Make favourite" : "Also make favourite")
                                    .font(.headline.bold())
                                
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 14)
                            .frame(height: 46)
                            .liquidGlass(cornerRadius: 22)
                            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        
                        HStack(spacing: 12) {
                            Button("Cancel") {
                                model.dismissPendingRatingPrompt()
                            }
                            .buttonStyle(.plain)
                            .font(.headline.bold())
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .liquidGlass(cornerRadius: 22)
                            
                            Button("Confirm") {
                                model.confirmPendingRatingPrompt()
                            }
                            .buttonStyle(.plain)
                            .font(.headline.bold())
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(model.settings.accentColor, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: 360, alignment: .leading)
                    .liquidGlass(cornerRadius: 30)
                    .padding(.horizontal, 22)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
                    .zIndex(50)
                }
            }
            .animation(.smooth(duration: 0.22), value: model.pendingRatingPromptItem?.key)
        }
    }
    
    private extension View {
        func ratingPromptOverlay(model: VestigoModel) -> some View {
            modifier(RatingPromptOverlay(model: model))
        }
    }
    
    
    // MARK: - Detail
    
    private struct DetailView: View {
        let item: MediaItem
        @ObservedObject var model: VestigoModel
        var allowsPersonSheet: Bool = true
        @State private var showCast = false
        @State private var showCollections = false
        @State private var selectedNestedItem: MediaItem?
        
        private var detail: MediaDetail? { model.detailsCache[item.key] }
        private var providers: [StreamingOption] { model.providerCache[item.key] ?? [] }
        
        private var selectedPersonBinding: Binding<PersonSummary?> {
            Binding(
                get: { allowsPersonSheet ? model.selectedPerson : nil },
                set: { model.selectedPerson = $0 }
            )
        }
        
        var body: some View {
            detailSheetSurface
                .favouriteReplacementOverlay(model: model)
                .presentationBackground(.clear)
                .presentationCornerRadius(54)
                .task { await model.loadDetail(item) }
                .onDisappear { model.playSheetDismissHaptic() }
                .sheet(isPresented: $showCollections) {
                    AddToCollectionSheet(item: item, model: model)
                }
                .sheet(item: selectedPersonBinding) { person in
                    PersonDetailView(person: person, model: model)
                }
                .sheet(item: $selectedNestedItem) { item in
                    DetailView(item: item, model: model, allowsPersonSheet: allowsPersonSheet)
                }
        }
        
        private var detailSheetSurface: some View {
            VStack(spacing: 0) {
                Capsule()
                    .fill(.white.opacity(0.46))
                    .frame(width: 48, height: 5)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                
                detailScroll
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .sheetLiquidGlass(cornerRadius: 48)
            .ignoresSafeArea(edges: .bottom)
        }
        
        private var detailScroll: some View {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    headerSection
                    ratingSection
                    detailButtons
                    overviewSection
                    actionSection
                    castSection
                    episodeSection
                    similarSection
                    providersSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 110)
            }
            .scrollClipDisabled(false)
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
            .scrollDismissesKeyboard(.immediately)
            .scrollIndicators(.hidden)
            .scrollViewTouchTuning(axis: .vertical)
        }
        
        private var headerSection: some View {
            HStack(alignment: .top, spacing: 16) {
                PosterView(item: item, width: 126, height: 188, isFavourite: model.library.isFavourite(item))
                
                VStack(alignment: .leading, spacing: 10) {
                    titleText
                    metadataText
                    ageRatingText
                    dateText
                    primaryCrewText
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
        }
        
        private var titleText: some View {
            Text(item.title)
                .font(.title2.bold())
                .foregroundStyle(.primary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        
        private var metadataText: some View {
            Text(detailMetadataLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        
        private var ageRatingText: some View {
            Text("Age rating: \(detail?.ageRating ?? "Not rated")")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
        }
        
        private var dateText: some View {
            Text(item.kind == .tv ? "Aired: \(detail?.yearRangeText ?? item.releaseYearText)" : "Date: \(item.releaseDate ?? "Unknown")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        
        @ViewBuilder private var primaryCrewText: some View {
            if let person = detail?.director ?? detail?.creator {
                Button {
                    model.selectedPerson = person
                } label: {
                    Text("\(item.kind == .tv ? "Creator" : "Director"): \(person.name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } else {
                Text("\(item.kind == .tv ? "Creator" : "Director"): Unknown")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        
        private var detailButtons: some View {
            HStack(spacing: 10) {
                DetailRowButton(
                    title: model.library.isInWatchlist(item.key) ? "Saved" : "Save",
                    systemName: model.library.isInWatchlist(item.key) ? "bookmark.fill" : "bookmark"
                ) {
                    model.toggleWatchlist(item)
                }
                
                if !item.isUpcoming {
                    DetailRowButton(
                        title: model.library.isWatched(item.key) ? "Watched" : "Watch",
                        systemName: model.library.isWatched(item.key) ? "checkmark.circle.fill" : "checkmark.circle"
                    ) {
                        model.toggleWatched(item)
                    }
                }
                
                DetailRowButton(
                    title: "Favourite",
                    systemName: model.library.isFavourite(item) ? "star.fill" : "star",
                    isEnabled: model.library.isWatched(item.key)
                ) {
                    model.requestToggleFavourite(item)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
        }
        
        @ViewBuilder private var ratingSection: some View {
            if model.library.isWatched(item.key) {
                StarRatingView(rating: Binding(
                    get: { model.library.ratings[item.key] ?? 0 },
                    set: { model.setRating($0, for: item) }
                ))
            }
        }
        
        private var overviewSection: some View {
            Text(item.overview.isEmpty ? "No overview available." : item.overview)
                .font(.body)
                .foregroundStyle(.primary.opacity(0.82))
        }
        
        private var actionSection: some View {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 10) {
                DetailRowButton(title: "Cast list", systemName: "person.2.fill") {
                    showCast.toggle()
                }
                
                DetailRowButton(title: "Add to collection", systemName: "folder.badge.plus") {
                    showCollections = true
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        
        private struct DetailRowButton: View {
            let title: String
            let systemName: String
            var isEnabled = true
            let action: () -> Void
            
            var body: some View {
                Button {
                    if isEnabled {
                        action()
                    }
                } label: {
                    Label(title, systemImage: systemName)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                        .foregroundStyle(isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary.opacity(0.55)))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .liquidGlass(cornerRadius: 22)
                        .opacity(isEnabled ? 1.0 : 0.42)
                        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
            }
        }
        
        @ViewBuilder private var castSection: some View {
            if showCast {
                CastCarousel(people: Array((detail?.castAndKeyCrew ?? []).prefix(22)), model: model)
            }
        }
        
        @ViewBuilder private var episodeSection: some View {
            if item.kind == .tv {
                EpisodeProgressView(show: item, model: model, seasons: detail?.seasons ?? [])
            }
        }
        
        @ViewBuilder private var similarSection: some View {
            if let similar = detail?.similar, !similar.isEmpty {
                MediaSection(title: "Movies and series like this", items: similar, hideWatchedForUpcoming: false, model: model, oneLineOnly: true, openItem: openNestedItem) { }
            }
        }
        
        private var providersSection: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text("Where to watch")
                    .sectionTitle()
                providerStatus
                providerRows
            }
        }
        
        @ViewBuilder private var providerStatus: some View {
            if item.isUpcoming {
                StatusBubble(title: "Theatrical status", text: "This release is upcoming. Streaming availability may not exist yet.")
            }
            if providers.isEmpty {
                StatusBubble(title: "No streaming prices found", text: "No US provider data with price and quality was returned for this title.")
            }
        }
        
        private var providerRows: some View {
            ForEach(providers.prefix(12)) { provider in
                ProviderRow(option: provider)
            }
        }
        
        private var detailMetadataLine: String {
            let rating = item.voteAverage.formatted(.number.precision(.fractionLength(1)))
            let yearText = item.kind == .tv ? (detail?.yearRangeText ?? item.releaseYearText) : item.releaseYearText
            var parts = [item.kind.displayLabel(runtime: detail?.runtime ?? item.runtime), yearText]
            
            if item.kind == .movie, let runtime = detail?.runtime, runtime > 0 {
                parts.append(formatRuntime(runtime))
            }
            
            if let originalLanguage = item.originalLanguage, !originalLanguage.isEmpty {
                parts.append("Original language: \(originalLanguage.uppercased())")
            }
            
            parts.append("TMDb \(rating)")
            return parts.joined(separator: " • ")
        }
        
        private func formatRuntime(_ minutes: Int) -> String {
            let hours = minutes / 60
            let mins = minutes % 60
            
            if hours > 0, mins > 0 {
                return "\(hours)h \(mins)m"
            } else if hours > 0 {
                return "\(hours)h"
            } else {
                return "\(mins)m"
            }
        }
        private func openNestedItem(_ item: MediaItem) {
            selectedNestedItem = item
        }
    }
    
    
    private struct CastCarousel: View {
        let people: [PersonSummary]
        @ObservedObject var model: VestigoModel
        
        var body: some View {
            content
        }
        
        @ViewBuilder private var content: some View {
            if people.isEmpty {
                StatusBubble(title: "No cast data", text: "TMDb did not return cast information for this title.")
            } else {
                carousel
            }
        }
        
        private var carousel: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text("Cast and crew")
                    .sectionTitle()
                scrollRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        
        private var scrollRow: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(people, id: \.id) { person in
                        CastPersonButton(person: person, model: model)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .scrollClipDisabled()
            .scrollIndicators(.hidden)
            .scrollViewTouchTuning(axis: .horizontal)
        }
    }
    
    private struct CastPersonButton: View {
        let person: PersonSummary
        @ObservedObject var model: VestigoModel
        
        var body: some View {
            Button {
                model.selectedPerson = person
            } label: {
                CastPersonCard(person: person)
            }
            .buttonStyle(.plain)
        }
    }
    
    private struct CastPersonCard: View {
        let person: PersonSummary
        
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                PersonImageView(person: person, width: 84, height: 112)
                
                Text(person.name)
                    .font(.caption.bold())
                    .lineLimit(1)
                    .frame(width: 84, alignment: .leading)
                
                Text(person.role.isEmpty ? "Cast" : person.role)
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(width: 84, alignment: .topLeading)
                    .frame(minHeight: 26, alignment: .topLeading)
            }
        }
    }
    
    private struct PersonDetailView: View {
        let person: PersonSummary
        @ObservedObject var model: VestigoModel
        @State private var selectedCreditItem: MediaItem?
        @State private var knownForSort: PersonKnownForSort = .rating
        
        private var credits: [MediaItem] {
            model.personCreditsCache[person.id] ?? []
        }
        
        private var sortedKnownForCredits: [MediaItem] {
            credits.sorted { lhs, rhs in
                switch knownForSort {
                case .rating:
                    if lhs.voteAverage != rhs.voteAverage {
                        return lhs.voteAverage > rhs.voteAverage
                    }
                case .date:
                    let lhsDate = lhs.releaseDateValue ?? .distantPast
                    let rhsDate = rhs.releaseDateValue ?? .distantPast
                    if lhsDate != rhsDate {
                        return lhsDate > rhsDate
                    }
                }
                
                return (lhs.releaseDateValue ?? .distantPast) > (rhs.releaseDateValue ?? .distantPast)
            }
        }
        
        var body: some View {
            personSheetSurface
                .presentationBackground(.clear)
                .presentationCornerRadius(54)
                .task {
                    await model.loadPersonCredits(person)
                }
                .onDisappear { model.playSheetDismissHaptic() }
                .sheet(item: $selectedCreditItem) { item in
                    DetailView(item: item, model: model, allowsPersonSheet: false)
                }
        }
        
        private var personSheetSurface: some View {
            VStack(spacing: 0) {
                Capsule()
                    .fill(.white.opacity(0.46))
                    .frame(width: 48, height: 5)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                
                scrollContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .sheetLiquidGlass(cornerRadius: 54)
            .ignoresSafeArea(edges: .bottom)
        }
        
        private var scrollContent: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    knownForTitle
                    PersonKnownForSortPicker(sort: $knownForSort)
                    
                    PersonCreditList(items: sortedKnownForCredits, model: model) { item in
                        selectedCreditItem = item
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .padding(.bottom, 110)
            }
            .scrollDismissesKeyboard(.immediately)
            .scrollIndicators(.hidden)
            .scrollViewTouchTuning()
        }
        
        private var header: some View {
            HStack(alignment: .top, spacing: 16) {
                PersonImageView(person: person, width: 112, height: 150)
                personText
            }
        }
        
        private var personText: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(person.name)
                    .font(.title2.bold())
                
                Text(person.role.isEmpty ? "Known for" : person.role)
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
            }
        }
        
        private var knownForTitle: some View {
            Text("Known for")
                .sectionTitle()
        }
    }
    
    private struct PersonCreditList: View {
        let items: [MediaItem]
        @ObservedObject var model: VestigoModel
        let openItem: (MediaItem) -> Void
        
        var body: some View {
            MediaList(
                items: items,
                model: model,
                showsRole: true,
                emptyTitle: "No credits found",
                emptyText: "TMDb did not return other movies or series for this person.",
                openItem: openItem
            )
        }
    }
    
    private struct MediaList: View {
        let items: [MediaItem]
        @ObservedObject var model: VestigoModel
        var showsRole: Bool = false
        var emptyTitle: String = "No results"
        var emptyText: String = "Nothing matched the current filter."
        var openItem: ((MediaItem) -> Void)? = nil
        
        var body: some View {
            if items.isEmpty {
                StatusBubble(title: emptyTitle, text: emptyText)
            } else {
                VStack(spacing: 12) {
                    ForEach(items) { item in
                        MediaListRow(item: item, model: model, showsRole: showsRole, openItem: openItem)
                    }
                }
            }
        }
    }
    
    private struct MediaListRow: View {
        let item: MediaItem
        @ObservedObject var model: VestigoModel
        @State private var showCollections = false
        var showsRole: Bool = false
        var openItem: ((MediaItem) -> Void)? = nil
        
        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                posterButton
                textAndActions
                Spacer(minLength: 0)
            }
            .padding(12)
            .liquidGlass(cornerRadius: 22)
            .appScrollTouchSafe()
            .contextMenu {
                MediaItemContextMenuActions(item: item, hideWatched: false, model: model, swipeContext: .none) {
                    showCollections = true
                }
            }
            .sheet(isPresented: $showCollections) {
                AddToCollectionSheet(item: item, model: model)
            }
        }
        
        private var posterButton: some View {
            Button {
                openItemFromList()
            } label: {
                PosterView(item: item, width: 72, height: 104, isFavourite: model.library.isFavourite(item))
            }
            .buttonStyle(.plain)
        }
        
        private var textAndActions: some View {
            VStack(alignment: .leading, spacing: 6) {
                infoButton
                actionButtons
            }
        }
        
        private var infoButton: some View {
            Button {
                openItemFromList()
            } label: {
                infoContent
            }
            .buttonStyle(.plain)
        }
        
        private var infoContent: some View {
            VStack(alignment: .leading, spacing: 6) {
                titleText
                metadataText
                roleText
                overviewText
            }
        }
        
        private var titleText: some View {
            Text(item.title)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(2)
        }
        
        private var metadataText: some View {
            Text(metadataLine)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
        }
        
        @ViewBuilder private var roleText: some View {
            if showsRole, let role = item.creditRole, !role.isEmpty {
                Text("Role: \(role)")
                    .font(.caption)
                    .foregroundStyle(.primary.opacity(0.78))
                    .lineLimit(2)
            }
        }
        
        @ViewBuilder private var overviewText: some View {
            if !item.overview.isEmpty {
                Text(item.overview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        
        private var actionButtons: some View {
            HStack(spacing: 7) {
                TileIconButton(systemName: model.library.isInWatchlist(item.key) ? "bookmark.fill" : "bookmark") {
                    model.toggleWatchlist(item)
                }
                
                if !item.isUpcoming {
                    TileIconButton(systemName: model.library.isWatched(item.key) ? "checkmark.circle.fill" : "checkmark.circle") {
                        model.toggleWatched(item)
                    }
                }
            }
            .padding(.top, 2)
        }
        
        private var metadataLine: String {
            let rating = item.voteAverage.formatted(.number.precision(.fractionLength(1)))
            return "\(item.kind.label) • \(item.releaseYearText) • TMDb \(rating)"
        }
        
        private func openItemFromList() {
            if let openItem {
                openItem(item)
            } else {
                model.selectedItem = item
            }
        }
    }
    
    private struct EpisodeProgressView: View {
        let show: MediaItem
        @ObservedObject var model: VestigoModel
        let seasons: [SeasonInfo]
        @State private var expandedSeasonNumbers = Set<Int>()
        
        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text("Episodes")
                    .sectionTitle()
                
                let usableSeasons = seasons.filter { $0.number > 0 }
                
                if usableSeasons.isEmpty {
                    StatusBubble(title: "No episode data", text: "TMDb did not return season or episode information for this series.")
                } else {
                    VStack(spacing: 10) {
                        ForEach(usableSeasons) { season in
                            SeasonDropdownView(
                                show: show,
                                season: season,
                                isExpanded: expandedSeasonNumbers.contains(season.number),
                                model: model
                            ) {
                                withAnimation(.smooth(duration: 0.22)) {
                                    if expandedSeasonNumbers.contains(season.number) {
                                        expandedSeasonNumbers.remove(season.number)
                                    } else {
                                        expandedSeasonNumbers.insert(season.number)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    private struct SeasonDropdownView: View {
        let show: MediaItem
        let season: SeasonInfo
        let isExpanded: Bool
        @ObservedObject var model: VestigoModel
        let toggle: () -> Void
        
        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Button(action: toggle) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(season.name)
                                .font(.headline.bold())
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            
                            Text(season.episodeCountAndRuntimeText)
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Spacer()
                        
                        Button(isSeasonWatched ? "Unwatch" : "Mark") {
                            model.markSeason(
                                show: show,
                                season: season.number,
                                episodeCount: max(season.episodeCount, season.episodes.count),
                                watched: !isSeasonWatched
                            )
                        }
                        .font(.caption.bold())
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .buttonStyle(.bordered)
                        .clipShape(Capsule())
                        
                        Image(systemName: "chevron.down")
                            .font(.caption.bold())
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .padding(12)
                }
                .buttonStyle(.plain)
                
                if isExpanded {
                    Divider()
                        .opacity(0.25)
                        .padding(.horizontal, 12)
                    
                    VStack(spacing: 8) {
                        ForEach(episodeRows) { episode in
                            EpisodeRowView(show: show, seasonNumber: season.number, episode: episode, model: model)
                        }
                    }
                    .padding(12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            .liquidGlass(cornerRadius: 22)
            .appScrollTouchSafe()
        }
        
        private var isSeasonWatched: Bool {
            let rows = episodeRows
            guard !rows.isEmpty else { return false }
            return rows.allSatisfy {
                model.library.isEpisodeWatched(showKey: show.key, season: season.number, episode: $0.number)
            }
        }
        
        private var episodeRows: [EpisodeInfo] {
            if !season.episodes.isEmpty {
                return season.episodes
            }
            
            return (1...max(season.episodeCount, 1)).map { number in
                EpisodeInfo(number: number, title: "Episode \(number)", airDate: nil, runtime: nil, stillPath: nil)
            }
        }
    }
    
    private struct EpisodeRowView: View {
        let show: MediaItem
        let seasonNumber: Int
        let episode: EpisodeInfo
        @ObservedObject var model: VestigoModel
        
        var body: some View {
            Button {
                model.toggleEpisode(show: show, season: seasonNumber, episode: episode.number)
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    EpisodeThumbnailView(url: episode.stillURL)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(episode.number). \(episode.title)")
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        
                        if !episodeMetadataText.isEmpty {
                            Text(episodeMetadataText)
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Spacer(minLength: 8)
                    
                    Image(systemName: isWatched ? "checkmark.circle.fill" : "circle")
                        .font(.title3.bold())
                        .foregroundStyle(isWatched ? model.settings.accentColor : .secondary)
                }
                .padding(10)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        
        private var isWatched: Bool {
            model.library.isEpisodeWatched(showKey: show.key, season: seasonNumber, episode: episode.number)
        }
        
        private var episodeMetadataText: String {
            var parts: [String] = []
            
            if let releaseDateText = episode.releaseDateText {
                parts.append(releaseDateText)
            }
            
            if let runtime = episode.runtime, runtime > 0 {
                parts.append("\(runtime) min")
            }
            
            return parts.joined(separator: " • ")
        }
    }
    
    private struct EpisodeThumbnailView: View {
        let url: URL?
        
        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(0.10))
                
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        Image(systemName: "tv")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 82, height: 46)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
    
    private struct AddToCollectionSheet: View {
        let item: MediaItem
        @ObservedObject var model: VestigoModel
        @State private var newName = ""
        
        var body: some View {
            ZStack {
                AppBackground(settings: model.settings)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Capsule()
                            .fill(.white.opacity(0.36))
                            .frame(width: 46, height: 5)
                            .padding(.top, 10)
                            .padding(.bottom, 6)
                            .frame(maxWidth: .infinity, alignment: .center)
                        
                        Text("Add to collection")
                            .font(.title2.bold())
                        
                        HStack {
                            TextField("New collection", text: $newName)
                                .padding(12)
                                .liquidGlass(cornerRadius: 18)
                            Button("Create") {
                                model.createCollection(named: newName, with: item)
                                newName = ""
                            }
                            .buttonStyle(.plain)
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)
                            .frame(width: 86, height: 44)
                            .liquidGlass(cornerRadius: 18)
                        }
                        
                        ForEach(model.library.collections) { collection in
                            let alreadyIn = collection.itemKeys.contains(item.key)
                            Button {
                                if alreadyIn { model.removeFromCollection(item, collectionID: collection.id) }
                                else { model.addToCollection(item, collectionID: collection.id) }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(collection.name).font(.headline)
                                        Text(alreadyIn ? "Already in collection" : "Tap to add")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: alreadyIn ? "checkmark.circle.fill" : "plus.circle")
                                }
                                .padding(14)
                                .liquidGlass(cornerRadius: 18)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, minHeight: 820, alignment: .topLeading)
                    .liquidGlass(cornerRadius: 36)
                    .padding(.horizontal, 6)
                    .padding(.top, 8)
                    .ignoresSafeArea(edges: .bottom)
                }
                .scrollDismissesKeyboard(.immediately)
                .scrollIndicators(.hidden)
                .scrollViewTouchTuning()
            }
            .presentationBackground(.clear)
            .presentationCornerRadius(36)
            .onDisappear { model.playSheetDismissHaptic() }
        }
    }
    
    // MARK: - Reusable Media UI
    
    private struct BaseScreen<Content: View>: View {
        let title: String
        @Binding var filter: MediaFilter
        let settings: AppSettings
        let headerAccessory: AnyView
        let contentTopPadding: CGFloat
        @ViewBuilder let content: Content
        
        init(
            title: String,
            filter: Binding<MediaFilter>,
            settings: AppSettings,
            headerAccessory: AnyView = AnyView(EmptyView()),
            contentTopPadding: CGFloat = 0,
            @ViewBuilder content: () -> Content
        ) {
            self.title = title
            self._filter = filter
            self.settings = settings
            self.headerAccessory = headerAccessory
            self.contentTopPadding = contentTopPadding
            self.content = content()
        }
        
        var body: some View {
            ZStack {
                AppBackground(settings: settings)
                    .ignoresSafeArea()
                
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(alignment: .center, spacing: 12) {
                            Text(title)
                                .font(.largeTitle.bold())
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            headerAccessory
                        }
                        
                        content
                    }
                    .padding(.top, contentTopPadding)
                    .padding(16)
                    .padding(.bottom, 94)
                    .containerRelativeFrame(.horizontal, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .contentShape(Rectangle())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .scrollClipDisabled(false)
                .scrollBounceBehavior(.basedOnSize, axes: .vertical)
                .scrollDismissesKeyboard(.immediately)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
                .scrollViewTouchTuning(axis: .vertical)
            }
        }
    }
    
    private struct MediaSection: View {
        let title: String
        let items: [MediaItem]
        let hideWatchedForUpcoming: Bool
        @ObservedObject var model: VestigoModel
        var oneLineOnly = true
        var openItem: ((MediaItem) -> Void)? = nil
        let openFull: () -> Void
        
        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    openFull()
                } label: {
                    HStack(spacing: 8) {
                        Text(title)
                            .sectionTitle()
                        
                        Spacer(minLength: 0)
                        
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                if items.isEmpty {
                    StatusBubble(title: "Nothing here yet", text: "This section will fill after more data loads or after you rate more watched items.")
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 14) {
                            ForEach(items.prefix(oneLineOnly ? 12 : items.count)) { item in
                                MediaTile(item: item, hideWatched: hideWatchedForUpcoming, model: model, openItem: openItem)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .scrollClipDisabled()
                    .scrollIndicators(.hidden)
                    .scrollViewTouchTuning(axis: .horizontal)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private struct MediaGridOrList: View {
        let items: [MediaItem]
        let hideWatchedForUpcoming: Bool
        @ObservedObject var model: VestigoModel
        var swipeContext: SwipeContext = .none
        var mode: ViewMode = .tile
        
        var body: some View {
            content
        }
        
        @ViewBuilder private var content: some View {
            if items.isEmpty {
                emptyState
            } else if mode == .list {
                listContent
            } else {
                gridContent
            }
        }
        
        private var emptyState: some View {
            StatusBubble(title: "No results", text: "Nothing matched the current filter.")
        }
        
        private var listContent: some View {
            MediaList(items: items, model: model)
        }
        
        private var gridContent: some View {
            LazyVGrid(columns: gridColumns, spacing: 18) {
                ForEach(items) { item in
                    MediaTile(item: item, hideWatched: hideWatchedForUpcoming, model: model, swipeContext: swipeContext)
                }
            }
        }
        
        private var gridColumns: [GridItem] {
            [GridItem(.adaptive(minimum: 148), spacing: 14)]
        }
    }
    
    private struct MediaItemContextMenuActions: View {
        let item: MediaItem
        let hideWatched: Bool
        @ObservedObject var model: VestigoModel
        var swipeContext: SwipeContext = .none
        let showCollections: () -> Void
        
        var body: some View {
            Button {
                showCollections()
            } label: {
                Label("Add to collection", systemImage: "folder.badge.plus")
            }
            
            Button {
                model.toggleWatchlist(item)
            } label: {
                Label(
                    model.library.isInWatchlist(item.key) ? "Remove saved" : "Save",
                    systemImage: model.library.isInWatchlist(item.key) ? "bookmark.slash" : "bookmark"
                )
            }
            
            if !hideWatched && !item.isUpcoming {
                Button {
                    model.toggleWatched(item)
                } label: {
                    Label(
                        model.library.isWatched(item.key) ? "Mark unwatched" : "Mark watched",
                        systemImage: model.library.isWatched(item.key) ? "checkmark.circle.fill" : "checkmark.circle"
                    )
                }
            }
            
            if model.library.isWatched(item.key) {
                Button {
                    model.requestToggleFavourite(item)
                } label: {
                    Label(
                        model.library.isFavourite(item) ? "Remove favourite" : "Mark favourite",
                        systemImage: model.library.isFavourite(item) ? "star.slash" : "star"
                    )
                }
            }
            
            if case .collection(let id) = swipeContext {
                Button(role: .destructive) {
                    model.removeFromCollection(item, collectionID: id)
                } label: {
                    Label("Remove from collection", systemImage: "trash")
                }
            }
        }
    }
    
    private struct MediaTile: View {
        let item: MediaItem
        let hideWatched: Bool
        @ObservedObject var model: VestigoModel
        var openItem: ((MediaItem) -> Void)? = nil
        var swipeContext: SwipeContext = .none
        @State private var showCollections = false
        
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Button { openTileItem() } label: {
                    PosterView(item: item, width: 148, height: 214, isFavourite: model.library.isFavourite(item))
                }
                .buttonStyle(.plain)
                
                .contextMenu {
                    MediaItemContextMenuActions(item: item, hideWatched: hideWatched, model: model, swipeContext: swipeContext) {
                        showCollections = true
                    }
                }
                .sheet(isPresented: $showCollections) {
                    AddToCollectionSheet(item: item, model: model)
                }
                
                Text(item.title)
                    .font(.subheadline.bold())
                    .lineLimit(2)
                    .frame(width: 148, alignment: .topLeading)
                    .frame(minHeight: 36, alignment: .topLeading)
                
                Text(item.isUpcoming ? item.releaseDateReadable : "\(item.releaseYearText) • TMDb \(item.voteAverage.formatted(.number.precision(.fractionLength(1))))")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                    .frame(width: 148, alignment: .leading)
                
                HStack(spacing: 7) {
                    TileIconButton(systemName: model.library.isInWatchlist(item.key) ? "bookmark.fill" : "bookmark") {
                        model.toggleWatchlist(item)
                    }
                    
                    if !hideWatched && !item.isUpcoming {
                        TileIconButton(systemName: model.library.isWatched(item.key) ? "checkmark.circle.fill" : "checkmark.circle") {
                            model.toggleWatched(item)
                        }
                    }
                }
                .frame(width: 148, alignment: .leading)
                .frame(minHeight: 30, alignment: .leading)
            }
            .frame(width: 148, alignment: .topLeading)
        }
        
        private func openTileItem() {
            if let openItem {
                openItem(item)
            } else {
                model.selectedItem = item
            }
        }
    }
    
    
    
    private struct PosterView: View {
        let item: MediaItem
        let width: CGFloat
        let height: CGFloat
        var isFavourite = false
        
        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: width * 0.18, style: .continuous)
                    .fill(item.genreGradient)
                AsyncImage(url: item.posterURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Image(systemName: item.kind == .movie ? "film" : "tv")
                            .font(.system(size: width * 0.25, weight: .bold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                LinearGradient(colors: [.clear, .black.opacity(0.42)], startPoint: .center, endPoint: .bottom)
                
                if isFavourite {
                    Image(systemName: "star.fill")
                        .font(.system(size: max(11, width * 0.095), weight: .black))
                        .foregroundStyle(.yellow)
                        .padding(max(5, width * 0.045))
                        .background(.black.opacity(0.64), in: Circle())
                        .padding(max(5, width * 0.045))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .zIndex(20)
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: width * 0.18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: width * 0.18, style: .continuous)
                    .stroke(.white.opacity(0.22), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.36), radius: 20, x: 0, y: 12)
            .shadow(color: .white.opacity(0.08), radius: 8, x: -3, y: -3)
        }
    }
    
    private struct PersonImageView: View {
        let person: PersonSummary
        let width: CGFloat
        let height: CGFloat
        
        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: width * 0.18, style: .continuous)
                    .fill(.white.opacity(0.12))
                
                AsyncImage(url: person.profileURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Image(systemName: "person.fill")
                            .font(.system(size: width * 0.32, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: width * 0.18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: width * 0.18, style: .continuous)
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.24), radius: 14, y: 8)
        }
    }
    
    private struct ProviderRow: View {
        let option: StreamingOption
        @Environment(\.openURL) private var openURL
        
        private var tappableURL: URL? {
            guard let rawURL = option.openURL?.trimmingCharacters(in: .whitespacesAndNewlines), !rawURL.isEmpty else {
                return nil
            }
            return URL(string: rawURL)
        }
        
        var body: some View {
            Button {
                guard let tappableURL else { return }
                openURL(tappableURL)
            } label: {
                HStack(spacing: 12) {
                    providerLogo
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text(option.cleanedServiceName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        
                        Text(option.cleanedAvailabilityLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    
                    Spacer()
                    
                    if tappableURL != nil {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(.plain)
            .liquidGlass(cornerRadius: 22)
            .opacity(tappableURL == nil ? 0.72 : 1.0)
            .appScrollTouchSafe()
        }
        
        private var providerLogo: some View {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(0.13))
                
                if let url = option.logoURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 52, height: 52)
                                .clipped()
                        default:
                            Text(option.serviceShort)
                                .font(.caption.bold())
                        }
                    }
                } else {
                    Text(option.serviceShort)
                        .font(.caption.bold())
                }
            }
            .frame(width: 52, height: 52)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
    
    private extension StreamingOption {
        var cleanedServiceName: String {
            let trimmed = serviceName.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Unknown service" : trimmed
        }
        
        var cleanedAvailabilityLine: String {
            let parts = [cleanedTypeText, cleanedPriceText, cleanedQualityText]
                .compactMap { $0 }
            
            if parts.isEmpty {
                return "Availability details not provided"
            }
            
            return parts.joined(separator: " • ")
        }
        
        private var cleanedTypeText: String? {
            let trimmed = type.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.isUnknownPlaceholder else { return nil }
            return trimmed.capitalized
        }
        
        private var cleanedPriceText: String? {
            let trimmed = priceText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.isUnknownPlaceholder else { return nil }
            return trimmed
        }
        
        private var cleanedQualityText: String? {
            let trimmed = qualityText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.isUnknownPlaceholder else { return nil }
            return trimmed
        }
        
        var logoURL: URL? {
            guard let domain = serviceLogoDomain else { return nil }
            
            var components = URLComponents(string: "https://www.google.com/s2/favicons")
            components?.queryItems = [
                URLQueryItem(name: "sz", value: "128"),
                URLQueryItem(name: "domain", value: domain)
            ]
            
            return components?.url
        }
        
        private var serviceLogoDomain: String? {
            let normalized = cleanedServiceName
                .lowercased()
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "+", with: "plus")
                .replacingOccurrences(of: ".", with: "")
                .replacingOccurrences(of: "-", with: "")
            
            if normalized.contains("netflix") { return "netflix.com" }
            if normalized.contains("primevideo") || normalized.contains("amazon") { return "primevideo.com" }
            if normalized.contains("disney") { return "disneyplus.com" }
            if normalized.contains("hulu") { return "hulu.com" }
            if normalized.contains("max") || normalized.contains("hbomax") { return "max.com" }
            if normalized.contains("appletv") || normalized.contains("itunes") { return "tv.apple.com" }
            if normalized.contains("paramount") { return "paramountplus.com" }
            if normalized.contains("peacock") { return "peacocktv.com" }
            if normalized.contains("starz") { return "starz.com" }
            if normalized.contains("showtime") { return "showtime.com" }
            if normalized.contains("youtube") { return "youtube.com" }
            if normalized.contains("googleplay") { return "play.google.com" }
            if normalized.contains("vudu") || normalized.contains("fandango") { return "athome.fandango.com" }
            if normalized.contains("microsoft") { return "microsoft.com" }
            if normalized.contains("amc") { return "amcplus.com" }
            if normalized.contains("crunchyroll") { return "crunchyroll.com" }
            if normalized.contains("tubi") { return "tubitv.com" }
            if normalized.contains("pluto") { return "pluto.tv" }
            if normalized.contains("roku") { return "therokuchannel.roku.com" }
            if normalized.contains("kanopy") { return "kanopy.com" }
            if normalized.contains("plex") { return "plex.tv" }
            if normalized.contains("mubi") { return "mubi.com" }
            if normalized.contains("criterion") { return "criterionchannel.com" }
            if normalized.contains("hoopla") { return "hoopladigital.com" }
            if normalized.contains("freevee") { return "amazon.com" }
            
            return nil
        }
    }
    
    private extension String {
        var isUnknownPlaceholder: Bool {
            let normalized = trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized == "unknown" || normalized == "unknown price" || normalized == "price unknown" || normalized == "unknown quality" || normalized == "quality unknown" || normalized == "n/a" || normalized == "na" || normalized == "none"
        }
        
        var normalizedForMatching: String {
            lowercased()
                .replacingOccurrences(of: "&", with: "and")
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
    }
    
    
    private struct SearchBubble: View {
        @Binding var text: String
        var isFocused: FocusState<Bool>.Binding
        var onSubmit: () -> Void = {}
        
        var body: some View {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                TextField("Search movies, series, people...", text: $text)
                    .textFieldStyle(.plain)
                    .focused(isFocused)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled(false)
                    .submitLabel(.search)
                    .onSubmit {
                        onSubmit()
                    }
            }
            .padding(.horizontal, 14)
            .frame(height: 52)
            .liquidGlass(cornerRadius: 24)
        }
    }
    
    // MARK: - Search Filter for Movies, TV, People
    private enum SearchFilter: String, Codable, CaseIterable, Identifiable {
        case movie
        case tv
        case both
        case people
        
        var id: String { rawValue }
        
        var title: String {
            switch self {
            case .movie: return "Movies"
            case .tv: return "Series"
            case .both: return "Both"
            case .people: return "People"
            }
        }
        
        var mediaFilter: MediaFilter? {
            switch self {
            case .movie: return .movie
            case .tv: return .tv
            case .both: return .both
            case .people: return nil
            }
        }
    }
    
    private enum SearchFilterSection: String, CaseIterable, Identifiable {
        case runtime
        case rating
        case date
        
        var id: String { rawValue }
        
        var title: String {
            switch self {
            case .runtime: return "Runtime"
            case .rating: return "Rating"
            case .date: return "Date"
            }
        }
    }
    
    private enum SearchRuntimeFilter: String, CaseIterable, Identifiable {
        case underOneHour
        case oneToOneAndHalf
        case oneAndHalfToTwo
        case twoToTwoAndHalf
        case twoAndHalfToThree
        case overThree
        
        var id: String { rawValue }
        
        var title: String {
            switch self {
            case .underOneHour: return "<1hr"
            case .oneToOneAndHalf: return "1–1.5hr"
            case .oneAndHalfToTwo: return "1.5–2hr"
            case .twoToTwoAndHalf: return "2–2.5hr"
            case .twoAndHalfToThree: return "2.5–3hr"
            case .overThree: return ">3hr"
            }
        }
        
        func contains(_ runtime: Int) -> Bool {
            switch self {
            case .underOneHour:
                return runtime < 60
            case .oneToOneAndHalf:
                return runtime >= 60 && runtime < 90
            case .oneAndHalfToTwo:
                return runtime >= 90 && runtime < 120
            case .twoToTwoAndHalf:
                return runtime >= 120 && runtime < 150
            case .twoAndHalfToThree:
                return runtime >= 150 && runtime < 180
            case .overThree:
                return runtime >= 180
            }
        }
    }
    
    private enum SearchRatingFilter: Int, CaseIterable, Identifiable {
        case zero = 0
        case one = 1
        case two = 2
        case three = 3
        case four = 4
        case five = 5
        case six = 6
        case seven = 7
        case eight = 8
        case nine = 9
        
        var id: Int { rawValue }
        var minimumRating: Double { Double(rawValue) }
        var title: String { "TMDb \(rawValue)+" }
    }
    
    private enum SearchDateFilter: String, CaseIterable, Identifiable {
        case lastYear
        case lastTenYears
        case lastTwentyYears
        case lastThirtyYears
        case lastFortyYears
        case olderThanFortyYears
        
        var id: String { rawValue }
        
        var title: String {
            switch self {
            case .lastYear: return "Last year"
            case .lastTenYears: return "Last 10 years"
            case .lastTwentyYears: return "Last 20 years"
            case .lastThirtyYears: return "Last 30 years"
            case .lastFortyYears: return "Last 40 years"
            case .olderThanFortyYears: return "Older than 40 years"
            }
        }
        
        func contains(_ date: Date) -> Bool {
            let calendar = Calendar.current
            let now = Date()
            let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: now) ?? now
            let tenYearsAgo = calendar.date(byAdding: .year, value: -10, to: now) ?? now
            let twentyYearsAgo = calendar.date(byAdding: .year, value: -20, to: now) ?? now
            let thirtyYearsAgo = calendar.date(byAdding: .year, value: -30, to: now) ?? now
            let fortyYearsAgo = calendar.date(byAdding: .year, value: -40, to: now) ?? now
            
            switch self {
            case .lastYear:
                return date >= oneYearAgo
            case .lastTenYears:
                return date >= tenYearsAgo
            case .lastTwentyYears:
                return date >= twentyYearsAgo
            case .lastThirtyYears:
                return date >= thirtyYearsAgo
            case .lastFortyYears:
                return date >= fortyYearsAgo
            case .olderThanFortyYears:
                return date < fortyYearsAgo
            }
        }
    }
    
    private struct FilterPills: View {
        @Binding var filter: MediaFilter
        let options: [MediaFilter]
        let onChange: () -> Void
        
        var body: some View {
            Picker("Filter", selection: $filter) {
                ForEach(options) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .liquidGlass(cornerRadius: 18)
            .onChange(of: filter) { _, _ in
                onChange()
            }
        }
    }
    
    private struct SortPicker: View {
        @Binding var sort: SortOption
        let includeMyRating: Bool
        
        var body: some View {
            Picker("Sort", selection: $sort) {
                Text("Released").tag(SortOption.releaseDate)
                
                if includeMyRating {
                    Text("My rating").tag(SortOption.myRating)
                }
                
                Text("TMDb").tag(SortOption.tmdbRating)
            }
            .pickerStyle(.segmented)
            .liquidGlass(cornerRadius: 18)
        }
    }
    
    private struct StarRatingView: View {
        @Binding var rating: Double
        
        var body: some View {
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { index in
                    Button { rating = nextRating(for: index) } label: {
                        Image(systemName: starName(index))
                            .font(.title2)
                            .foregroundStyle(.yellow)
                    }
                    .buttonStyle(.plain)
                }
                Text(rating.formatted(.number.precision(.fractionLength(1))))
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .liquidGlass(cornerRadius: 20)
        }
        
        private func starName(_ index: Int) -> String {
            let value = Double(index)
            if rating >= value { return "star.fill" }
            if rating >= value - 0.5 { return "star.leadinghalf.filled" }
            return "star"
        }
        
        private func nextRating(for index: Int) -> Double {
            let full = Double(index)
            if rating == full { return full - 0.5 }
            return full
        }
    }
    
    private struct StarDisplay: View {
        let rating: Double
        var body: some View {
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { i in
                    Image(systemName: rating >= Double(i) ? "star.fill" : (rating >= Double(i) - 0.5 ? "star.leadinghalf.filled" : "star"))
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
            }
        }
    }
    
    
    private struct SmallActionButton: View {
        let title: String
        let systemName: String
        let action: () -> Void
        
        var body: some View {
            Button(action: action) {
                Label(title, systemImage: systemName)
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, 9)
                    .frame(width: 68, height: 28)
                    .liquidGlass(cornerRadius: 14)
            }
            .buttonStyle(.plain)
        }
    }
    
    
    private struct DetailActionButton: View {
        let title: String
        let systemName: String
        let action: () -> Void
        
        var body: some View {
            Button(action: action) {
                Label(title, systemImage: systemName)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: 150, height: 34)
                    .liquidGlass(cornerRadius: 17)
            }
            .buttonStyle(.plain)
        }
    }
    
    private struct TileIconButton: View {
        let systemName: String
        let action: () -> Void
        
        var body: some View {
            Button(action: action) {
                Image(systemName: systemName)
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 32, height: 28)
                    .liquidGlass(cornerRadius: 14)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(systemName.contains("bookmark") ? "Save" : "Watched")
        }
    }
    
    private struct RemoteImageView: View {
        let url: URL?
        let fallback: AnyView
        @State private var platformImage: PlatformImage?
        @State private var loadedURL: URL?
        
        var body: some View {
            ZStack {
                if let platformImage {
                    platformImageView(platformImage)
                } else {
                    fallback
                }
            }
            .task(id: url) {
                await loadImage()
            }
        }
        
        @ViewBuilder
        private func platformImageView(_ image: PlatformImage) -> some View {
#if canImport(UIKit)
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
#elseif canImport(AppKit)
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
#endif
        }
        
        @MainActor
        private func setLoadedImage(_ image: PlatformImage?, for url: URL?) {
            platformImage = image
            loadedURL = url
        }
        
        private func loadImage() async {
            guard let url else {
                setLoadedImage(nil, for: nil)
                return
            }
            
            if loadedURL == url, platformImage != nil {
                return
            }
            
            do {
                let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    setLoadedImage(nil, for: url)
                    return
                }
                guard (200...299).contains(httpResponse.statusCode) else {
                    setLoadedImage(nil, for: url)
                    return
                }
                guard let image = PlatformImage(data: data) else {
                    setLoadedImage(nil, for: url)
                    return
                }
                setLoadedImage(image, for: url)
            } catch {
                setLoadedImage(nil, for: url)
            }
        }
    }
    
    private struct GenreIconTile: View {
        let genre: GenreDefinition
        
        var body: some View {
            ZStack(alignment: .bottomLeading) {
                genreImage
                
                LinearGradient(
                    colors: [
                        .black.opacity(0.06),
                        .black.opacity(0.30),
                        .black.opacity(0.84)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                
                Text(genre.name)
                    .font(.system(size: 19, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .shadow(color: .black.opacity(0.80), radius: 8, y: 3)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 11)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 96)
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.30), radius: 14, y: 9)
        }
        
        private var genreImage: some View {
            RemoteImageView(url: resolvedImageURL, fallback: AnyView(fallbackImage))
                .id(genre.name + "-" + (resolvedImageURL?.absoluteString ?? "fallback"))
                .frame(maxWidth: .infinity)
                .frame(height: 96)
                .clipped()
        }
        
        private var resolvedImageURL: URL? {
            switch genre.tmdbID {
            case 28:
                return URL(string: "https://image.tmdb.org/t/p/w780/yFihWxQcmqcaBR31QM6Y8gT6aYV.jpg")
            case 2000:
                return URL(string: "https://image.tmdb.org/t/p/w780/qJ2tW6WMUDux911r6m7haRef0WH.jpg")
            case 2010:
                return URL(string: "https://image.tmdb.org/t/p/w780/gEU2QniE6E77NI6lCU6MxlNBvIx.jpg")
            default:
                return genre.imageURLValue
            }
        }
        
        private var fallbackImage: some View {
            ZStack {
                fallbackBackdrop
                
                LinearGradient(
                    colors: [.clear, .black.opacity(0.16), .black.opacity(0.48)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        
        @ViewBuilder private var fallbackBackdrop: some View {
            switch genre.name {
            case "00s":
                ZStack {
                    LinearGradient(colors: [.blue.opacity(0.92), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Circle()
                        .fill(.cyan.opacity(0.34))
                        .frame(width: 140, height: 140)
                        .blur(radius: 12)
                        .offset(x: 55, y: -36)
                    Image(systemName: "circle.grid.cross.fill")
                        .font(.system(size: 48, weight: .black))
                        .foregroundStyle(.white.opacity(0.28))
                        .offset(x: 42, y: -10)
                }
            case "10s":
                ZStack {
                    LinearGradient(colors: [.indigo.opacity(0.92), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Circle()
                        .fill(.purple.opacity(0.36))
                        .frame(width: 140, height: 140)
                        .blur(radius: 14)
                        .offset(x: 50, y: -34)
                    Image(systemName: "sparkles")
                        .font(.system(size: 48, weight: .black))
                        .foregroundStyle(.white.opacity(0.30))
                        .offset(x: 44, y: -12)
                }
            default:
                ZStack {
                    genre.gradient
                    LinearGradient(
                        colors: [.white.opacity(0.10), .clear, .black.opacity(0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: fallbackSymbol)
                        .font(.system(size: 34, weight: .black))
                        .foregroundStyle(.white.opacity(0.36))
                        .offset(x: 32, y: -10)
                }
            }
        }
        
        private var fallbackSymbol: String {
            switch genre.name {
            case "Action": return "flame.fill"
            case "Sci-Fi": return "sparkles"
            case "Fantasy": return "wand.and.stars"
            case "Drama": return "theatermasks.fill"
            case "Horror": return "moon.fill"
            case "Animation": return "paintpalette.fill"
            case "Crime": return "magnifyingglass"
            case "Comedy": return "face.smiling.fill"
            case "80s": return "clock.fill"
            case "90s": return "clock.fill"
            case "00s": return "clock.fill"
            case "10s": return "clock.fill"
            default: return "film.fill"
            }
        }
    }
    
    private struct CollectionRow: View {
        let collection: MediaCollection
        let count: Int
        
        var body: some View {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(collection.name).font(.headline)
                    Text(collection.isDynamic ? "Dynamic collection • \(count) items" : "Custom collection • \(count) items")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .liquidGlass(cornerRadius: 22)
            .appScrollTouchSafe()
        }
    }
    
    
    private struct StatusBubble: View {
        let title: String
        let text: String
        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline.bold())
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .liquidGlass(cornerRadius: 22)
            .appScrollTouchSafe()
        }
    }
    
    private struct AppBackground: View {
        let settings: AppSettings
        
        var body: some View {
            Group {
                if settings.usePlainBackground {
                    settings.appearance == .dark ? Color.black : Color.white
                } else {
                    GeometryReader { proxy in
                        let topInset = proxy.safeAreaInsets.top
                        let bottomInset = proxy.safeAreaInsets.bottom
                        let fullHeight = proxy.size.height + topInset + bottomInset
                        
                        ZStack(alignment: .topLeading) {
                            LinearGradient(
                                colors: backgroundColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .frame(width: proxy.size.width, height: fullHeight)
                            
                            Circle()
                                .fill(settings.accentColor.opacity(settings.appearance == .dark ? 0.34 : 0.28))
                                .frame(width: 360, height: 360)
                                .blur(radius: 70)
                                .position(x: 50, y: -80)
                            
                            Circle()
                                .fill(settings.accentColor.opacity(settings.appearance == .dark ? 0.24 : 0.20))
                                .frame(width: 360, height: 360)
                                .blur(radius: 78)
                                .position(x: proxy.size.width + 40, y: 270)
                            
                            Circle()
                                .fill(settings.accentColor.opacity(settings.appearance == .dark ? 0.18 : 0.16))
                                .frame(width: 420, height: 420)
                                .blur(radius: 95)
                                .position(x: proxy.size.width * 0.62, y: 720)
                        }
                        .frame(width: proxy.size.width, height: fullHeight, alignment: .topLeading)
                        .offset(y: -topInset)
                    }
                }
            }
            .ignoresSafeArea()
        }
        
        private var backgroundColors: [Color] {
            if settings.appearance == .dark {
                return [
                    settings.accentColor.opacity(0.22),
                    Color(red: 0.04, green: 0.045, blue: 0.075),
                ]
            } else {
                return [
                    settings.accentColor.opacity(0.22),
                    Color.white,
                    settings.accentColor.opacity(0.16),
                    Color(red: 0.90, green: 0.93, blue: 0.98)
                ]
            }
        }
    }
    
    // MARK: - API Services
    
    private struct TMDbService {
        private let apiKey = "98eefd757e87d7462c815c87d8aa2ce4"
        private let base = "https://api.themoviedb.org/3"
        
        func trending(filter: MediaFilter) async throws -> [MediaItem] {
            try await fetchList(path: "/trending/\(filter.tmdbPath)/week", query: [])
        }
        
        func popular(filter: MediaFilter) async throws -> [MediaItem] {
            if filter == .both {
                async let movies = fetchList(path: "/movie/popular", query: [])
                async let tv = fetchList(path: "/tv/popular", query: [])
                return try await (movies + tv).sorted { $0.voteAverage > $1.voteAverage }
            }
            return try await fetchList(path: "/\(filter.tmdbPath)/popular", query: [])
        }
        
        func newReleases(filter: MediaFilter) async throws -> [MediaItem] {
            var items: [MediaItem] = []
            if filter != .tv {
                items += try await fetchList(path: "/movie/now_playing", query: [URLQueryItem(name: "region", value: "US")])
            }
            if filter != .movie {
                items += try await fetchList(path: "/tv/on_the_air", query: [])
            }
            return items
        }
        
        func upcoming(filter: MediaFilter) async throws -> [MediaItem] {
            var items: [MediaItem] = []
            if filter != .tv {
                items += try await fetchList(path: "/movie/upcoming", query: [URLQueryItem(name: "region", value: "US")])
            }
            if filter != .movie {
                items += try await fetchList(path: "/tv/airing_today", query: [])
            }
            return items
        }
        
        func search(query: String, filter: MediaFilter, includeAdult: Bool = false) async throws -> [MediaItem] {
            let path = filter == .both ? "/search/multi" : "/search/\(filter.tmdbPath)"
            return try await fetchList(path: path, query: [
                URLQueryItem(name: "query", value: query),
                URLQueryItem(name: "include_adult", value: includeAdult ? "true" : "false")
            ])
            .filter { $0.kind != .person }
        }
        
        func searchPeople(query: String, includeAdult: Bool = false) async throws -> [PersonSummary] {
            let response: TMDbPersonSearchResponse = try await fetch(path: "/search/person", query: [
                URLQueryItem(name: "query", value: query),
                URLQueryItem(name: "include_adult", value: includeAdult ? "true" : "false")
            ])
            
            return response.results
                .map { dto in
                    PersonSummary(dto, fallbackRole: dto.knownForDepartment ?? "Person")
                }
                .uniquedPeople()
        }
        
        func contextualSearch(query: String, filter: MediaFilter, includeAdult: Bool = false) async throws -> [MediaItem] {
            let found = try await search(query: query, filter: filter, includeAdult: includeAdult)
            var more: [MediaItem] = []
            for item in found {
                more += (try? await recommendations(for: item.key)) ?? []
                more += (try? await sameSeriesOrSimilar(for: item.key)) ?? []
            }
            return more
        }
        
        func discover(genreID: Int, filter: MediaFilter, sort: GenreSort) async throws -> [MediaItem] {
            if Self.isEraID(genreID) {
                return try await discoverEra(eraID: genreID, filter: filter, sort: sort)
            }
            
            return try await curatedCategoryItems(genreID: genreID, filter: filter)
        }
        
        private func curatedCategoryItems(genreID: Int, filter: MediaFilter) async throws -> [MediaItem] {
            guard let entries = Self.curatedCategoryEntries[genreID] else { return [] }
            var resolved: [MediaItem] = []
            
            let filteredEntries = entries.filter { entry in
                switch filter {
                case .both:
                    return true
                case .movie:
                    return entry.kind == .movie
                case .tv:
                    return entry.kind == .tv
                }
            }
            
            for entry in filteredEntries.prefix(50) {
                if let item = try await resolveCuratedEntry(entry) {
                    resolved.append(item)
                }
            }
            
            return resolved
                .uniqued()
                .prefixArray(50)
        }
        
        private func resolveCuratedEntry(_ entry: CuratedCategoryEntry) async throws -> MediaItem? {
            let results = try await search(query: entry.title, filter: entry.filter)
            let normalizedTarget = Self.normalizedTitle(entry.title)
            
            return results.first { item in
                item.kind == entry.kind && Self.normalizedTitle(item.title) == normalizedTarget
            } ?? results.first { item in
                item.kind == entry.kind && Self.normalizedTitle(item.title).contains(normalizedTarget)
            } ?? results.first { item in
                item.kind == entry.kind
            }
        }
        
        private static func normalizedTitle(_ title: String) -> String {
            title
                .lowercased()
                .replacingOccurrences(of: "&", with: "and")
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
        
        private struct CuratedCategoryEntry {
            let title: String
            let kind: MediaKind
            
            var filter: MediaFilter {
                kind == .tv ? .tv : .movie
            }
        }
        
        private static func movie(_ title: String) -> CuratedCategoryEntry {
            CuratedCategoryEntry(title: title, kind: .movie)
        }
        
        private static func show(_ title: String) -> CuratedCategoryEntry {
            CuratedCategoryEntry(title: title, kind: .tv)
        }
        
        private static let curatedCategoryEntries: [Int: [CuratedCategoryEntry]] = [
            28: [
                movie("Die Hard"), movie("Terminator 2: Judgment Day"), movie("Mad Max: Fury Road"), movie("The Raid"), movie("John Wick"),
                movie("Mission: Impossible - Fallout"), movie("The Bourne Ultimatum"), movie("Speed"), movie("Police Story"), movie("Hard Boiled"),
                movie("Enter the Dragon"), movie("The Killer"), movie("Lethal Weapon"), movie("Predator"), movie("First Blood"),
                movie("Casino Royale"), movie("Skyfall"), movie("Top Gun: Maverick"), movie("The Fugitive"), movie("Heat"),
                movie("The Rock"), movie("True Lies"), movie("Face/Off"), movie("Con Air"), movie("Point Break"),
                movie("Kill Bill: Vol. 1"), movie("Kill Bill: Vol. 2"), movie("The Man from Nowhere"), movie("The Night Comes for Us"), movie("Ong-Bak"),
                movie("Dredd"), movie("Nobody"), movie("The Equalizer"), movie("Taken"), movie("Man on Fire"),
                movie("Extraction"), movie("Baby Driver"), movie("Atomic Blonde"), movie("Sicario"), movie("The Warriors"),
                show("24"), show("Reacher"), show("Jack Ryan"), show("The Night Manager"), show("Warrior"),
                show("The Terminal List"), show("Strike Back"), show("Banshee"), show("The Punisher"), show("Gangs of London")
            ],
            878: [
                movie("Blade Runner"), movie("Blade Runner 2049"), movie("The Matrix"), movie("Inception"), movie("Interstellar"),
                movie("2001: A Space Odyssey"), movie("Alien"), movie("Aliens"), movie("The Terminator"), movie("Back to the Future"),
                movie("The Empire Strikes Back"), movie("Star Wars"), movie("Return of the Jedi"), movie("Arrival"), movie("Dune"),
                movie("Dune: Part Two"), movie("The Martian"), movie("Minority Report"), movie("Children of Men"), movie("Ex Machina"),
                movie("Her"), movie("Eternal Sunshine of the Spotless Mind"), movie("WALL·E"), movie("District 9"), movie("Moon"),
                movie("A.I. Artificial Intelligence"), movie("Gattaca"), movie("The Fifth Element"), movie("Planet of the Apes"), movie("Rise of the Planet of the Apes"),
                movie("Dawn of the Planet of the Apes"), movie("War for the Planet of the Apes"), movie("Edge of Tomorrow"), movie("Looper"), movie("Source Code"),
                movie("Contact"), movie("Close Encounters of the Third Kind"), movie("Solaris"), movie("12 Monkeys"), movie("The Thing"),
                show("The Expanse"), show("Black Mirror"), show("Dark"), show("Severance"), show("Battlestar Galactica"),
                show("Doctor Who"), show("Fringe"), show("Westworld"), show("Foundation"), show("For All Mankind")
            ],
            14: [
                movie("The Lord of the Rings: The Fellowship of the Ring"), movie("The Lord of the Rings: The Two Towers"), movie("The Lord of the Rings: The Return of the King"), movie("The Wizard of Oz"), movie("Pan's Labyrinth"),
                movie("Harry Potter and the Prisoner of Azkaban"), movie("Harry Potter and the Deathly Hallows: Part 2"), movie("The Princess Bride"), movie("The NeverEnding Story"), movie("Labyrinth"),
                movie("The Dark Crystal"), movie("Willow"), movie("Stardust"), movie("Big Fish"), movie("Edward Scissorhands"),
                movie("The Shape of Water"), movie("Beauty and the Beast"), movie("Spirited Away"), movie("Howl's Moving Castle"), movie("Princess Mononoke"),
                movie("Crouching Tiger, Hidden Dragon"), movie("The Green Knight"), movie("The Chronicles of Narnia: The Lion, the Witch and the Wardrobe"), movie("The Hobbit: An Unexpected Journey"), movie("The Hobbit: The Desolation of Smaug"),
                movie("The Hobbit: The Battle of the Five Armies"), movie("Excalibur"), movie("Jason and the Argonauts"), movie("Clash of the Titans"), movie("The Fall"),
                movie("A Monster Calls"), movie("The Secret of Kells"), movie("Song of the Sea"), movie("Kubo and the Two Strings"), movie("Coraline"),
                movie("The Tale of The Princess Kaguya"), movie("The Red Turtle"), movie("Only Lovers Left Alive"), movie("Wings of Desire"), movie("Time Bandits"),
                show("Game of Thrones"), show("House of the Dragon"), show("The Witcher"), show("His Dark Materials"), show("The Sandman"),
                show("Merlin"), show("Once Upon a Time"), show("The Dark Crystal: Age of Resistance"), show("Shadow and Bone"), show("The Legend of Vox Machina")
            ],
            18: [
                movie("The Shawshank Redemption"), movie("The Godfather"), movie("The Godfather Part II"), movie("12 Angry Men"), movie("Schindler's List"),
                movie("The Green Mile"), movie("Forrest Gump"), movie("One Flew Over the Cuckoo's Nest"), movie("Good Will Hunting"), movie("Dead Poets Society"),
                movie("The Truman Show"), movie("The Social Network"), movie("There Will Be Blood"), movie("No Country for Old Men"), movie("Whiplash"),
                movie("Moonlight"), movie("Parasite"), movie("A Beautiful Mind"), movie("American Beauty"), movie("Million Dollar Baby"),
                movie("The Pianist"), movie("Life Is Beautiful"), movie("City of God"), movie("Amadeus"), movie("Raging Bull"),
                movie("Taxi Driver"), movie("Apocalypse Now"), movie("The Deer Hunter"), movie("Rocky"), movie("Rain Man"),
                movie("The King's Speech"), movie("Spotlight"), movie("Manchester by the Sea"), movie("Marriage Story"), movie("Nomadland"),
                movie("The Father"), movie("Minari"), movie("Sound of Metal"), movie("A Separation"), movie("Ikiru"),
                show("Breaking Bad"), show("Better Call Saul"), show("The Sopranos"), show("The Wire"), show("Mad Men"),
                show("Succession"), show("The Crown"), show("Six Feet Under"), show("Friday Night Lights"), show("The Bear")
            ],
            27: [
                movie("Psycho"), movie("The Shining"), movie("Alien"), movie("The Exorcist"), movie("Halloween"),
                movie("The Texas Chain Saw Massacre"), movie("A Nightmare on Elm Street"), movie("The Thing"), movie("Rosemary's Baby"), movie("Jaws"),
                movie("Night of the Living Dead"), movie("Dawn of the Dead"), movie("The Fly"), movie("Scream"), movie("Get Out"),
                movie("Hereditary"), movie("Midsommar"), movie("The Babadook"), movie("It Follows"), movie("The Witch"),
                movie("Let the Right One In"), movie("Train to Busan"), movie("28 Days Later"), movie("The Descent"), movie("The Conjuring"),
                movie("Insidious"), movie("Sinister"), movie("The Ring"), movie("Ringu"), movie("Audition"),
                movie("The Orphanage"), movie("REC"), movie("A Quiet Place"), movie("Us"), movie("Nope"),
                movie("Barbarian"), movie("Talk to Me"), movie("The Lighthouse"), movie("Carrie"), movie("Misery"),
                show("The Haunting of Hill House"), show("Midnight Mass"), show("Hannibal"), show("American Horror Story"), show("Penny Dreadful"),
                show("The Terror"), show("Bates Motel"), show("Castle Rock"), show("From"), show("Marianne")
            ],
            16: [
                movie("Spirited Away"), movie("Spider-Man: Into the Spider-Verse"), movie("Spider-Man: Across the Spider-Verse"), movie("Toy Story"), movie("Toy Story 2"),
                movie("Toy Story 3"), movie("Finding Nemo"), movie("The Incredibles"), movie("WALL·E"), movie("Up"),
                movie("Inside Out"), movie("Coco"), movie("Ratatouille"), movie("Monsters, Inc."), movie("Shrek"),
                movie("How to Train Your Dragon"), movie("The Iron Giant"), movie("The Lion King"), movie("Beauty and the Beast"), movie("Aladdin"),
                movie("The Nightmare Before Christmas"), movie("Coraline"), movie("Kubo and the Two Strings"), movie("Fantastic Mr. Fox"), movie("The Lego Movie"),
                movie("Akira"), movie("Ghost in the Shell"), movie("Princess Mononoke"), movie("Howl's Moving Castle"), movie("My Neighbor Totoro"),
                movie("Grave of the Fireflies"), movie("The Tale of The Princess Kaguya"), movie("Your Name."), movie("A Silent Voice"), movie("Wolf Children"),
                movie("The Secret of Kells"), movie("Song of the Sea"), movie("Persepolis"), movie("Waltz with Bashir"), movie("The Red Turtle"),
                show("Avatar: The Last Airbender"), show("Arcane"), show("BoJack Horseman"), show("Gravity Falls"), show("Samurai Jack"),
                show("Batman: The Animated Series"), show("Star Wars: The Clone Wars"), show("Adventure Time"), show("Over the Garden Wall"), show("Invincible")
            ],
            80: [
                movie("The Godfather"), movie("The Godfather Part II"), movie("Goodfellas"), movie("Pulp Fiction"), movie("The Departed"),
                movie("Se7en"), movie("The Silence of the Lambs"), movie("Heat"), movie("Scarface"), movie("Casino"),
                movie("Reservoir Dogs"), movie("L.A. Confidential"), movie("Fargo"), movie("No Country for Old Men"), movie("Zodiac"),
                movie("Prisoners"), movie("Memories of Murder"), movie("Oldboy"), movie("City of God"), movie("The Usual Suspects"),
                movie("M"), movie("Double Indemnity"), movie("Chinatown"), movie("The French Connection"), movie("Dog Day Afternoon"),
                movie("Serpico"), movie("The Untouchables"), movie("A Bronx Tale"), movie("Carlito's Way"), movie("Road to Perdition"),
                movie("Mystic River"), movie("Gone Girl"), movie("Nightcrawler"), movie("Sicario"), movie("Training Day"),
                movie("Collateral"), movie("Inside Man"), movie("The Girl with the Dragon Tattoo"), movie("Eastern Promises"), movie("A History of Violence"),
                show("The Wire"), show("The Sopranos"), show("Breaking Bad"), show("Better Call Saul"), show("True Detective"),
                show("Fargo"), show("Mindhunter"), show("Narcos"), show("Ozark"), show("Peaky Blinders")
            ],
            35: [
                movie("Some Like It Hot"), movie("Dr. Strangelove or: How I Learned to Stop Worrying and Love the Bomb"), movie("Monty Python and the Holy Grail"), movie("Life of Brian"), movie("Airplane!"),
                movie("The Big Lebowski"), movie("Groundhog Day"), movie("Ghostbusters"), movie("Back to the Future"), movie("The Princess Bride"),
                movie("Ferris Bueller's Day Off"), movie("Planes, Trains and Automobiles"), movie("When Harry Met Sally..."), movie("Annie Hall"), movie("The Apartment"),
                movie("City Lights"), movie("Modern Times"), movie("The General"), movie("Duck Soup"), movie("Young Frankenstein"),
                movie("Blazing Saddles"), movie("This Is Spinal Tap"), movie("Office Space"), movie("Shaun of the Dead"), movie("Hot Fuzz"),
                movie("Superbad"), movie("Bridesmaids"), movie("Mean Girls"), movie("Clueless"), movie("School of Rock"),
                movie("Tropic Thunder"), movie("Borat"), movie("The Grand Budapest Hotel"), movie("Fantastic Mr. Fox"), movie("Hunt for the Wilderpeople"),
                movie("Jojo Rabbit"), movie("Knives Out"), movie("Palm Springs"), movie("Game Night"), movie("The Nice Guys"),
                show("Seinfeld"), show("The Office"), show("Parks and Recreation"), show("Community"), show("Arrested Development"),
                show("30 Rock"), show("Brooklyn Nine-Nine"), show("It's Always Sunny in Philadelphia"), show("Curb Your Enthusiasm"), show("What We Do in the Shadows")
            ]
        ]
        
        private static func isEraID(_ id: Int) -> Bool {
            id == 1980 || id == 1990 || id == 2000 || id == 2010
        }
        
        private func discoverEra(eraID: Int, filter: MediaFilter, sort: GenreSort) async throws -> [MediaItem] {
            let years: (start: String, end: String)
            
            switch eraID {
            case 1980:
                years = ("1980-01-01", "1989-12-31")
            case 1990:
                years = ("1990-01-01", "1999-12-31")
            case 2000:
                years = ("2000-01-01", "2009-12-31")
            case 2010:
                years = ("2010-01-01", "2019-12-31")
            default:
                years = ("1980-01-01", "2019-12-31")
            }
            
            if filter == .both {
                async let movies = discoverEraSingleMedia(years: years, media: "movie", sort: sort)
                async let shows = discoverEraSingleMedia(years: years, media: "tv", sort: sort)
                
                return try await (movies + shows)
                    .uniqued()
                    .sorted(using: .tmdbRating, ratings: [:])
            }
            
            let media = filter == .tv ? "tv" : "movie"
            return try await discoverEraSingleMedia(years: years, media: media, sort: sort)
        }
        
        private func discoverEraSingleMedia(years: (start: String, end: String), media: String, sort: GenreSort) async throws -> [MediaItem] {
            let datePrefix = media == "tv" ? "first_air_date" : "primary_release_date"
            let minVoteCount = media == "tv" ? "350" : "1200"
            let minVoteAverage = media == "tv" ? "7.0" : "6.8"
            
            return try await fetchList(path: "/discover/\(media)", query: [
                URLQueryItem(name: "sort_by", value: sort.tmdbSort),
                URLQueryItem(name: "with_original_language", value: "en"),
                URLQueryItem(name: "vote_count.gte", value: minVoteCount),
                URLQueryItem(name: "vote_average.gte", value: minVoteAverage),
                URLQueryItem(name: "include_adult", value: "false"),
                URLQueryItem(name: "include_video", value: "false"),
                URLQueryItem(name: "region", value: "US"),
                URLQueryItem(name: "watch_region", value: "US"),
                URLQueryItem(name: "with_watch_monetization_types", value: "flatrate|free|rent|buy"),
                URLQueryItem(name: "\(datePrefix).gte", value: years.start),
                URLQueryItem(name: "\(datePrefix).lte", value: years.end)
            ])
        }
        
        func discoverFilteredSearch(filter: SearchFilter, runtimeFilter: RuntimeSearchFilter, minimumRating: Double, includeAdult: Bool) async throws -> [MediaItem] {
            if filter == .people { return [] }
            
            if filter == .movie {
                return try await discoverFilteredSearchSingleMedia(
                    media: "movie",
                    runtimeFilter: runtimeFilter,
                    minimumRating: minimumRating,
                    includeAdult: includeAdult
                )
            }
            
            if filter == .tv {
                return try await discoverFilteredSearchSingleMedia(
                    media: "tv",
                    runtimeFilter: runtimeFilter,
                    minimumRating: minimumRating,
                    includeAdult: includeAdult
                )
            }
            
            return []
        }
        
        private func discoverFilteredSearchSingleMedia(media: String, runtimeFilter: RuntimeSearchFilter, minimumRating: Double, includeAdult: Bool) async throws -> [MediaItem] {
            var query: [URLQueryItem] = [
                URLQueryItem(name: "sort_by", value: "popularity.desc"),
                URLQueryItem(name: "with_original_language", value: "en"),
                URLQueryItem(name: "include_adult", value: includeAdult ? "true" : "false"),
                URLQueryItem(name: "include_video", value: "false"),
                URLQueryItem(name: "region", value: "US"),
                URLQueryItem(name: "watch_region", value: "US")
            ]
            
            if minimumRating > 0 {
                query.append(URLQueryItem(name: "vote_average.gte", value: String(format: "%.1f", minimumRating)))
            }
            
            if let minimumMinutes = runtimeFilter.minimumMinutes {
                query.append(URLQueryItem(name: "with_runtime.gte", value: String(minimumMinutes)))
            }
            
            if let maximumMinutes = runtimeFilter.maximumMinutes {
                query.append(URLQueryItem(name: "with_runtime.lte", value: String(maximumMinutes)))
            }
            
            return try await fetchListPages(path: "/discover/\(media)", query: query, pages: 5)
        }
        
        private func discoverCategorySingleMedia(genreID: Int, media: String) async throws -> [MediaItem] {
            let tmdbGenreIDs = tmdbGenreIDsToQuery(for: genreID, media: media)
            guard !tmdbGenreIDs.isEmpty else { return [] }
            
            let minVoteCount = minimumVoteCount(for: genreID, media: media)
            let minVoteAverage = minimumVoteAverage(for: genreID, media: media)
            let queryGenreString = tmdbGenreIDs.map(String.init).joined(separator: ",")
            
            let query: [URLQueryItem] = [
                URLQueryItem(name: "with_genres", value: queryGenreString),
                URLQueryItem(name: "sort_by", value: "popularity.desc"),
                URLQueryItem(name: "with_original_language", value: "en"),
                URLQueryItem(name: "vote_count.gte", value: minVoteCount),
                URLQueryItem(name: "vote_average.gte", value: minVoteAverage),
                URLQueryItem(name: "include_adult", value: "false"),
                URLQueryItem(name: "include_video", value: "false"),
                URLQueryItem(name: "region", value: "US"),
                URLQueryItem(name: "watch_region", value: "US")
            ]
            
            return try await fetchListPages(path: "/discover/\(media)", query: query, pages: 5)
                .filter { item in
                    guard item.kind == .movie || item.kind == .tv else { return false }
                    return item.primaryCategoryGenreID == genreID
                }
        }
        
        private func tmdbGenreIDsToQuery(for genreID: Int, media: String) -> [Int] {
            guard media == "tv" else { return [genreID] }
            
            switch genreID {
            case 28:
                return [10759]
            case 878:
                return [10765]
            case 14:
                return [10765]
            case 18:
                return [18]
            case 16:
                return [16]
            case 80:
                return [80]
            case 35:
                return [35]
            case 27:
                return []
            default:
                return [genreID]
            }
        }
        
        private func minimumVoteCount(for genreID: Int, media: String) -> String {
            if media == "tv" {
                switch genreID {
                case 16:
                    return "120"
                case 35:
                    return "180"
                case 878, 14:
                    return "220"
                default:
                    return "250"
                }
            }
            
            switch genreID {
            case 16:
                return "350"
            case 27, 35:
                return "450"
            default:
                return "650"
            }
        }
        
        private func minimumVoteAverage(for genreID: Int, media: String) -> String {
            if media == "tv" {
                switch genreID {
                case 27:
                    return "6.2"
                case 35:
                    return "6.4"
                default:
                    return "6.6"
                }
            }
            
            switch genreID {
            case 27:
                return "6.0"
            case 35:
                return "6.2"
            default:
                return "6.4"
            }
        }
        
        func recommendations(for key: MediaKey) async throws -> [MediaItem] {
            try await fetchList(path: "/\(key.kind.tmdbPath)/\(key.id)/recommendations", query: [])
                .filter { !$0.isUpcoming }
        }
        
        func sameSeriesOrSimilar(for key: MediaKey) async throws -> [MediaItem] {
            try await fetchList(path: "/\(key.kind.tmdbPath)/\(key.id)/similar", query: [])
                .filter { !$0.isUpcoming }
        }
        
        func detail(for item: MediaItem) async throws -> MediaDetail {
            let response: TMDbDetailResponse = try await fetch(path: "/\(item.kind.tmdbPath)/\(item.id)", query: [URLQueryItem(
                name: "append_to_response",
                value: item.kind == .movie
                ? "credits,similar,watch/providers,release_dates"
                : "credits,similar,watch/providers,content_ratings"
            )])
            
            guard item.kind == .tv else {
                return MediaDetail(response: response, fallback: item)
            }
            
            let seasonsWithEpisodes = try await hydratedSeasons(for: item, baseSeasons: response.seasons ?? [])
            let hydratedResponse = response.replacingSeasons(seasonsWithEpisodes)
            return MediaDetail(response: hydratedResponse, fallback: item)
        }
        
        private func hydratedSeasons(for item: MediaItem, baseSeasons: [SeasonDTO]) async throws -> [SeasonDTO] {
            var hydratedSeasons: [SeasonDTO] = []
            
            for season in baseSeasons {
                guard let seasonNumber = season.seasonNumber, seasonNumber > 0 else {
                    hydratedSeasons.append(season)
                    continue
                }
                
                do {
                    let hydratedSeason: SeasonDTO = try await fetch(path: "/tv/\(item.id)/season/\(seasonNumber)", query: [])
                    hydratedSeasons.append(season.mergingEpisodes(from: hydratedSeason))
                } catch {
                    hydratedSeasons.append(season)
                }
            }
            
            return hydratedSeasons
        }
        
        func personCredits(personID: Int) async throws -> [MediaItem] {
            let response: TMDbPersonCreditsResponse = try await fetch(path: "/person/\(personID)/combined_credits", query: [])
            let combinedCredits: [TMDbMediaDTO] = response.cast + response.crew
            let mappedItems: [MediaItem] = combinedCredits.map { dto in
                MediaItem(dto)
            }
            let filteredItems: [MediaItem] = mappedItems.filter { item in
                item.shouldShowInPersonCredits
            }
            let uniqueItems: [MediaItem] = filteredItems.uniqued()
            let sortedItems: [MediaItem] = uniqueItems.sorted { lhs, rhs in
                if lhs.voteAverage != rhs.voteAverage {
                    return lhs.voteAverage > rhs.voteAverage
                }
                let lhsDate = lhs.releaseDateValue ?? .distantPast
                let rhsDate = rhs.releaseDateValue ?? .distantPast
                return lhsDate > rhsDate
            }
            return sortedItems
        }
        
        func personDetail(personID: Int) async throws -> PersonDetail {
            let response: TMDbPersonDetailResponse = try await fetch(path: "/person/\(personID)", query: [])
            return PersonDetail(response: response)
        }
        
        
        private func fetchList(path: String, query: [URLQueryItem]) async throws -> [MediaItem] {
            let response: TMDbListResponse = try await fetch(path: path, query: query)
            return response.results.map(MediaItem.init).filter { !$0.title.isEmpty }
        }
        
        private func fetchListPages(path: String, query: [URLQueryItem], pages: Int) async throws -> [MediaItem] {
            var collected: [MediaItem] = []
            for page in 1...max(pages, 1) {
                let pageItems: [MediaItem] = try await fetchList(path: path, query: query, page: page)
                collected += pageItems
                if pageItems.isEmpty { break }
            }
            return collected.uniqued()
        }
        
        private func fetchList(path: String, query: [URLQueryItem], page: Int) async throws -> [MediaItem] {
            let response: TMDbListResponse = try await fetch(path: path, query: query, page: page)
            return response.results.map(MediaItem.init).filter { !$0.title.isEmpty }
        }
        
        private func fetch<T: Decodable>(path: String, query: [URLQueryItem]) async throws -> T {
            try await fetch(path: path, query: query, page: 1)
        }
        
        private func fetch<T: Decodable>(path: String, query: [URLQueryItem], page: Int) async throws -> T {
            var comps = URLComponents(string: base + path)!
            comps.queryItems = [
                URLQueryItem(name: "api_key", value: apiKey),
                URLQueryItem(name: "language", value: "en-US"),
                URLQueryItem(name: "page", value: String(page))
            ] + query
            guard let url = comps.url else { throw URLError(.badURL) }
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) { throw URLError(.badServerResponse) }
            return try JSONDecoder().decode(T.self, from: data)
        }
    }

    private struct StreamingAvailabilityService {
        private let base = "https://mtttuyvpjyugudkevchj.supabase.co/functions/v1/vestigo-api"
        
        func providers(for item: MediaItem) async throws -> [StreamingOption] {
            var comps = URLComponents(string: base + "/watchmode-sources")!
            comps.queryItems = [
                URLQueryItem(name: "tmdbID", value: String(item.id)),
                URLQueryItem(name: "kind", value: item.kind == .tv ? "tv" : "movie"),
                URLQueryItem(name: "country", value: "US")
            ]
            
            guard let url = comps.url else { throw URLError(.badURL) }
            let response: WatchmodeSourcesResponse = try await fetch(url: url)
            return response.sources
        }
        
        private func fetch<T: Decodable>(url: URL) async throws -> T {
            let request = URLRequest(url: url)
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            return try JSONDecoder().decode(T.self, from: data)
        }
    }

    private struct WatchmodeSourcesResponse: Decodable {
        let ok: Bool
        let source: String?
        let tmdbID: Int?
        let kind: String?
        let country: String?
        let count: Int?
        let sources: [StreamingOption]
    }
    
        
    // MARK: - DTOs
    
    
    private struct TMDbListResponse: Decodable { let results: [TMDbMediaDTO] }
    
    private struct TMDbPersonSearchResponse: Decodable {
        let results: [TMDbPersonSearchDTO]
    }
    
    private struct TMDbPersonSearchDTO: Decodable {
        let id: Int
        let name: String
        let knownForDepartment: String?
        let profilePath: String?
        
        enum CodingKeys: String, CodingKey {
            case id, name
            case knownForDepartment = "known_for_department"
            case profilePath = "profile_path"
        }
    }
    
    
    private struct TMDbPersonCreditsResponse: Decodable {
        let cast: [TMDbMediaDTO]
        let crew: [TMDbMediaDTO]
    }
    
    private struct TMDbPersonDetailResponse: Decodable {
        let id: Int
        let biography: String?
    }
    
    private struct TMDbMediaDTO: Decodable {
        let id: Int
        let title: String?
        let name: String?
        let overview: String?
        let character: String?
        let job: String?
        let mediaType: String?
        let posterPath: String?
        let backdropPath: String?
        let releaseDate: String?
        let firstAirDate: String?
        let voteAverage: Double?
        let genreIDs: [Int]?
        let originalLanguage: String?
        
        enum CodingKeys: String, CodingKey {
            case id, title, name, overview, character, job
            case mediaType = "media_type"
            case posterPath = "poster_path"
            case backdropPath = "backdrop_path"
            case releaseDate = "release_date"
            case firstAirDate = "first_air_date"
            case voteAverage = "vote_average"
            case genreIDs = "genre_ids"
            case originalLanguage = "original_language"
        }
    }
    
    private struct TMDbCollectionReference: Codable, Hashable {
        let id: Int?
        let name: String?
    }
    
    private struct TMDbDetailResponse: Decodable {
        let runtime: Int?
        let numberOfSeasons: Int?
        let numberOfEpisodes: Int?
        let seasons: [SeasonDTO]?
        let firstAirDate: String?
        let lastAirDate: String?
        let status: String?
        let createdBy: [PersonDTO]?
        let credits: CreditsDTO?
        let similar: TMDbListResponse?
        let recommendations: TMDbListResponse?
        let releaseDates: TMDbReleaseDatesResponse?
        let contentRatings: TMDbContentRatingsResponse?
        let belongsToCollection: TMDbCollectionReference?
        
        enum CodingKeys: String, CodingKey {
            case runtime
            case numberOfSeasons = "number_of_seasons"
            case numberOfEpisodes = "number_of_episodes"
            case seasons
            case firstAirDate = "first_air_date"
            case lastAirDate = "last_air_date"
            case status
            case createdBy = "created_by"
            case credits
            case similar
            case recommendations
            case releaseDates = "release_dates"
            case contentRatings = "content_ratings"
            case belongsToCollection = "belongs_to_collection"
        }
        
        init(
            runtime: Int?,
            numberOfSeasons: Int?,
            numberOfEpisodes: Int?,
            seasons: [SeasonDTO]?,
            firstAirDate: String?,
            lastAirDate: String?,
            status: String?,
            createdBy: [PersonDTO]?,
            credits: CreditsDTO?,
            similar: TMDbListResponse?,
            recommendations: TMDbListResponse?,
            releaseDates: TMDbReleaseDatesResponse?,
            contentRatings: TMDbContentRatingsResponse?,
            belongsToCollection: TMDbCollectionReference?
        ) {
            self.runtime = runtime
            self.numberOfSeasons = numberOfSeasons
            self.numberOfEpisodes = numberOfEpisodes
            self.seasons = seasons
            self.firstAirDate = firstAirDate
            self.lastAirDate = lastAirDate
            self.status = status
            self.createdBy = createdBy
            self.credits = credits
            self.similar = similar
            self.recommendations = recommendations
            self.releaseDates = releaseDates
            self.contentRatings = contentRatings
            self.belongsToCollection = belongsToCollection
        }
        
        func replacingSeasons(_ hydratedSeasons: [SeasonDTO]) -> TMDbDetailResponse {
            TMDbDetailResponse(
                runtime: runtime,
                numberOfSeasons: numberOfSeasons,
                numberOfEpisodes: numberOfEpisodes,
                seasons: hydratedSeasons,
                firstAirDate: firstAirDate,
                lastAirDate: lastAirDate,
                status: status,
                createdBy: createdBy,
                credits: credits,
                similar: similar,
                recommendations: recommendations,
                releaseDates: releaseDates,
                contentRatings: contentRatings,
                belongsToCollection: belongsToCollection
            )
        }
        
        var usAgeRating: String? {
            if let movieRating = releaseDates?.results
                .first(where: { $0.iso31661 == "US" })?
                .releaseDates
                .compactMap({ $0.certification?.trimmingCharacters(in: .whitespacesAndNewlines) })
                .first(where: { !$0.isEmpty }) {
                return movieRating
            }
            
            if let tvRating = contentRatings?.results
                .first(where: { $0.iso31661 == "US" })?
                .rating?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !tvRating.isEmpty {
                return tvRating
            }
            
            return nil
        }
    }
    
    private struct TMDbReleaseDatesResponse: Decodable {
        let results: [TMDbReleaseDatesCountry]
    }
    
    private struct TMDbReleaseDatesCountry: Decodable {
        let iso31661: String
        let releaseDates: [TMDbReleaseDate]
        
        enum CodingKeys: String, CodingKey {
            case iso31661 = "iso_3166_1"
            case releaseDates = "release_dates"
        }
    }
    
    private struct TMDbReleaseDate: Decodable {
        let certification: String?
    }
    
    private struct TMDbContentRatingsResponse: Decodable {
        let results: [TMDbContentRating]
    }
    
    private struct TMDbContentRating: Decodable {
        let iso31661: String
        let rating: String?
        
        enum CodingKeys: String, CodingKey {
            case iso31661 = "iso_3166_1"
            case rating
        }
    }
    
    private struct SeasonDTO: Decodable {
        let seasonNumber: Int?
        let name: String?
        let airDate: String?
        let episodeCount: Int?
        let episodes: [EpisodeDTO]?
        
        enum CodingKeys: String, CodingKey {
            case seasonNumber = "season_number"
            case name
            case airDate = "air_date"
            case episodeCount = "episode_count"
            case episodes
        }
        
        init(seasonNumber: Int?, name: String?, airDate: String?, episodeCount: Int?, episodes: [EpisodeDTO]?) {
            self.seasonNumber = seasonNumber
            self.name = name
            self.airDate = airDate
            self.episodeCount = episodeCount
            self.episodes = episodes
        }
        
        func mergingEpisodes(from hydratedSeason: SeasonDTO) -> SeasonDTO {
            SeasonDTO(
                seasonNumber: seasonNumber ?? hydratedSeason.seasonNumber,
                name: name ?? hydratedSeason.name,
                airDate: airDate ?? hydratedSeason.airDate,
                episodeCount: episodeCount ?? hydratedSeason.episodeCount ?? hydratedSeason.episodes?.count,
                episodes: hydratedSeason.episodes ?? episodes
            )
        }
    }
    
    private struct EpisodeDTO: Decodable {
        let episodeNumber: Int?
        let name: String?
        let airDate: String?
        let runtime: Int?
        let stillPath: String?
        
        enum CodingKeys: String, CodingKey {
            case episodeNumber = "episode_number"
            case name
            case airDate = "air_date"
            case runtime
            case stillPath = "still_path"
        }
    }
    private struct CreditsDTO: Decodable { let cast: [PersonDTO]?; let crew: [PersonDTO]? }
    private struct PersonDTO: Decodable {
        let id: Int
        let name: String
        let job: String?
        let character: String?
        let profilePath: String?
        
        enum CodingKeys: String, CodingKey {
            case id, name, job, character
            case profilePath = "profile_path"
        }
    }
    private struct PersonSummary: Identifiable, Codable, Hashable {
        let id: Int
        let name: String
        let role: String
        let profilePath: String?
        
        var profileURL: URL? {
            profilePath.flatMap { URL(string: "https://image.tmdb.org/t/p/w342\($0)") }
        }
        
        init(_ dto: PersonDTO, fallbackRole: String = "") {
            id = dto.id
            name = dto.name
            role = dto.character ?? dto.job ?? fallbackRole
            profilePath = dto.profilePath
        }
        
        init(_ dto: TMDbPersonSearchDTO, fallbackRole: String = "Person") {
            id = dto.id
            name = dto.name
            role = fallbackRole
            profilePath = dto.profilePath
        }
    }
    
    private struct PersonDetail: Codable, Hashable {
        let id: Int
        let biography: String
        
        init(id: Int, biography: String) {
            self.id = id
            self.biography = biography
        }
        
        init(response: TMDbPersonDetailResponse) {
            id = response.id
            biography = response.biography ?? ""
        }
    }
    
    private struct TMDbProviderResponse: Decodable { let results: [String: TMDbProviderRegion] }
    private struct TMDbProviderRegion: Decodable { let flatrate: [TMDbProvider]?; let free: [TMDbProvider]?; let rent: [TMDbProvider]?; let buy: [TMDbProvider]? }
    private struct TMDbProvider: Decodable { let providerName: String; enum CodingKeys: String, CodingKey { case providerName = "provider_name" } }
    
    private struct WatchmodeShowResponse: Decodable {
        let title: String?
        let tmdbId: String?
        let releaseYear: Int?
        let firstAirYear: Int?
        let streamingOptions: [String: [WatchmodeOption]]?
        
        enum CodingKeys: String, CodingKey {
            case title
            case tmdbId
            case releaseYear
            case firstAirYear
            case streamingOptions
        }
        
        var matchYear: Int? {
            releaseYear ?? firstAirYear
        }
        
        var normalizedTitle: String {
            (title ?? "").normalizedForMatching
        }
        
        var usOptions: [StreamingOption] {
            let options = streamingOptions?["us"] ?? streamingOptions?["US"] ?? []
            return options.map { option in
                StreamingOption(
                    serviceName: option.displayServiceName,
                    type: option.displayTypeText,
                    priceText: option.displayPriceText,
                    qualityText: option.displayQualityText,
                    openURL: option.displayOpenURL
                )
            }
        }
    }
    
    private struct WatchmodeOption: Decodable {
        let service: WatchmodeService?
        let addon: WatchmodeService?
        let type: String?
        let quality: String?
        let price: WatchmodePrice?
        let raw: WatchmodeJSONValue?
        let link: String?
        let openURL: String?
        let webURL: String?
        let iosURL: String?
        let androidURL: String?
        let appURL: String?

        enum CodingKeys: String, CodingKey {
            case service
            case addon
            case addOn
            case type
            case quality
            case price
            case amount
            case value
            case cost
            case retailPrice
            case rentalPrice
            case purchasePrice
            case rentPrice
            case buyPrice
            case currency
            case currencyCode
            case formattedPrice
            case priceFormatted
            case displayPrice
            case priceText
            case prices
            case pricing
            case offers
            case offer
            case links
            case link
            // openURL fields for openURL selection
            case openURL
            case openUrl
            case open_url
            // URL fields for openURL selection
            case url
            case webURL
            case webUrl
            case web_url
            case iosURL
            case iosUrl
            case ios_url
            case androidURL
            case androidUrl
            case android_url
            case appURL
            case appUrl
            case app_url
            case deepLink
            case deeplink
            case deep_link
        }

        init(from decoder: Decoder) throws {
            let keyed = try decoder.container(keyedBy: CodingKeys.self)
            service = try keyed.decodeIfPresent(WatchmodeService.self, forKey: .service)
            addon = try keyed.decodeIfPresent(WatchmodeService.self, forKey: .addon) ?? keyed.decodeIfPresent(WatchmodeService.self, forKey: .addOn)
            type = try keyed.decodeIfPresent(String.self, forKey: .type)
            quality = try keyed.decodeIfPresent(String.self, forKey: .quality)
            raw = try? WatchmodeJSONValue(from: decoder)
            let decodedLink = try keyed.decodeIfPresent(String.self, forKey: .link)
            let decodedLinks = try keyed.decodeIfPresent(String.self, forKey: .links)
            let decodedURL = try keyed.decodeIfPresent(String.self, forKey: .url)
            let decodedDeepLink = try keyed.decodeIfPresent(String.self, forKey: .deepLink)
            let decodedDeeplink = try keyed.decodeIfPresent(String.self, forKey: .deeplink)
            let decodedDeepLinkSnake = try keyed.decodeIfPresent(String.self, forKey: .deep_link)
            link = decodedLink ?? decodedLinks ?? decodedURL ?? decodedDeepLink ?? decodedDeeplink ?? decodedDeepLinkSnake

            // openURL decoding (normalized field from backend)
            let decodedOpenURL = try keyed.decodeIfPresent(String.self, forKey: .openURL)
            let decodedOpenUrl = try keyed.decodeIfPresent(String.self, forKey: .openUrl)
            let decodedOpenURLSnake = try keyed.decodeIfPresent(String.self, forKey: .open_url)
            openURL = decodedOpenURL ?? decodedOpenUrl ?? decodedOpenURLSnake

            let decodedWebURL = try keyed.decodeIfPresent(String.self, forKey: .webURL)
            let decodedWebUrl = try keyed.decodeIfPresent(String.self, forKey: .webUrl)
            let decodedWebURLSnake = try keyed.decodeIfPresent(String.self, forKey: .web_url)
            webURL = decodedWebURL ?? decodedWebUrl ?? decodedWebURLSnake

            let decodedIOSURL = try keyed.decodeIfPresent(String.self, forKey: .iosURL)
            let decodedIOSUrl = try keyed.decodeIfPresent(String.self, forKey: .iosUrl)
            let decodedIOSURLSnake = try keyed.decodeIfPresent(String.self, forKey: .ios_url)
            iosURL = decodedIOSURL ?? decodedIOSUrl ?? decodedIOSURLSnake

            let decodedAndroidURL = try keyed.decodeIfPresent(String.self, forKey: .androidURL)
            let decodedAndroidUrl = try keyed.decodeIfPresent(String.self, forKey: .androidUrl)
            let decodedAndroidURLSnake = try keyed.decodeIfPresent(String.self, forKey: .android_url)
            androidURL = decodedAndroidURL ?? decodedAndroidUrl ?? decodedAndroidURLSnake

            let decodedAppURL = try keyed.decodeIfPresent(String.self, forKey: .appURL)
            let decodedAppUrl = try keyed.decodeIfPresent(String.self, forKey: .appUrl)
            let decodedAppURLSnake = try keyed.decodeIfPresent(String.self, forKey: .app_url)
            appURL = decodedAppURL ?? decodedAppUrl ?? decodedAppURLSnake

            var resolvedPrice: WatchmodePrice?

            if resolvedPrice == nil { resolvedPrice = try keyed.decodeIfPresent(WatchmodePrice.self, forKey: .price) }
            if resolvedPrice == nil { resolvedPrice = try keyed.decodeIfPresent(WatchmodePrice.self, forKey: .amount) }
            if resolvedPrice == nil { resolvedPrice = try keyed.decodeIfPresent(WatchmodePrice.self, forKey: .value) }
            if resolvedPrice == nil { resolvedPrice = try keyed.decodeIfPresent(WatchmodePrice.self, forKey: .cost) }
            if resolvedPrice == nil { resolvedPrice = try keyed.decodeIfPresent(WatchmodePrice.self, forKey: .retailPrice) }
            if resolvedPrice == nil { resolvedPrice = try keyed.decodeIfPresent(WatchmodePrice.self, forKey: .rentalPrice) }
            if resolvedPrice == nil { resolvedPrice = try keyed.decodeIfPresent(WatchmodePrice.self, forKey: .purchasePrice) }
            if resolvedPrice == nil { resolvedPrice = try keyed.decodeIfPresent(WatchmodePrice.self, forKey: .rentPrice) }
            if resolvedPrice == nil { resolvedPrice = try keyed.decodeIfPresent(WatchmodePrice.self, forKey: .buyPrice) }
            if resolvedPrice == nil { resolvedPrice = try keyed.decodeIfPresent(WatchmodePrice.self, forKey: .formattedPrice) }
            if resolvedPrice == nil { resolvedPrice = try keyed.decodeIfPresent(WatchmodePrice.self, forKey: .priceFormatted) }
            if resolvedPrice == nil { resolvedPrice = try keyed.decodeIfPresent(WatchmodePrice.self, forKey: .displayPrice) }
            if resolvedPrice == nil { resolvedPrice = try keyed.decodeIfPresent(WatchmodePrice.self, forKey: .priceText) }
            if resolvedPrice == nil { resolvedPrice = try keyed.decodeIfPresent(WatchmodePrice.self, forKey: .prices) }
            if resolvedPrice == nil { resolvedPrice = try keyed.decodeIfPresent(WatchmodePrice.self, forKey: .pricing) }
            if resolvedPrice == nil { resolvedPrice = try keyed.decodeIfPresent(WatchmodePrice.self, forKey: .offer) }
            if resolvedPrice == nil { resolvedPrice = try keyed.decodeIfPresent(WatchmodePrice.self, forKey: .offers) }
            if resolvedPrice == nil { resolvedPrice = try keyed.decodeIfPresent(WatchmodePrice.self, forKey: .link) }
            if resolvedPrice == nil { resolvedPrice = try keyed.decodeIfPresent(WatchmodePrice.self, forKey: .links) }

            if resolvedPrice?.displayText == nil {
                if let scannedText = raw?.firstPriceText() {
                    resolvedPrice = WatchmodePrice(displayText: scannedText)
                }
            }

            price = resolvedPrice
        }

        var displayOpenURL: String? {
            let candidates = [openURL, iosURL, appURL, webURL, link, androidURL]
            return candidates
                .compactMap { value in
                    value?.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                .first { value in
                    guard !value.isEmpty else { return false }
                    let lower = value.lowercased()
                    guard lower != "ios:" else { return false }
                    guard lower != "ios://" else { return false }
                    guard !lower.contains("{ios") else { return false }
                    guard !lower.contains("placeholder") else { return false }
                    return URL(string: value) != nil
                }
        }

        var displayServiceName: String {
            addon?.name ?? service?.name ?? "Unknown"
        }

        var displayTypeText: String {
            let normalizedType = (type ?? "unknown").lowercased()
            switch normalizedType {
            case "rent", "rental":
                return "rent"
            case "buy", "purchase", "purchase4k", "buy4k":
                return "buy"
            case "free":
                return "free"
            case "subscription", "flatrate", "stream":
                return "subscription"
            case "addon", "add-on", "add_on":
                return "addon"
            default:
                return type ?? "unknown"
            }
        }

        var displayPriceText: String {
            if let displayText = price?.displayText, !displayText.isEmpty {
                return displayText
            }

            if let linkPrice = link?.priceTextFromURL(), !linkPrice.isEmpty {
                return linkPrice
            }

            let normalizedType = (type ?? "").lowercased()
            switch normalizedType {
            case "free":
                return "Free"
            case "subscription", "flatrate", "stream", "addon", "add-on", "add_on":
                return "Included"
            default:
                return ""
            }
        }

        var displayQualityText: String {
            guard let quality, !quality.isEmpty else { return "" }
            return quality.uppercased()
        }
    }
    
    private struct WatchmodeService: Decodable {
        let name: String?
    }
    
    private struct WatchmodePrice: Decodable {
        let displayText: String?
        
        init(displayText: String?) {
            self.displayText = displayText
        }
        
        init(from decoder: Decoder) throws {
            let raw = try? WatchmodeJSONValue(from: decoder)
            displayText = raw?.firstPriceText()
        }
    }
    
    private enum WatchmodeJSONValue: Decodable {
        case string(String)
        case number(Double)
        case object([String: WatchmodeJSONValue])
        case array([WatchmodeJSONValue])
        case bool(Bool)
        case null
        
        init(from decoder: Decoder) throws {
            if let single = try? decoder.singleValueContainer() {
                if single.decodeNil() {
                    self = .null
                    return
                }
                
                if let value = try? single.decode(String.self) {
                    self = .string(value)
                    return
                }
                
                if let value = try? single.decode(Double.self) {
                    self = .number(value)
                    return
                }
                
                if let value = try? single.decode(Bool.self) {
                    self = .bool(value)
                    return
                }
            }
            
            if let keyed = try? decoder.container(keyedBy: DynamicCodingKey.self) {
                var object: [String: WatchmodeJSONValue] = [:]
                for key in keyed.allKeys {
                    object[key.stringValue] = try keyed.decode(WatchmodeJSONValue.self, forKey: key)
                }
                self = .object(object)
                return
            }
            
            var unkeyed = try decoder.unkeyedContainer()
            var array: [WatchmodeJSONValue] = []
            while !unkeyed.isAtEnd {
                array.append(try unkeyed.decode(WatchmodeJSONValue.self))
            }
            self = .array(array)
        }
        
        func firstPriceText() -> String? {
            switch self {
            case .string(let value):
                return Self.cleanedPriceString(value, keyHint: nil)
            case .number:
                return nil
            case .bool, .null:
                return nil
            case .array(let values):
                return Self.firstPriceText(in: values)
            case .object(let object):
                return Self.firstPriceText(in: object)
            }
        }
        
        private static func firstPriceText(in values: [WatchmodeJSONValue]) -> String? {
            for value in values {
                if let found = value.firstPriceText() {
                    return found
                }
            }
            return nil
        }
        
        private static func firstPriceText(in object: [String: WatchmodeJSONValue]) -> String? {
            let preferredKeys: [String] = [
                "formattedPrice",
                "priceFormatted",
                "displayPrice",
                "priceText",
                "formatted",
                "amount",
                "value",
                "cost",
                "retailPrice",
                "rentalPrice",
                "purchasePrice",
                "rentPrice",
                "buyPrice",
                "price"
            ]
            
            for key in preferredKeys {
                if let value = object[key], let found = priceText(from: value, keyHint: key) {
                    return found
                }
            }
            
            let sortedPairs = object.sorted { lhs, rhs in
                lhs.key < rhs.key
            }
            
            for pair in sortedPairs {
                let lowerKey = pair.key.lowercased()
                let isPriceKey = lowerKey.contains("price") || lowerKey.contains("amount") || lowerKey.contains("cost") || lowerKey.contains("rental") || lowerKey.contains("purchase") || lowerKey.contains("rent") || lowerKey.contains("buy")
                if isPriceKey, let found = priceText(from: pair.value, keyHint: pair.key) {
                    return found
                }
            }
            
            for pair in sortedPairs {
                let lowerKey = pair.key.lowercased()
                if lowerKey == "type" || lowerKey == "quality" || lowerKey == "service" || lowerKey == "addon" || lowerKey == "link" || lowerKey == "links" {
                    continue
                }
                if let found = pair.value.firstPriceText() {
                    return found
                }
            }
            
            return nil
        }
        
        private static func priceText(from value: WatchmodeJSONValue, keyHint: String?) -> String? {
            switch value {
            case .string(let text):
                return cleanedPriceString(text, keyHint: keyHint)
            case .number(let number):
                guard let keyHint else { return nil }
                let lowerKey = keyHint.lowercased()
                let isPriceKey = lowerKey.contains("price") || lowerKey.contains("amount") || lowerKey.contains("cost")
                guard isPriceKey else { return nil }
                return formattedCurrency(number)
            case .array(let values):
                for nestedValue in values {
                    if let found = priceText(from: nestedValue, keyHint: keyHint) {
                        return found
                    }
                }
                return nil
            case .object(let object):
                return firstPriceText(in: object)
            case .bool, .null:
                return nil
            }
        }
        
        private static func cleanedPriceString(_ value: String, keyHint: String?) -> String? {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            
            if let dollarRange = trimmed.range(of: #"\$\s*\d+(?:\.\d{1,2})?"#, options: .regularExpression) {
                return String(trimmed[dollarRange]).replacingOccurrences(of: " ", with: "")
            }
            
            let lower = trimmed.lowercased()
            if lower == "free" { return "Free" }
            if lower == "included" { return "Included" }
            if lower == "subscription" { return nil }
            if lower == "flatrate" { return nil }
            if lower == "stream" { return nil }
            if lower == "rent" { return nil }
            if lower == "buy" { return nil }
            if lower == "purchase" { return nil }
            if lower == "addon" { return nil }
            if lower == "available" { return nil }
            if lower.hasPrefix("http://") || lower.hasPrefix("https://") { return trimmed.priceTextFromURL() }
            
            guard let keyHint else { return nil }
            let lowerKey = keyHint.lowercased()
            let isNumericPriceKey = lowerKey.contains("price") || lowerKey.contains("amount") || lowerKey.contains("cost")
            guard isNumericPriceKey else { return nil }
            
            let numericOnly = trimmed
                .replacingOccurrences(of: "$", with: "")
                .replacingOccurrences(of: ",", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            if let number = Double(numericOnly) {
                return formattedCurrency(number)
            }
            
            return nil
        }
        
        private static func formattedCurrency(_ value: Double) -> String? {
            guard value > 0 else { return nil }
            
            let amount: Double
            if value >= 100, value.rounded() == value {
                amount = value / 100.0
            } else {
                amount = value
            }
            
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.currencyCode = "USD"
            return formatter.string(from: NSNumber(value: amount))
        }
    }
    
    private struct DynamicCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int?
        
        init?(stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }
        
        init?(intValue: Int) {
            self.stringValue = String(intValue)
            self.intValue = intValue
        }
    }
    
    private extension String {
        func priceTextFromURL() -> String? {
            guard let comps = URLComponents(string: self) else { return nil }
            let possibleNames: [String] = [
                "price",
                "amount",
                "cost",
                "retailPrice",
                "rentalPrice",
                "purchasePrice",
                "rentPrice",
                "buyPrice"
            ]
            
            for name in possibleNames {
                guard let value = comps.queryItems?.first(where: { $0.name == name })?.value else {
                    continue
                }
                
                let cleaned = value
                    .replacingOccurrences(of: "$", with: "")
                    .replacingOccurrences(of: ",", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                guard let number = Double(cleaned), number > 0 else {
                    continue
                }
                
                let amount: Double
                if number >= 100, number.rounded() == number {
                    amount = number / 100.0
                } else {
                    amount = number
                }
                
                let formatter = NumberFormatter()
                formatter.numberStyle = .currency
                formatter.currencyCode = "USD"
                return formatter.string(from: NSNumber(value: amount))
            }
            
            return nil
        }
    }
    
    // MARK: - Data Models
    
    private struct MediaItem: Identifiable, Codable, Hashable {
        let id: Int
        let kind: MediaKind
        let title: String
        let overview: String
        let posterPath: String?
        let backdropPath: String?
        let releaseDate: String?
        let voteAverage: Double
        let genreIDs: [Int]
        let creditRole: String?
        let runtime: Int?
        let originalLanguage: String?
        
        init(
            id: Int,
            kind: MediaKind,
            title: String,
            overview: String,
            posterPath: String?,
            backdropPath: String?,
            releaseDate: String?,
            voteAverage: Double,
            genreIDs: [Int],
            creditRole: String?,
            runtime: Int?,
            originalLanguage: String?
        ) {
            self.id = id
            self.kind = kind
            self.title = title
            self.overview = overview
            self.posterPath = posterPath
            self.backdropPath = backdropPath
            self.releaseDate = releaseDate
            self.voteAverage = voteAverage
            self.genreIDs = genreIDs
            self.creditRole = creditRole
            self.runtime = runtime
            self.originalLanguage = originalLanguage
        }
        
        init(_ dto: TMDbMediaDTO) {
            id = dto.id
            if dto.mediaType == "tv" || (dto.name != nil && dto.title == nil) { kind = .tv }
            else if dto.mediaType == "person" { kind = .person }
            else { kind = .movie }
            title = dto.title ?? dto.name ?? ""
            overview = dto.overview ?? ""
            posterPath = dto.posterPath
            backdropPath = dto.backdropPath
            releaseDate = dto.releaseDate ?? dto.firstAirDate
            voteAverage = dto.voteAverage ?? 0
            genreIDs = dto.genreIDs ?? []
            creditRole = dto.character ?? dto.job
            runtime = nil
            originalLanguage = dto.originalLanguage
        }
        
        var key: MediaKey { MediaKey(id: id, kind: kind) }
        var posterURL: URL? { posterPath.flatMap { URL(string: "https://image.tmdb.org/t/p/w500\($0)") } }
        var releaseDateValue: Date? { DateParser.parse(releaseDate) }
        var releaseYearText: String { releaseDateValue.map { String(Calendar.current.component(.year, from: $0)) } ?? "TBA" }
        var releaseYearInt: Int? { Int(releaseYearText) }
        var releaseDateReadable: String { releaseDateValue?.formatted(.dateTime.month(.abbreviated).day().year()) ?? "TBA" }
        var isUpcoming: Bool { (releaseDateValue ?? .distantPast) > .now }
        var genreGradient: LinearGradient { GenreDefinition.gradient(for: genreIDs.first) }
        
        func withRuntime(_ runtime: Int?) -> MediaItem {
            MediaItem(
                id: id,
                kind: kind,
                title: title,
                overview: overview,
                posterPath: posterPath,
                backdropPath: backdropPath,
                releaseDate: releaseDate,
                voteAverage: voteAverage,
                genreIDs: genreIDs,
                creditRole: creditRole,
                runtime: runtime,
                originalLanguage: originalLanguage
            )
        }
    }
    
    private struct MediaKey: Codable, Hashable, Identifiable {
        let id: Int
        let kind: MediaKind
        var stableID: String { "\(kind.rawValue)-\(id)" }
    }
    
    private enum MediaKind: String, Codable, Hashable { case movie, tv, person }
    
    private extension MediaKind {
        var label: String { self == .movie ? "Movie" : (self == .tv ? "Series" : "Person") }
        var tmdbPath: String { self == .movie ? "movie" : (self == .tv ? "tv" : "person") }
        
        func displayLabel(runtime: Int?) -> String {
            if self == .movie, let runtime, runtime > 0, runtime <= 40 {
                return "Short film"
            }
            
            return label
        }
    }
    
    private struct MediaDetail: Hashable {
        let director: PersonSummary?
        let creator: PersonSummary?
        let cast: [PersonSummary]
        let castAndKeyCrew: [PersonSummary]
        let seasons: [SeasonInfo]
        let similar: [MediaItem]
        let firstAirDate: String?
        let lastAirDate: String?
        let status: String?
        let runtime: Int?
        let ageRating: String?
        let tmdbCollectionID: Int?
        
        init(response: TMDbDetailResponse, fallback: MediaItem) {
            let crewList: [PersonDTO] = response.credits?.crew ?? []
            let castList: [PersonDTO] = response.credits?.cast ?? []
            tmdbCollectionID = response.belongsToCollection?.id
            firstAirDate = response.firstAirDate
            lastAirDate = response.lastAirDate
            status = response.status
            runtime = response.runtime
            ageRating = response.usAgeRating
            
            let directorDTO = crewList.first { dto in
                dto.job == "Director"
            }
            director = directorDTO.map { dto in
                PersonSummary(dto, fallbackRole: "Director")
            }
            
            let creatorDTO = response.createdBy?.first
            creator = creatorDTO.map { dto in
                PersonSummary(dto, fallbackRole: "Creator")
            }
            
            let mappedCast: [PersonSummary] = castList.map { dto in
                PersonSummary(dto)
            }
            cast = mappedCast
            
            let keyCrewJobs: Set<String> = [
                "Director",
                "Creator",
                "Executive Producer",
                "Producer",
                "Writer",
                "Screenplay",
                "Story"
            ]
            
            let filteredCrewDTOs: [PersonDTO] = crewList.filter { dto in
                guard let job = dto.job else { return false }
                return keyCrewJobs.contains(job)
            }
            
            let mappedKeyCrew: [PersonSummary] = filteredCrewDTOs.map { dto in
                PersonSummary(dto)
            }
            
            let castIDs = Set(mappedCast.map { person in
                person.id
            })
            let uniqueKeyCrew = mappedKeyCrew.uniquedPeople(excluding: castIDs)
            castAndKeyCrew = mappedCast + uniqueKeyCrew
            
            let rawSeasons: [SeasonDTO] = response.seasons ?? []
            let normalSeasons = rawSeasons.filter { season in
                (season.seasonNumber ?? 0) > 0
            }
            seasons = normalSeasons.map { season in
                let number = season.seasonNumber ?? 1
                let name = season.name ?? "Season \(number)"
                let airDate = season.airDate
                let episodes: [EpisodeInfo] = (season.episodes ?? []).map { episode in
                    let episodeNumber = episode.episodeNumber ?? 1
                    return EpisodeInfo(
                        number: episodeNumber,
                        title: episode.name ?? "Episode \(episodeNumber)",
                        airDate: episode.airDate,
                        runtime: episode.runtime,
                        stillPath: episode.stillPath
                    )
                }
                let count = season.episodeCount ?? episodes.count
                return SeasonInfo(number: number, name: name, airDate: airDate, episodeCount: count, episodes: episodes)
            }
            
            let recommendationResults: [TMDbMediaDTO] = response.recommendations?.results ?? []
            let similarResults: [TMDbMediaDTO] = response.similar?.results ?? []
            let combinedResults: [TMDbMediaDTO] = similarResults + recommendationResults
            let mappedSimilar: [MediaItem] = combinedResults.map { dto in
                MediaItem(dto)
            }
            similar = mappedSimilar
                .uniqued()
                .filter { !$0.isUpcoming }
                .sortedBySimilarity(to: fallback)
        }
        
        var yearRangeText: String {
            guard let startYear = firstAirDate?.prefix(4), !startYear.isEmpty else {
                return "Unknown"
            }
            
            let normalizedStatus = status?.lowercased() ?? ""
            
            if normalizedStatus.contains("returning") ||
                normalizedStatus.contains("planned") ||
                normalizedStatus.contains("production") {
                return "\(startYear)–present"
            }
            
            if let endYear = lastAirDate?.prefix(4), !endYear.isEmpty, endYear != startYear {
                return "\(startYear)–\(endYear)"
            }
            
            return String(startYear)
        }
    }
    
    private struct SeasonInfo: Identifiable, Hashable {
        let number: Int
        let name: String
        let airDate: String?
        let episodeCount: Int
        let episodes: [EpisodeInfo]
        
        var id: Int { number }
        
        var releaseYearText: String? {
            guard let airDate,
                  let date = DateParser.parse(airDate) else {
                return nil
            }
            
            return String(Calendar.current.component(.year, from: date))
        }
        
        var totalRuntime: Int? {
            let runtimes = episodes.compactMap(\.runtime)
            guard !runtimes.isEmpty else { return nil }
            return runtimes.reduce(0, +)
        }
        
        var episodeCountAndRuntimeText: String {
            var parts: [String] = ["\(episodeCount) episode\(episodeCount == 1 ? "" : "s")"]
            
            if let releaseYearText {
                parts.append(releaseYearText)
            }
            
            if let totalRuntime, totalRuntime > 0 {
                parts.append(Self.formatRuntime(totalRuntime))
            }
            
            return parts.joined(separator: " • ")
        }
        
        private static func formatRuntime(_ minutes: Int) -> String {
            let hours = minutes / 60
            let mins = minutes % 60
            
            if hours > 0, mins > 0 {
                return "\(hours)h \(mins)m"
            } else if hours > 0 {
                return "\(hours)h"
            } else {
                return "\(mins)m"
            }
        }
        
        static let placeholder: [SeasonInfo] = []
    }
    
    private struct EpisodeInfo: Identifiable, Hashable {
        let number: Int
        let title: String
        let airDate: String?
        let runtime: Int?
        let stillPath: String?
        
        var id: Int { number }
        
        var releaseDateText: String? {
            DateParser.parse(airDate)?.formatted(.dateTime.month(.abbreviated).day().year())
        }
        
        var stillURL: URL? {
            guard let stillPath else { return nil }
            return URL(string: "https://image.tmdb.org/t/p/w300\(stillPath)")
        }
    }
    
    private struct StreamingOption: Codable, Hashable, Identifiable {
        var id: String {
            "\(serviceName)-\(type)-\(priceText)-\(qualityText)-\(openURL ?? "")"
        }

        var serviceShort: String {
            let cleaned = serviceName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return "?" }

            let initials = cleaned
                .split { !$0.isLetter && !$0.isNumber }
                .compactMap { $0.first }
                .prefix(2)
                .map { String($0).uppercased() }
                .joined()

            if !initials.isEmpty {
                return initials
            }

            return String(cleaned.prefix(2)).uppercased()
        }

        var availabilityText: String {
            switch type.lowercased() {
            case "subscription", "sub":
                return "Subscription"
            case "free":
                return "Free"
            case "rent", "rental":
                return "Rent"
            case "buy", "purchase":
                return "Buy"
            case "addon", "add-on", "add_on":
                return "Add-on"
            default:
                return type.isEmpty ? "Available" : type.capitalized
            }
        }

        let serviceName: String
        let type: String
        let priceText: String
        let qualityText: String
        let openURL: String?

        init(
            serviceName: String,
            type: String,
            priceText: String,
            qualityText: String,
            openURL: String? = nil
        ) {
            self.serviceName = serviceName
            self.type = type
            self.priceText = priceText
            self.qualityText = qualityText
            self.openURL = openURL
        }
    }
    
    private struct UserLibrary: Codable {
        var items: [MediaKey: MediaItem] = [:]
        var watchlist: Set<MediaKey> = []
        var watched: Set<MediaKey> = []
        var ratings: [MediaKey: Double] = [:]
        var favouriteMovieKey: MediaKey?
        var favouriteSeriesKey: MediaKey?
        var watchedOrder: [MediaKey] = []
        var collections: [MediaCollection] = []
        var watchedEpisodes: Set<EpisodeKey> = []
        
        var watchlistItems: [MediaItem] { watchlist.compactMap { items[$0] } }
        var watchedItems: [MediaItem] { watched.compactMap { items[$0] } }
        
        func isInWatchlist(_ key: MediaKey) -> Bool { watchlist.contains(key) }
        func isWatched(_ key: MediaKey) -> Bool { watched.contains(key) }
        
        mutating func toggleWatchlist(_ item: MediaItem) {
            items[item.key] = item
            if watchlist.contains(item.key) { watchlist.remove(item.key) } else { watchlist.insert(item.key) }
        }
        
        mutating func markWatched(_ item: MediaItem) {
            items[item.key] = item
            watched.insert(item.key)
        }
        
        mutating func toggleWatched(_ item: MediaItem) {
            items[item.key] = item
            if watched.contains(item.key) { watched.remove(item.key) } else { watched.insert(item.key) }
        }
        
        mutating func toggleEpisode(showKey: MediaKey, season: Int, episode: Int) {
            let key = EpisodeKey(show: showKey, season: season, episode: episode)
            if watchedEpisodes.contains(key) { watchedEpisodes.remove(key) } else { watchedEpisodes.insert(key) }
        }
        
        mutating func setEpisode(showKey: MediaKey, season: Int, episode: Int, watched: Bool) {
            let key = EpisodeKey(show: showKey, season: season, episode: episode)
            if watched { watchedEpisodes.insert(key) } else { watchedEpisodes.remove(key) }
        }
        
        func isEpisodeWatched(showKey: MediaKey, season: Int, episode: Int) -> Bool {
            watchedEpisodes.contains(EpisodeKey(show: showKey, season: season, episode: episode))
        }
        
        var favouriteMovie: MediaItem? {
            guard let favouriteMovieKey else { return nil }
            return items[favouriteMovieKey]
        }
        
        var favouriteSeries: MediaItem? {
            guard let favouriteSeriesKey else { return nil }
            return items[favouriteSeriesKey]
        }
        
        var lastWatchedItem: MediaItem? {
            for key in watchedOrder.reversed() {
                if watched.contains(key), let item = items[key] {
                    return item
                }
            }
            
            return watchedItems.last
        }
        
        func favouriteItem(for kind: MediaKind) -> MediaItem? {
            switch kind {
            case .movie:
                return favouriteMovie
            case .tv:
                return favouriteSeries
            case .person:
                return nil
            }
        }
        
        func isFavourite(_ item: MediaItem) -> Bool {
            switch item.kind {
            case .movie:
                return favouriteMovieKey == item.key
            case .tv:
                return favouriteSeriesKey == item.key
            case .person:
                return false
            }
        }
        
        mutating func setFavourite(_ item: MediaItem) {
            items[item.key] = item
            
            switch item.kind {
            case .movie:
                favouriteMovieKey = item.key
            case .tv:
                favouriteSeriesKey = item.key
            case .person:
                break
            }
        }
        
        mutating func clearFavourite(for kind: MediaKind) {
            switch kind {
            case .movie:
                favouriteMovieKey = nil
            case .tv:
                favouriteSeriesKey = nil
            case .person:
                break
            }
        }
        
        mutating func recordWatchOrderChange(for item: MediaItem) {
            items[item.key] = item
            watchedOrder.removeAll { $0 == item.key }
            
            if watched.contains(item.key) {
                watchedOrder.append(item.key)
            }
        }
    }
    
    private struct EpisodeKey: Codable, Hashable { let show: MediaKey; let season: Int; let episode: Int }
    private struct MediaCollection: Identifiable, Codable, Hashable { var id = UUID(); var name: String; var isDynamic: Bool; var itemKeys: Set<MediaKey> = [] }
    
    private struct AppSettings: Codable, Hashable {
        var recommendationStrength: Double = 3.5
        var appearance: AppearanceMode = .dark
        var accent: AccentChoice = .blue
        var accentRed: Double = 0.20
        var accentGreen: Double = 0.44
        var accentBlue: Double = 1.00
        var name: String = ""
        var prioritiseEnglish: Bool = true
        var removeItemsFromWatchlist: Bool = false
        var usePlainBackground: Bool = false
        var hapticsEnabled: Bool = true
        var hideAdultResults: Bool = false
        var hideAnimeResults: Bool = false
        var hideWatchedFromHome: Bool = false
        var hideWatchedFromSearch: Bool = false
        var hideShortFilmsFromHome = false
        var hideShortFilmsFromSearch = false
        var hideShortFilmsFromRecommended = false
        var hideShortFilmsFromCollectionRecommendations = false
        var defaultSearchFilter: SearchFilter = .movie
        var defaultHomeFilter: MediaFilter = .both
        var defaultCategorySort: GenreSort = .tmdbRating
        var showUpcomingReleases: Bool = true
        var hideUpcomingFromSearch = false
        var hideUpcomingFromRecommended = false
        var hideUpcomingFromCollectionRecommendations = false
        var warnBeforeReplacingFavourite = true
        var promptToRateAfterMarkingWatched = true
    }
    
    private extension AppSettings {
        var accentColor: Color {
            Color(red: accentRed, green: accentGreen, blue: accentBlue)
        }
        
        mutating func setAccentColor(_ color: Color) {
#if canImport(UIKit)
            let uiColor = UIColor(color)
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            
            accentRed = Double(red)
            accentGreen = Double(green)
            accentBlue = Double(blue)
#else
            accentRed = 0.20
            accentGreen = 0.44
            accentBlue = 1.00
#endif
        }
    }
    
    private enum AppearanceMode: String, Codable, CaseIterable, Identifiable { case dark, light; var id: String { rawValue }; var title: String { rawValue.capitalized } }
    private enum PersonKnownForSort: String, CaseIterable, Identifiable {
        case rating
        case date
        
        var id: String { rawValue }
        
        var title: String {
            switch self {
            case .rating:
                return "Rating"
            case .date:
                return "Date"
            }
        }
    }
    private struct PersonKnownForSortPicker: View {
        @Binding var sort: PersonKnownForSort
        
        var body: some View {
            HStack(spacing: 0) {
                ForEach(PersonKnownForSort.allCases) { item in
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            sort = item
                        }
                    } label: {
                        Text(item.title)
                            .font(.caption.bold())
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                            .selectedGlassCapsule(isSelected: sort == item)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .liquidGlass(cornerRadius: 18)
        }
    }
    private enum AccentChoice: String, Codable, CaseIterable, Identifiable {
        case blue, purple, green, orange
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var color: Color { switch self { case .blue: return .blue; case .purple: return .purple; case .green: return .green; case .orange: return .orange } }
    }
    
    private enum AppTab: String, CaseIterable, Identifiable { case home, search, forYou, watchlist, collections; var id: String { rawValue } }
    private enum TabTransitionDirection { case forward, backward }
    private extension AppTab {
        var title: String { switch self { case .home: return "Home"; case .search: return "Search"; case .forYou: return "For You"; case .watchlist: return "Watchlist"; case .collections: return "Collections" } }
        var icon: String { switch self { case .home: return "house"; case .search: return "magnifyingglass"; case .forYou: return "sparkles"; case .watchlist: return "bookmark"; case .collections: return "rectangle.stack" } }
        
        var sortIndex: Int {
            switch self {
            case .home: return 0
            case .search: return 1
            case .forYou: return 2
            case .watchlist: return 3
            case .collections: return 4
            }
        }
    }
    
    private enum MediaFilter: String, Codable, CaseIterable, Identifiable { case both, movie, tv; var id: String { rawValue } }
    
    private enum RuntimeSearchFilter: String, Codable, CaseIterable, Identifiable {
        case any
        case underOneHour
        case oneToNinety
        case ninetyToTwoHours
        case twoToTwoAndHalf
        case twoAndHalfToThree
        case overThreeHours
        
        var id: String { rawValue }
        
        var title: String {
            switch self {
            case .any: return "Any runtime"
            case .underOneHour: return "<1hr"
            case .oneToNinety: return "1–1.5hr"
            case .ninetyToTwoHours: return "1.5–2hr"
            case .twoToTwoAndHalf: return "2–2.5hr"
            case .twoAndHalfToThree: return "2.5–3hr"
            case .overThreeHours: return ">3hr"
            }
        }
        
        var minimumMinutes: Int? {
            switch self {
            case .any: return nil
            case .underOneHour: return nil
            case .oneToNinety: return 60
            case .ninetyToTwoHours: return 90
            case .twoToTwoAndHalf: return 120
            case .twoAndHalfToThree: return 150
            case .overThreeHours: return 180
            }
        }
        
        var maximumMinutes: Int? {
            switch self {
            case .any: return nil
            case .underOneHour: return 59
            case .oneToNinety: return 89
            case .ninetyToTwoHours: return 119
            case .twoToTwoAndHalf: return 149
            case .twoAndHalfToThree: return 179
            case .overThreeHours: return nil
            }
        }
        
        var isActive: Bool { self != .any }
    }
    private extension MediaFilter { var title: String { self == .both ? "Both" : (self == .movie ? "Movies" : "Series") }; var tmdbPath: String { self == .both ? "all" : (self == .movie ? "movie" : "tv") } }
    private enum ViewMode: String, Codable { case tile, list }
    private enum SortOption: String, CaseIterable, Identifiable { case releaseDate, myRating, tmdbRating; var id: String { rawValue } }
    private enum GenreSort: String, Codable, CaseIterable, Identifiable { case tmdbRating, releaseDate; var id: String { rawValue }; var title: String { self == .tmdbRating ? "TMDb rating" : "Released" }; var tmdbSort: String { self == .tmdbRating ? "vote_average.desc" : "primary_release_date.desc" } }
    private enum SwipeContext { case none, watchlist, collection(UUID) }
    private enum SectionRoute: String, Hashable {
        case trending, popular, newReleases, upcoming
        
        var title: String {
            switch self {
            case .trending:
                return "Trending now"
            case .popular:
                return "Popular"
            case .newReleases:
                return "New releases"
            case .upcoming:
                return "Upcoming releases"
            }
        }
    }
    private struct GenreRoute: Hashable { let genre: GenreDefinition }
    
    private struct GenreDefinition: Identifiable, Hashable {
        var id: Int { tmdbID }
        let name: String
        let tmdbID: Int
        let iconicFilm: String
        let imageURL: String
        
        var imageURLValue: URL? {
            URL(string: imageURL)
        }
        
        static let all = [
            GenreDefinition(name: "Action", tmdbID: 28, iconicFilm: "Die Hard", imageURL: "https://image.tmdb.org/t/p/w780/4HWAQu28e2yaWrtupFPGFkdNU7V.jpg"),
            GenreDefinition(name: "Sci-Fi", tmdbID: 878, iconicFilm: "Blade Runner 2049", imageURL: "https://image.tmdb.org/t/p/w780/8rpDcsfLJypbO6vREc0547VKqEv.jpg"),
            GenreDefinition(name: "Fantasy", tmdbID: 14, iconicFilm: "The Lord of the Rings", imageURL: "https://image.tmdb.org/t/p/w780/6oom5QYQ2yQTMJIbnvbkBL9cHo6.jpg"),
            GenreDefinition(name: "Drama", tmdbID: 18, iconicFilm: "The Godfather", imageURL: "https://image.tmdb.org/t/p/w780/3bhkrj58Vtu7enYsRolD1fZdja1.jpg"),
            GenreDefinition(name: "Horror", tmdbID: 27, iconicFilm: "Alien", imageURL: "https://image.tmdb.org/t/p/w500/vfrQk5IPloGg1v9Rzbh2Eg3VGyM.jpg"),
            GenreDefinition(name: "Animation", tmdbID: 16, iconicFilm: "Spirited Away", imageURL: "https://image.tmdb.org/t/p/w780/39wmItIWsg5sZMyRUHLkWBcuVCM.jpg"),
            GenreDefinition(name: "Crime", tmdbID: 80, iconicFilm: "Pulp Fiction", imageURL: "https://image.tmdb.org/t/p/w500/d5iIlFn5s0ImszYzBPb8JPIfbXD.jpg"),
            GenreDefinition(name: "Comedy", tmdbID: 35, iconicFilm: "Airplane!", imageURL: "https://image.tmdb.org/t/p/w780/hiURvJjCgk0s10urHVCg80TFF11.jpg"),
            GenreDefinition(name: "80s", tmdbID: 1980, iconicFilm: "Back to the Future", imageURL: "https://image.tmdb.org/t/p/w780/fNOH9f1aA7XRTzl1sAOx9iF553Q.jpg"),
            GenreDefinition(name: "90s", tmdbID: 1990, iconicFilm: "Jurassic Park", imageURL: "https://image.tmdb.org/t/p/w780/9i3plLl89DHMz7mahksDaAo7HIS.jpg"),
            GenreDefinition(name: "00s", tmdbID: 2000, iconicFilm: "The Dark Knight", imageURL: "https://image.tmdb.org/t/p/w780/qJ2tW6WMUDux911r6m7haRef0WH.jpg"),
            GenreDefinition(name: "10s", tmdbID: 2010, iconicFilm: "Interstellar", imageURL: "https://image.tmdb.org/t/p/w780/gEU2QniE6E77NI6lCU6MxlNBvIx.jpg")
        ]
        
        var gradient: LinearGradient { Self.gradient(for: tmdbID) }
        static func gradient(for id: Int?) -> LinearGradient {
            switch id {
            case 1980: return LinearGradient(colors: [.pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
            case 1990: return LinearGradient(colors: [.green, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
            case 2000: return LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
            case 2010: return LinearGradient(colors: [.indigo, .black], startPoint: .topLeading, endPoint: .bottomTrailing)
            case 28: return LinearGradient(colors: [.red, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
            case 878: return LinearGradient(colors: [.cyan, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
            case 14: return LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
            case 27: return LinearGradient(colors: [.black, .red], startPoint: .topLeading, endPoint: .bottomTrailing)
            default: return LinearGradient(colors: [.gray, .black], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
    }
    
    private extension MediaItem {
        var primaryCategoryGenreID: Int? {
            guard let firstGenreID = genreIDs.first else { return nil }
            return Self.categoryGenrePriorityMap[firstGenreID]
        }
        
        private static let categoryGenrePriorityMap: [Int: Int] = [
            28: 28,
            12: 28,
            878: 878,
            10765: 878,
            14: 14,
            18: 18,
            27: 27,
            16: 16,
            80: 80,
            35: 35,
            10759: 28
        ]
    }
    
    
    // MARK: - Helpers
    
    private enum DynamicCollections {
        static func inferredSeriesNames(for item: MediaItem) -> [String] {
            []
        }
        
        static func broadCollections(for item: MediaItem) -> [String] {
            let title = item.title.lowercased()
            var names: [String] = []
            if item.genreIDs.contains(878) || title.contains("space") || title.contains("martian") || title.contains("interstellar") { names.append("Space") }
            if item.genreIDs.contains(28) { names.append("Action") }
            if item.genreIDs.contains(80) { names.append("Crime") }
            if item.genreIDs.contains(14) { names.append("Fantasy") }
            return names
        }
    }
    
    private enum LoadErrorFilter {
        static func shouldIgnore(_ error: Error) -> Bool {
            if error is CancellationError {
                return true
            }
            
            if let urlError = error as? URLError, urlError.code == .cancelled {
                return true
            }
            
            return false
        }
    }
    
    private enum Storage {
        static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
            guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
            return try? JSONDecoder().decode(T.self, from: data)
        }
        static func save<T: Encodable>(_ value: T, key: String) {
            if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
        }
    }
    
    private enum DateParser {
        static func parse(_ text: String?) -> Date? {
            guard let text, !text.isEmpty else { return nil }
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.date(from: text)
        }
    }
    
    private extension Array where Element: Hashable {
        func frequencySorted() -> [Element] {
            var counts: [Element: Int] = [:]
            
            for element in self {
                counts[element, default: 0] += 1
            }
            
            return counts.sorted { lhs, rhs in
                if lhs.value != rhs.value {
                    return lhs.value > rhs.value
                }
                
                return String(describing: lhs.key) < String(describing: rhs.key)
            }
            .map(\.key)
        }
    }
    
    private extension Array where Element == MediaItem {
        func uniqued() -> [MediaItem] {
            var seen = Set<MediaKey>()
            return filter { seen.insert($0.key).inserted }
        }
        
        func sortedBySearchRelevance(_ query: String) -> [MediaItem] {
            let q = query.lowercased()
            return sorted {
                let aExact = $0.title.lowercased() == q
                let bExact = $1.title.lowercased() == q
                if aExact != bExact { return aExact }
                let aPrefix = $0.title.lowercased().hasPrefix(q)
                let bPrefix = $1.title.lowercased().hasPrefix(q)
                if aPrefix != bPrefix { return aPrefix }
                return $0.voteAverage > $1.voteAverage
            }
        }
        
        func sortedBySimilarity(to seed: MediaItem) -> [MediaItem] {
            sorted { lhs, rhs in
                let lhsScore = lhs.similarityScore(to: seed)
                let rhsScore = rhs.similarityScore(to: seed)
                
                if lhsScore != rhsScore {
                    return lhsScore > rhsScore
                }
                
                if lhs.voteAverage != rhs.voteAverage {
                    return lhs.voteAverage > rhs.voteAverage
                }
                
                return (lhs.releaseDateValue ?? .distantPast) > (rhs.releaseDateValue ?? .distantPast)
            }
        }
        
        func sorted(using option: SortOption, ratings: [MediaKey: Double]) -> [MediaItem] {
            sorted { a, b in
                switch option {
                case .releaseDate:
                    let av = a.releaseDateValue ?? .distantPast
                    let bv = b.releaseDateValue ?? .distantPast
                    if av != bv { return av > bv }
                case .myRating:
                    let av = ratings[a.key] ?? -1
                    let bv = ratings[b.key] ?? -1
                    if av != bv { return av > bv }
                case .tmdbRating:
                    if a.voteAverage != b.voteAverage { return a.voteAverage > b.voteAverage }
                }
                return (a.releaseDateValue ?? .distantPast) > (b.releaseDateValue ?? .distantPast)
            }
        }
        
        func sortedByCategoryRank() -> [MediaItem] {
            sorted { a, b in
                if a.voteAverage != b.voteAverage {
                    return a.voteAverage > b.voteAverage
                }
                return (a.releaseDateValue ?? .distantPast) > (b.releaseDateValue ?? .distantPast)
            }
        }
        
        func prefixArray(_ count: Int) -> [MediaItem] {
            Array(prefix(count))
        }
    }
    
    private extension Array where Element == PersonSummary {
        func uniquedPeople(excluding excludedIDs: Set<Int> = []) -> [PersonSummary] {
            var seen = excludedIDs
            return filter { seen.insert($0.id).inserted }
        }
    }
    
#if canImport(UIKit)
    @MainActor
    private func dismissKeyboardNow() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
#else
    @MainActor
    private func dismissKeyboardNow() {}
#endif
    
    
    // MARK: - Credit Filtering
    
    private enum CreditFilterText {
        static let blockedTitlePrefixes: [String] = [
            "the making of",
            "making of",
            "behind the scenes",
            "inside ",
            "a look inside",
            "a closer look",
            "the story of",
            "the legacy of"
        ]
        
        static let blockedPhrases: [String] = [
            "making of",
            "behind the scenes",
            "behind-the-scenes",
            "bts",
            "blooper",
            "bloopers",
            "gag reel",
            "deleted scenes",
            "special features",
            "featurette",
            "documentary about",
            "documentary on",
            "premiere special",
            "red carpet",
            "award show",
            "awards show",
            "academy awards",
            "golden globes",
            "emmy awards",
            "screen actors guild awards",
            "mtv movie awards",
            "critics choice awards"
        ]
    }
    
    private extension MediaItem {
        func similarityScore(to seed: MediaItem) -> Int {
            var score = 0
            
            if kind == seed.kind {
                score += 12
            }
            
            let sharedGenres = Set(genreIDs).intersection(Set(seed.genreIDs)).count
            score += sharedGenres * 10
            
            if originalLanguage == seed.originalLanguage {
                score += 5
            }
            
            if let seedYear = seed.releaseDateValue.map({ Calendar.current.component(.year, from: $0) }),
               let itemYear = releaseDateValue.map({ Calendar.current.component(.year, from: $0) }) {
                let yearGap = abs(seedYear - itemYear)
                
                if yearGap <= 2 {
                    score += 6
                } else if yearGap <= 5 {
                    score += 4
                } else if yearGap <= 10 {
                    score += 2
                }
            }
            
            return score
        }
    }
    
    private extension MediaItem {
        var shouldShowInPersonCredits: Bool {
            guard !title.isEmpty else { return false }
            guard kind != .person else { return false }
            guard !hasBlockedCreditTitle else { return false }
            guard !hasBlockedCreditPhrase else { return false }
            guard !hasSelfCreditRole else { return false }
            return true
        }
        
        private var normalizedCreditTitle: String {
            title.lowercased()
        }
        
        private var normalizedCreditOverview: String {
            overview.lowercased()
        }
        
        private var normalizedCreditRole: String {
            (creditRole ?? "").lowercased()
        }
        
        private var normalizedCreditCombinedText: String {
            normalizedCreditTitle + " " + normalizedCreditOverview + " " + normalizedCreditRole
        }
        
        private var hasBlockedCreditTitle: Bool {
            for prefix in CreditFilterText.blockedTitlePrefixes {
                if normalizedCreditTitle.hasPrefix(prefix) { return true }
            }
            return false
        }
        
        private var hasBlockedCreditPhrase: Bool {
            let text = normalizedCreditCombinedText
            for phrase in CreditFilterText.blockedPhrases {
                if text.contains(phrase) { return true }
            }
            return false
        }
        
        private var hasSelfCreditRole: Bool {
            let role = normalizedCreditRole
            if role == "self" { return true }
            if role == "himself" { return true }
            if role == "herself" { return true }
            if role == "themselves" { return true }
            if role.hasPrefix("self -") { return true }
            return false
        }
    }
    
    private extension View {
        @ViewBuilder
        func appScrollTouchSafe() -> some View {
            self
        }
        @ViewBuilder
        func liquidGlass(cornerRadius: CGFloat = 24) -> some View {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            
            if #available(iOS 26.0, *) {
                self
                    .padding(1)
                    .background(.clear, in: shape)
                    .glassEffect(.regular, in: shape)
                    .clipShape(shape)
                    .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 9)
            } else {
                self
                    .background {
                        shape
                            .fill(.ultraThinMaterial)
                            .background(
                                shape.fill(.white.opacity(0.10))
                            )
                            .overlay {
                                shape.stroke(.white.opacity(0.16), lineWidth: 1)
                            }
                            .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 10)
                    }
                    .clipShape(shape)
            }
        }
        
        @ViewBuilder
        func sheetLiquidGlass(cornerRadius: CGFloat = 54) -> some View {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            
            if #available(iOS 26.0, *) {
                self
                    .glassEffect(.regular, in: shape)
                    .clipShape(shape)
                    .shadow(color: .black.opacity(0.10), radius: 18, x: 0, y: 10)
            } else {
                self
                    .background {
                        shape
                            .fill(.clear)
                            .shadow(color: .black.opacity(0.10), radius: 18, x: 0, y: 10)
                    }
                    .clipShape(shape)
            }
        }
        
        @ViewBuilder
        func selectedGlassCapsule(isSelected: Bool) -> some View {
            if isSelected {
                if #available(iOS 26.0, *) {
                    self
                        .padding(.horizontal, 1)
                        .background(.white.opacity(0.10), in: Capsule())
                        .glassEffect(.regular, in: Capsule())
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 5)
                } else {
                    self
                        .background(.white.opacity(0.18), in: Capsule())
                        .overlay {
                            Capsule()
                                .stroke(.white.opacity(0.18), lineWidth: 1)
                        }
                }
            } else {
                self
                    .background(.clear, in: Capsule())
            }
        }
        
        @ViewBuilder
        func edgeBackGesture(isEnabled: Bool = true, action: @escaping () -> Void) -> some View {
            if isEnabled {
                self
                    .background(alignment: .leading) {
                        Color.clear
                            .frame(width: 18)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 18, coordinateSpace: .global)
                                    .onEnded { value in
                                        let mostlyHorizontal = abs(value.translation.width) > abs(value.translation.height) * 2.0
                                        let swipedRight = value.translation.width > 84
                                        
                                        if mostlyHorizontal && swipedRight {
                                            action()
                                        }
                                    }
                            )
                    }
            } else {
                self
            }
        }
    }
    
#if canImport(UIKit)
    private struct ScrollViewTouchTuningView: UIViewRepresentable {
        let axis: Axis.Set
        
        func makeUIView(context: Context) -> UIView {
            let view = UIView(frame: .zero)
            view.isUserInteractionEnabled = false
            DispatchQueue.main.async { configureNearestScrollView(from: view) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { configureNearestScrollView(from: view) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { configureNearestScrollView(from: view) }
            return view
        }
        
        func updateUIView(_ uiView: UIView, context: Context) {
            DispatchQueue.main.async { configureNearestScrollView(from: uiView) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { configureNearestScrollView(from: uiView) }
        }
        
        private func configureNearestScrollView(from view: UIView) {
            var current = view.superview
            
            while let candidate = current {
                if let scrollView = candidate as? UIScrollView {
                    configure(scrollView)
                    return
                }
                
                current = candidate.superview
            }
        }
        
        private func configure(_ scrollView: UIScrollView) {
            scrollView.panGestureRecognizer.minimumNumberOfTouches = 1
            scrollView.delaysContentTouches = false
            scrollView.canCancelContentTouches = true
            scrollView.keyboardDismissMode = .onDrag
            scrollView.isDirectionalLockEnabled = true
            scrollView.showsVerticalScrollIndicator = false
            scrollView.showsHorizontalScrollIndicator = false
            scrollView.alwaysBounceVertical = false
            scrollView.alwaysBounceHorizontal = false
            
            let verticalInset = scrollView.adjustedContentInset.top + scrollView.adjustedContentInset.bottom
            let horizontalInset = scrollView.adjustedContentInset.left + scrollView.adjustedContentInset.right
            let canScrollVertically = scrollView.contentSize.height + verticalInset > scrollView.bounds.height + 1
            let canScrollHorizontally = scrollView.contentSize.width + horizontalInset > scrollView.bounds.width + 1
            
            scrollView.isScrollEnabled = true
            
            if axis == .horizontal {
                scrollView.bounces = canScrollHorizontally
            } else {
                scrollView.bounces = canScrollVertically
            }
        }
    }
    
    private extension View {
        func scrollViewTouchTuning(axis: Axis.Set = .vertical) -> some View {
            background(ScrollViewTouchTuningView(axis: axis))
        }
    }
#else
    private extension View {
        func scrollViewTouchTuning(axis: Axis.Set = .vertical) -> some View {
            self
        }
    }
#endif
    
    
    // MARK: - For You Section Route Model
    
    private struct ForYouSection: Identifiable, Hashable {
        let id = UUID()
        let title: String
        let items: [MediaItem]
    }
    
    // MARK: - Adaptive Layout
    
    private struct FullMediaListView: View {
        let title: String
        let items: [MediaItem]
        @ObservedObject var model: VestigoModel
        
        var body: some View {
            BaseScreen(title: title, filter: .constant(.both), settings: model.settings) {
                MediaGridOrList(items: items, hideWatchedForUpcoming: false, model: model)
            }
        }
    }
    
    
    private struct StreamingProviderBubble: View {
        let option: StreamingOption

        var body: some View {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.10))

                RemoteImageView(
                    url: option.logoURL,
                    fallback: AnyView(
                        Text(option.serviceShort)
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                    )
                )
                .frame(width: 56, height: 56)
                .clipShape(Circle())
            }
            .frame(width: 46, height: 46)
            .clipShape(Circle())
            .contentShape(Circle())
        }
    }
    
    
// MARK: - Streaming Option Row Subtitle Helper
    private extension View {
        /// Helper for building streaming option subtitle
        func streamingSubtitle(for option: StreamingOption) -> String {
            var parts: [String] = [option.availabilityText]
            let trimmedPrice = option.priceText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedPrice.isEmpty && trimmedPrice.lowercased() != "price unavailable" {
                parts.append(trimmedPrice)
            }
            
            let trimmedQuality = option.qualityText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedQuality.isEmpty {
                parts.append(trimmedQuality)
            }
            
            return parts.joined(separator: " • ")
        }
    }
    
    
    private extension Text {
        func sectionTitle() -> some View {
            self.font(.system(size: 20, weight: .black, design: .rounded))
        }
    }
    
    private struct ExportDocument: FileDocument {
        static var readableContentTypes: [UTType] { [.plainText] }
        var text: String
        init(text: String = "") { self.text = text }
        init(configuration: ReadConfiguration) throws { text = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? "" }
        func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
    }
    
    
    
// MARK: - Person Search Result Row
private struct PersonSearchResultRow: View {
    let person: PersonSummary
    @ObservedObject var model: VestigoModel
        
    var body: some View {
        Button {
            model.selectedPerson = person
        } label: {
            HStack(spacing: 12) {
                PersonImageView(person: person, width: 58, height: 76)
                
                VStack(alignment: .leading, spacing: 5) {
                    Text(person.name)
                        .font(.headline.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        
                    Text(person.role.isEmpty ? "Known for" : person.role)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                    
                Spacer(minLength: 0)
                
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .liquidGlass(cornerRadius: 22)
        }
        .buttonStyle(.plain)
    }
}
    
    
// MARK: - Setting Bubble Modifier

    private struct SettingBubbleModifier: ViewModifier {
        func body(content: Content) -> some View {
            content
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .liquidGlass(cornerRadius: 24)
        }
    }

    private extension View {
        func settingBubble() -> some View {
            self
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.black.opacity(0.2))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }
    
    
// MARK: - String Normalization Helper
    
private extension String {
    var normalizedRecommendationText: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: ":", with: " ")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "’", with: "")
    }
}
    
    
// MARK: - Standard Preview Macro
    
#Preview {
    ContentView()
}
