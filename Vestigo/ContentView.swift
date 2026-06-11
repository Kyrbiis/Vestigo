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

private let pickForMeHistoricalTrueEventSignals: [String] = [
    "true story",
    "based on true",
    "based on actual",
    "real events",
    "real-life",
    "true events",
    "actual events",
    "based on the life",
    "biopic"
]

private let pickForMeHistoricalContextSignals: [String] = [
    "political history",
    "historical event",
    "world war",
    "world war i",
    "world war ii",
    "wwi",
    "wwii",
    "civil war",
    "cold war",
    "holocaust",
    "nazi",
    "revolution",
    "president",
    "prime minister",
    "queen",
    "king",
    "roman empire",
    "tudor",
    "dynasty"
]

private let pickForMeNonHistoricalDocumentarySignals: [String] = [
    "nature",
    "wildlife",
    "planet",
    "climate",
    "environment",
    "ocean",
    "animal",
    "animals",
    "music",
    "concert",
    "sports",
    "stand-up",
    "comedy special",
    "behind the scenes",
    "making of"
]

private let pickForMeHumanTriumphSignals: [String] = [
    "overcome",
    "overcoming",
    "triumph",
    "perseverance",
    "resilience",
    "underdog",
    "against the odds",
    "inspiring",
    "inspirational",
    "determination",
    "adversity",
    "achievement",
    "champion",
    "courage",
    "barrier",
    "barriers",
    "obstacle",
    "obstacles",
    "disability",
    "disabled",
    "redemption",
    "breakthrough"
]

private let pickForMeWarDealBreakerSignals: [String] = [
    "war",
    "wartime",
    "battlefield",
    "soldier",
    "troops",
    "military",
    "armed forces",
    "front line",
    "invasion",
    "invades",
    "invading",
    "occupation",
    "occupied",
    "resistance fighter",
    "armed resistance",
    "guerrilla",
    "enemy forces",
    "foreign army",
    "paratrooper"
]

private let pickForMeHistoricalGenreIDs: Set<Int> = [36]
private let pickForMeWarGenreIDs: Set<Int> = [10752, 10768]

@MainActor
private final class RemoteImageMemoryCache {
    static let shared = RemoteImageMemoryCache()
    private var images: [URL: PlatformImage] = [:]

    func image(for url: URL) -> PlatformImage? {
        images[url]
    }

    func setImage(_ image: PlatformImage, for url: URL) {
        images[url] = image
    }
}

// MARK: - App Entry

struct ContentView: View {
    @StateObject private var model = VestigoModel()
    @Namespace private var tabNamespace

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
        .environment(\.imageRefreshToken, model.imageRefreshToken)
        .environment(\.refreshImages, RefreshImagesAction {
            model.refreshImages()
        })
        .task { await model.bootstrap() }
        .sheet(item: $model.selectedItem) { item in
            DetailView(item: item, model: model)
        }
        .sheet(item: $model.selectedPerson) { person in
            PersonDetailView(person: person, model: model)
        }
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

    var shouldShowInDiscovery: Bool {
        let normalizedTitle = title
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedOverview = overview
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let normalizedReleaseDate = (releaseDate ?? "")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedTitle.isEmpty else { return false }
        guard voteAverage > 0 else { return false }
        guard let releaseDate, let releaseYear = Int(releaseDate.prefix(4)), releaseYear > 1870 else { return false }
        if normalizedReleaseDate == "tba" || normalizedReleaseDate == "date tba" { return false }
        if normalizedReleaseDate.contains("tba") { return false }
        if normalizedTitle.hasPrefix("untitled") { return false }
        if normalizedTitle == "tba" || normalizedTitle == "plot tba" { return false }
        if normalizedOverview == "plot tba" || normalizedOverview == "tba" { return false }
        if normalizedOverview == "plot unknown" || normalizedOverview == "no plot available" { return false }
        if normalizedTitle.contains(" tba") { return false }
        return true
    }

    var releaseYearNumber: Int? {
        if let releaseDate, releaseDate.count >= 4 {
            return Int(releaseDate.prefix(4))
        }

        return Int(releaseYearText.prefix(4))
    }
}

private struct ImageRefreshTokenKey: EnvironmentKey {
    static let defaultValue = 0
}

private struct RefreshImagesAction {
    let action: () -> Void

    func callAsFunction() {
        action()
    }
}

private struct RefreshImagesKey: EnvironmentKey {
    static let defaultValue = RefreshImagesAction {}
}

private extension EnvironmentValues {
    var imageRefreshToken: Int {
        get { self[ImageRefreshTokenKey.self] }
        set { self[ImageRefreshTokenKey.self] = newValue }
    }

    var refreshImages: RefreshImagesAction {
        get { self[RefreshImagesKey.self] }
        set { self[RefreshImagesKey.self] = newValue }
    }
}

private extension URL {
    func refreshedImageURL(token: Int) -> URL {
        guard token > 0 else { return self }

        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)
        var queryItems = components?.queryItems ?? []
        queryItems.removeAll { $0.name == "vestigoRefresh" }
        queryItems.append(URLQueryItem(name: "vestigoRefresh", value: String(token)))
        components?.queryItems = queryItems

        return components?.url ?? self
    }
}

private struct WatchedImportEntry {
    let rawText: String
    let title: String
    let rating: Double
    let isFavourite: Bool
    let mediaFilter: MediaFilter?

    var isMissingMediaIdentifier: Bool {
        mediaFilter == nil
    }

    private static let mediaIdentifierTokens = ["m", "s"]

    enum ImportFormat {
        case automatic
        case commaSeparated
    }

    static func report(for text: String, format: ImportFormat = .automatic) -> WatchedImportReport {
        let rawEntries = splitEntries(text, format: format)
        var entries: [WatchedImportEntry] = []
        var malformed: [String] = []

        for rawText in rawEntries {
            if format == .commaSeparated && rawText.contains("\n") {
                malformed.append(rawText)
                continue
            }

            guard let entry = parseEntry(rawText) else {
                malformed.append(rawText)
                continue
            }

            entries.append(entry)
        }

        return WatchedImportReport(entries: entries, malformed: malformed)
    }

    static func parse(_ text: String) -> [WatchedImportEntry] {
        report(for: text).entries
    }

    private static func splitEntries(_ text: String, format: ImportFormat) -> [String] {
        let normalizedText = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let separator: Character = format == .commaSeparated
            ? ","
            : (normalizedText.contains("\n") ? "\n" : ",")

        return normalizedText
            .split(separator: separator, omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func parseEntry(_ rawText: String) -> WatchedImportEntry? {
        var tokens = rawText.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard tokens.count >= 2 else { return nil }

        var mediaFilter: MediaFilter?
        if let lastToken = tokens.last?.lowercased(), mediaIdentifierTokens.contains(lastToken) {
            mediaFilter = lastToken == "m" ? .movie : .tv
            tokens.removeLast()
        }

        var isFavourite = false
        if tokens.last?.localizedCaseInsensitiveCompare("f") == .orderedSame {
            isFavourite = true
            tokens.removeLast()
        }

        guard let lastToken = tokens.last, let parsedRating = Double(lastToken), (0...5).contains(parsedRating) else {
            return nil
        }

        tokens.removeLast()
        let title = tokens.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }

        return WatchedImportEntry(
            rawText: rawText,
            title: title,
            rating: parsedRating,
            isFavourite: isFavourite,
            mediaFilter: mediaFilter
        )
    }

    var mediaIdentifierText: String {
        switch mediaFilter {
        case .movie:
            return "m"
        case .tv:
            return "s"
        case .both, .none:
            return ""
        }
    }

    static func exportLine(for item: MediaItem, rating: Double?, isFavourite: Bool) -> String {
        var parts = [item.title]

        if let rating {
            parts.append(rating.formatted(.number.precision(.fractionLength(0...1))))
        }

        if isFavourite {
            parts.append("f")
        }

        parts.append(item.kind == .tv ? "s" : "m")

        return parts.joined(separator: " ")
    }

    static func warningMessage(for report: WatchedImportReport) -> String? {
        var sections: [String] = []

        if !report.unclearItems.isEmpty {
            sections.append("The following items are unclear because they do not end in m for movie or s for series:\n\(report.unclearItems.joined(separator: "\n"))")
        }

        if !report.malformed.isEmpty {
            sections.append("The following lines may be formatted incorrectly and could cause import errors:\n\(report.malformed.joined(separator: "\n"))")
        }

        guard !sections.isEmpty else { return nil }

        return "\(sections.joined(separator: "\n\n"))\n\nDouble-check before pressing Continue."
    }
}

private struct WatchedImportReport {
    let entries: [WatchedImportEntry]
    let malformed: [String]

    var unclearItems: [String] {
        entries
            .filter(\.isMissingMediaIdentifier)
            .map(\.rawText)
    }

    var hasWarnings: Bool {
        !unclearItems.isEmpty || !malformed.isEmpty
    }
}

private extension WatchedImportEntry {
    static func normalizedTitle(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func matchScore(_ title: String, normalizedTitle query: String) -> Int {
        let normalized = normalizedTitle(title)

        if normalized == query {
            return 100
        }

        if normalized.contains(query) {
            return 75
        }

        if query.contains(normalized) {
            return 60
        }

        return 0
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
    @Published var minimumTMDbRatingFilter: SearchRatingFilter?
    @Published var searchText = ""
    @Published var searchFilter: SearchFilter = .all
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
    @Published var externalRatingsCache: [MediaKey: ExternalRatings] = [:]
    @Published var providerCache: [MediaKey: [StreamingOption]] = [:]
    @Published var personCreditsCache: [Int: [MediaItem]] = [:]
    @Published var personDetails: [Int: PersonDetail] = [:]
    @Published var collectionRecommendations: [UUID: [MediaItem]] = [:]
    @Published var pendingRatingPromptItem: MediaItem?
    @Published var pendingRatingPromptValue: Double = 0
    @Published var pendingRatingPromptMakeFavourite = false
    @Published var pendingRatingPromptRestoreWatchlist = false
    
    @Published var library = UserLibrary()
    @Published var settings = AppSettings()
    @Published var selectedItem: MediaItem?
    @Published var selectedPerson: PersonSummary?
    @Published var homePath: [SectionRoute] = []
    @Published var searchPath: [GenreRoute] = []
    @Published var isLoading = false
    @Published var errorText: String?
    @Published var exportDocument = ExportDocument(text: "")
    @Published var exportFormat: ExportFormat = .text
    @Published var showExporter = false
    @Published var pendingFavouriteReplacement: MediaItem?
    @Published var showFavouriteReplacementAlert = false
    @Published var forYouResetToken = UUID()
    @Published var watchlistResetToken = UUID()
    @Published var collectionsResetToken = UUID()
    @Published var imageRefreshToken = 0
    
    private let tmdb = TMDbService()
    private let tasteDive = TasteDiveService()
    private let streaming = StreamingAvailabilityService()
    private let backend = VestigoBackendClient()
    private let externalRatingBatchLimit = 24
    private let externalRatingSessionLimit = 200
    private var externalRatingRequestCount = 0
    private var externalRatingEmptyRefreshes: Set<MediaKey> = []
    private var searchTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var searchRequestID = UUID()
    private var mediaSearchCache: [String: [MediaItem]] = [:]
    private var peopleSearchCache: [String: [PersonSummary]] = [:]
    private var tasteDiveSimilarCache: [MediaKey: [MediaItem]] = [:]
    private var tmdbExpandedSimilarCache: [MediaKey: [MediaItem]] = [:]

    func refreshImages() {
        imageRefreshToken &+= 1
        URLCache.shared.removeAllCachedResponses()
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
        guard let runtime = detailsCache[item.key]?.runtime else { return false }

        return runtime > 0 && runtime <= 40
    }

    func shouldHideForLowestAgeRating(_ item: MediaItem, enabled: Bool) -> Bool {
        guard enabled else { return false }
        guard let ageRating = detailsCache[item.key]?.ageRating else { return false }
        return Self.isLowestAgeRating(ageRating)
    }

    private static func isLowestAgeRating(_ rawRating: String) -> Bool {
        let normalized = rawRating
            .uppercased()
            .replacingOccurrences(of: "_", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return ["G", "U", "TV-Y", "TV-G", "TV-Y7", "TV-Y7-FV"].contains(normalized)
    }

    func filteredShortFilmsIfNeeded(_ items: [MediaItem], enabled: Bool) async -> [MediaItem] {
        guard enabled || settings.hideLowestAgeRatings else { return items }

        var filtered: [MediaItem] = []

        for item in items {
            if detailsCache[item.key] == nil {
                await loadBasicDetailIfNeeded(item)
            }

            if shouldHideAsShortFilm(item, enabled: enabled) {
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
        loadLocal()
        await loadHome()
    }
    
    func loadHome() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
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

            let loadedTrending = await filteredShortFilmsIfNeeded(preparedTrending, enabled: settings.hideShortFilmsFromHome)
            let loadedPopular = await filteredShortFilmsIfNeeded(preparedPopular, enabled: settings.hideShortFilmsFromHome)
            let loadedNewReleases = await filteredShortFilmsIfNeeded(preparedNewReleases, enabled: settings.hideShortFilmsFromHome)
            let loadedUpcoming = await filteredShortFilmsIfNeeded(preparedUpcoming, enabled: settings.hideShortFilmsFromHome)

            if !loadedTrending.isEmpty { trending = loadedTrending }
            if !loadedPopular.isEmpty { popular = loadedPopular }
            if !loadedNewReleases.isEmpty { newReleases = loadedNewReleases }
            if !loadedUpcoming.isEmpty { upcoming = loadedUpcoming }
            await loadSmartRecommendations()
        } catch {
            if !LoadErrorFilter.shouldIgnore(error) {
                errorText = error.localizedDescription
            }
        }
    }

    func refreshHome() async {
        await loadHome()
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
                
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
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
                    guard !library.isNeverShowAgain(candidate.key) else { continue }
                    
                    let positionScore = 1.0 / (1.0 + Double(index) * 0.08)
                    let similarityBoost = genreSimilarity(candidate, record) * (0.35 + normalizedStrength * 0.45)
                    let score = (positionScore + similarityBoost) * weight
                    
                    var entry = scoredRecommendations[candidate.key] ?? (candidate, 0)
                    entry.score += score
                    scoredRecommendations[candidate.key] = entry
                }
                
                let related = try await tmdb.sameSeriesOrSimilar(for: record.key)
                nextItems.append(contentsOf: related)
            } catch { }
        }
        
        await loadExternalRatings(for: scoredRecommendations.values.map(\.item), limit: 120)

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
        recommendations = await filteredShortFilmsIfNeeded(
            visibleRecommendations,
            enabled: settings.hideShortFilmsFromRecommended
        )
        seriesNext = await filteredShortFilmsIfNeeded(
            preparedResults(nextItems.uniqued().filter { !library.isWatched($0.key) && !library.isNeverShowAgain($0.key) }, hideWatched: true),
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
        let favouriteSeeds = library.favouriteItems
            .sorted { lhs, rhs in
                let lhsRating = library.ratings[lhs.key] ?? 2.5
                let rhsRating = library.ratings[rhs.key] ?? 2.5
                if lhsRating != rhsRating { return lhsRating > rhsRating }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }

        for favourite in favouriteSeeds.prefix(8) {
            do {
                favouriteRecommendations.append(contentsOf: try await tmdb.recommendations(for: favourite.key))
            } catch { }
        }

        if let primaryFavouriteSeed = favouriteSeeds.first {
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
                .filter { $0.shouldShowInDiscovery && !$0.isUpcoming && $0.genreIDs.contains(topGenreID) }
                .filter { !library.isNeverShowAgain($0.key) }
                .filter { settings.prioritiseEnglish ? (($0.originalLanguage ?? "en") == "en") : true }

            fromTopGenre = await filteredShortFilmsIfNeeded(
                preparedTopGenre,
                enabled: settings.hideShortFilmsFromRecommended
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

        await loadExternalRatings(for: trySomethingNewPool, limit: 80)

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

        trySomethingNewRecommendations = await filteredShortFilmsIfNeeded(
            preparedTrySomethingNew,
            enabled: settings.hideShortFilmsFromRecommended
        )
    }

    func pickForMeRecommendations(for answers: PickForMeAnswers) async -> [MediaItem] {
        let effectiveFilter = answers.effectiveMediaFilter
        let wantsMainstreamResults = answers.recommendationType == .crowdPleaser
        let wantsNewReleaseResults = answers.releaseAge == .newReleases
        let discoveryGenreIDs = pickForMeDiscoveryGenreIDs(for: answers)
        var sourceMaterialCandidateKeys: Set<MediaKey> = []
        var candidates = (
            recommendations +
            moreLikeLastWatched +
            moreLikeFavourite +
            fromTopGenre +
            seriesNext +
            library.watchlistItems
        )
        .uniqued()

        if wantsMainstreamResults {
            candidates.append(contentsOf: popular + trending)
        }

        if wantsNewReleaseResults {
            candidates.append(contentsOf: newReleases)
        }

        if wantsMainstreamResults || wantsNewReleaseResults {
            candidates.append(contentsOf: trySomethingNewRecommendations)
        }

        do {
            let discovered = try await tmdb.discoverPickForMe(
                filter: effectiveFilter,
                genreIDs: discoveryGenreIDs,
                runtime: answers.runtime,
                minimumRating: 0,
                includeAdult: !settings.hideAdultResults,
                sortBy: wantsMainstreamResults ? "popularity.desc" : "vote_average.desc"
            )
            candidates.append(contentsOf: discovered)
        } catch { }

        for supplementalGenreIDs in pickForMeSupplementalDiscoveryGenreIDs(for: answers) {
            do {
                let discovered = try await tmdb.discoverPickForMe(
                    filter: effectiveFilter,
                    genreIDs: supplementalGenreIDs,
                    runtime: answers.runtime,
                    minimumRating: 0,
                    includeAdult: !settings.hideAdultResults,
                    sortBy: wantsMainstreamResults ? "popularity.desc" : "vote_average.desc"
                )
                candidates.append(contentsOf: discovered)
            } catch { }
        }

        if let sourceMaterial = answers.sourceMaterial, sourceMaterial != .noPreference {
            do {
                let sourceMaterialCandidates = try await tmdb.discoverSourceMaterial(sourceMaterial, filter: effectiveFilter)
                sourceMaterialCandidateKeys = Set(sourceMaterialCandidates.map(\.key))
                candidates.append(contentsOf: sourceMaterialCandidates)
            } catch { }
        }

        let uniqueCandidates = candidates.uniqued()
        await loadExternalRatings(for: uniqueCandidates, limit: 160)
        await loadPickForMeStrictFilterDetails(for: uniqueCandidates, answers: answers)

        let filtered = uniqueCandidates
            .uniqued()
            .filter { item in
                guard !library.isWatched(item.key) else { return false }
                guard !settings.hideUpcomingFromRecommended || !item.isUpcoming else { return false }
                guard effectiveFilter == .both || item.kind.rawValue == effectiveFilter.rawValue else { return false }

                if !pickForMeRuntimeAllows(item, runtime: answers.runtime) {
                    return false
                }

                if !pickForMeReleaseAgeAllows(item, releaseAge: answers.releaseAge) {
                    return false
                }

                if !pickForMeDocumentaryAllows(item, answers: answers) {
                    return false
                }

                if !pickForMeSourceMaterialAllows(item, sourceMaterial: answers.sourceMaterial, sourceMaterialCandidateKeys: sourceMaterialCandidateKeys) {
                    return false
                }

                if !pickForMeRealismAllows(item, answers: answers) {
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

                if answers.dealBreakers.contains(where: { pickForMeDealBreakerMatches(item: item, dealBreaker: $0) }) {
                    return false
                }

                return true
            }

        let prepared = preparedResults(filtered, hideWatched: true)
        let visible = prepared.filter { item in
            !settings.hideShortFilmsFromRecommended || !shouldHideAsShortFilm(item, enabled: true)
        }

        let sorted = visible
            .sorted { lhs, rhs in
                let lhsScore = pickForMeScore(lhs, answers: answers)
                let rhsScore = pickForMeScore(rhs, answers: answers)

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

        return balancedPickForMeResults(sorted, filter: effectiveFilter, limit: 120)
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
            case .space, .noPreference:
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
            case .thriller:
                append([53])
            case .mystery, .mindBending:
                append([9648])
                append([878])
                append([53])
            case .heist:
                append([80])
                append([53])
                append([28])
            case .mission:
                append([28])
                append([53])
            case .smartProblems:
                append([18])
                append([53])
            case .adventure:
                append([12])
            case .thoughtfulSciFi:
                append([878])
            case .war:
                append(pickForMeWarGenreIDs)
            case .humanTriumph:
                append([18])
            case .feelGood, .comedy, .characterRelationships, .documentary, .historical, .epicSpectacle, .horror, .surprise, .noPreference:
                break
            }
        }

        switch answers.realism {
        case .someSpeculative:
            append([878])
            append([14])
        case .mostlyRealistic, .realWorld, .completelyFictional, .anything, nil:
            break
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

    private func pickForMeRuntimeAllows(_ item: MediaItem, runtime: PickForMeRuntime?) -> Bool {
        guard item.kind == .movie else { return true }
        guard let runtime, runtime != .any else { return true }
        guard let minutes = detailsCache[item.key]?.runtime ?? item.runtime else { return false }

        return runtime.contains(minutes)
    }

    private func loadPickForMeStrictFilterDetails(for items: [MediaItem], answers: PickForMeAnswers) async {
        let needsRuntime = answers.runtime != nil && answers.runtime != .any
        let needsContentRating = !answers.contentRatings.isEmpty && !answers.contentRatings.contains(.any)
        guard needsRuntime || needsContentRating else { return }

        for item in items.prefix(120) where detailsCache[item.key] == nil {
            do {
                detailsCache[item.key] = try await tmdb.detail(for: item)
            } catch { }
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

        switch sourceMaterial {
        case .trueStory:
            return text.containsAny(["based on true", "based on actual", "true story", "true events", "real events", "real-life", "real life"])
        case .book:
            return text.containsAny(["based on the novel", "based on a novel", "based on the book", "based on a book", "adapted from the novel", "adapted from a novel", "book by", "novel by"])
        case .game:
            return text.containsAny(["based on the video game", "based on a video game", "video game", "videogame", "game series", "computer game"])
        case .noPreference:
            return true
        }
    }

    private func pickForMeRealismAllows(_ item: MediaItem, answers: PickForMeAnswers) -> Bool {
        let genres = Set(item.genreIDs)
        let text = pickForMeSearchableText(for: item)

        switch answers.realism {
        case .realWorld:
            return !pickForMeIsSpeculative(genres: genres, text: text)
        case .mostlyRealistic, .someSpeculative, .completelyFictional, .anything, nil:
            return true
        }
    }

    private func pickForMeHistoryAllows(_ item: MediaItem, answers: PickForMeAnswers) -> Bool {
        guard answers.wantsStrictHistorical else { return true }

        let historicalScore = pickForMeHistoricalEventScore(genres: Set(item.genreIDs), text: pickForMeSearchableText(for: item))
        return historicalScore > 0
    }

    private func pickForMeScore(_ item: MediaItem, answers: PickForMeAnswers) -> Double {
        var score = max(ratingSortValue(for: item), 0) * 0.75
        let genreIDs = Set(item.genreIDs)
        let text = pickForMeSearchableText(for: item)

        if library.isNeverShowAgain(item.key) {
            score -= 250.0
        }

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

        if let seriousness = answers.seriousness {
            score += pickForMeSeriousnessScore(genres: genreIDs, text: text, seriousness: seriousness)
        }

        if let realism = answers.realism {
            score += pickForMeRealismScore(genres: genreIDs, text: text, realism: realism)
        }

        for actionLevel in answers.actionLevels where !actionLevel.isAnyOption {
            score += pickForMeActionScore(genres: genreIDs, actionLevel: actionLevel)
        }

        if let engagement = answers.engagement {
            score += pickForMeEngagementScore(genres: genreIDs, text: text, engagement: engagement)
        }

        if let recommendationType = answers.recommendationType {
            score += pickForMeRecommendationTypeScore(for: item, recommendationType: recommendationType)
        }

        if let minimumRating = answers.minimumRating {
            score += pickForMeMinimumRatingScore(for: item, minimumRating: minimumRating)
        }

        if item.genreIDs.contains(99) && !answers.wantsDocumentary {
            score -= pickForMeDocumentaryDownweight(for: answers)
        }

        score -= pickForMeArchetypeMismatchPenalty(genres: genreIDs, text: text, answers: answers)

        if answers.wantsHistorical && !genreIDs.intersection(pickForMeWarGenreIDs).isEmpty && !answers.wantsWar {
            score -= pickForMeHistoricalWarDownweight(for: answers)
        }

        if shouldPenalizeMissingContentRating(item, answers: answers) {
            score -= 1.5
        }

        if let goreLevel = answers.goreLevel {
            score += pickForMeGoreScore(genres: genreIDs, text: text, goreLevel: goreLevel)
        }

        if let sexLevel = answers.sexLevel {
            score += pickForMeSexScore(text: text, sexLevel: sexLevel)
        }

        if library.isInWatchlist(item.key) {
            score += 5.0
        }

        if recommendations.contains(where: { $0.key == item.key }) ||
            moreLikeLastWatched.contains(where: { $0.key == item.key }) ||
            moreLikeFavourite.contains(where: { $0.key == item.key }) {
            score += 2.5
        }

        score += pickForMePersonalizationScore(for: item)

        return score
    }

    private func pickForMeArchetypeScore(item: MediaItem, archetype: PickForMeArchetype) -> Double {
        let genres = Set(item.genreIDs)
        let text = pickForMeSearchableText(for: item)

        switch archetype {
        case .feelGood:
            return pickForMeKeywordScore(text, ["optimistic", "heartwarming", "friendship", "family", "personal growth", "inspiring", "uplifting", "feel-good", "new beginning"]) * 1.8 +
                (genres.intersection([35, 10751, 18, 12]).isEmpty ? 0 : 4.2) -
                (genres.intersection([27, 10752]).isEmpty ? 0 : 1.8)
        case .comedy:
            return pickForMeKeywordScore(text, ["satire", "buddy comedy", "workplace comedy", "funny", "comedian", "laugh"]) * 1.7 +
                (genres.contains(35) ? 5.0 : 0)
        case .mystery:
            return pickForMeKeywordScore(text, ["detective", "investigation", "conspiracy", "murder mystery", "whodunnit", "clue", "secret"]) * 2.0 +
                (genres.intersection([9648, 53, 80]).isEmpty ? 0 : 4.6)
        case .thriller:
            return pickForMeKeywordScore(text, ["danger", "survival", "suspense", "pursuit", "fugitive", "threat", "uncertainty", "crime"]) * 1.8 +
                (genres.intersection([53, 80, 28]).isEmpty ? 0 : 4.5)
        case .smartProblems:
            var score = pickForMeKeywordScore(text, ["investigation", "journalist", "scientist", "engineer", "rescue mission", "courtroom", "legal", "historical event", "based on true", "expert", "team"]) * 2.0
            score += genres.intersection([18, 53, 36]).isEmpty ? 0 : 4.0
            if genres.contains(14) || genres.contains(27) { score -= 2.5 }
            if genres.contains(35) && !genres.contains(18) { score -= 1.2 }
            return score
        case .mission:
            return pickForMeKeywordScore(text, ["mission", "operation", "rescue", "espionage", "military objective", "survival objective", "special operations", "spy", "objective"]) * 2.0 +
                (genres.intersection([53, 28, 10752, 80, 36]).isEmpty ? 0 : 4.2)
        case .heist:
            return pickForMeKeywordScore(text, ["heist", "robbery", "con artist", "con man", "con woman", "theft", "casino", "caper", "scheme", "steal"]) * 2.4 +
                (genres.intersection([80, 53, 35, 28]).isEmpty ? 0 : 4.0)
        case .adventure:
            return pickForMeKeywordScore(text, ["treasure", "expedition", "exploration", "archaeology", "quest", "journey", "travel"]) * 2.0 +
                (genres.intersection([12, 28, 10759]).isEmpty ? 0 : 4.4)
        case .characterRelationships:
            return pickForMeKeywordScore(text, ["family", "friendship", "relationship", "relationships", "coming of age", "personal growth", "love"]) * 1.7 +
                (genres.intersection([18, 35, 10749]).isEmpty ? 0 : 4.0)
        case .humanTriumph:
            return pickForMeKeywordScore(text, pickForMeHumanTriumphSignals) * 2.1 +
                (genres.intersection([18, 36]).isEmpty ? 0 : 3.2) -
                (genres.intersection([27, 878, 14]).isEmpty ? 0 : 2.0)
        case .documentary:
            return pickForMeKeywordScore(text, ["documentary", "docuseries", "true story", "real-life", "real life", "interview", "archive", "behind the scenes"]) * 2.1 +
                (genres.contains(99) ? 6.0 : 0)
        case .historical:
            return pickForMeHistoricalEventScore(genres: genres, text: text) * 1.65
        case .war:
            return pickForMeKeywordScore(text, pickForMeWarDealBreakerSignals) * 2.1 +
                (genres.intersection(pickForMeWarGenreIDs).isEmpty ? 0 : 6.0)
        case .epicSpectacle:
            return pickForMeKeywordScore(text, ["epic", "space", "disaster", "war", "planet", "future", "battle", "large-scale", "world"]) * 1.9 +
                (genres.intersection([878, 28, 12, 10752]).isEmpty ? 0 : 4.8)
        case .mindBending:
            return pickForMeKeywordScore(text, ["memory", "nonlinear", "alternate reality", "twist", "puzzle", "mind-bending", "reality", "dream"]) * 2.1 +
                (genres.intersection([9648, 878, 53]).isEmpty ? 0 : 4.0)
        case .horror:
            return pickForMeKeywordScore(text, ["supernatural", "monster", "possession", "slasher", "psychological horror", "terror", "dread", "haunted"]) * 2.0 +
                (genres.contains(27) ? 5.0 : 0)
        case .thoughtfulSciFi:
            return pickForMeKeywordScore(text, ["artificial intelligence", "ethics", "future society", "technology", "consciousness", "philosophical", "experiment"]) * 2.1 +
                (genres.intersection([878, 18]).isEmpty ? 0 : 4.1) -
                (genres.intersection([28, 10752]).isEmpty ? 0 : 1.0)
        case .surprise:
            return ratingSortValue(for: item) + (library.isInWatchlist(item.key) ? 2.0 : 0)
        case .noPreference:
            return 0
        }
    }

    private func pickForMeArchetypeCombinationBonus(primaryScores: [Double]) -> Double {
        let strongMatches = primaryScores.filter { $0 >= 3.5 }.count
        guard strongMatches >= 2 else { return 0 }
        return Double(strongMatches - 1) * 2.4
    }

    private func pickForMeSeriousnessScore(genres: Set<Int>, text: String, seriousness: PickForMeSeriousness) -> Double {
        switch seriousness {
        case .lightFun:
            return (genres.intersection([35, 12, 10751, 16]).isEmpty ? 0 : 3.0) - (genres.intersection([27, 10752]).isEmpty ? 0 : 2.5) - (text.containsAny(["grief", "tragedy", "terminal"]) ? 1.8 : 0)
        case .mostlyFun:
            return (genres.intersection([35, 12, 28]).isEmpty ? 0 : 2.2) - (genres.contains(27) ? 1.4 : 0)
        case .balanced:
            return 1.0
        case .serious:
            return genres.intersection([18, 53, 36, 10752]).isEmpty ? 0.4 : 2.6
        case .intense:
            return genres.intersection([53, 27, 28, 80, 10752]).isEmpty ? -0.5 : 3.4
        case .noPreference:
            return 0
        }
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
        case .noPreference:
            return 0
        }
    }

    private func pickForMeRealismScore(genres: Set<Int>, text: String, realism: PickForMeRealism) -> Double {
        let speculative = pickForMeIsSpeculative(genres: genres, text: text)
        switch realism {
        case .realWorld:
            return speculative ? -6.0 : (genres.intersection([18, 36, 53, 10752]).isEmpty ? 1.2 : 3.0)
        case .mostlyRealistic:
            return speculative ? -2.2 : 2.0
        case .someSpeculative:
            return speculative ? 1.8 : 0.8
        case .completelyFictional:
            let nonfictionPenalty = pickForMeIsNonfictionOrTrueEvent(genres: genres, text: text) ? -8.0 : 0
            return nonfictionPenalty + (speculative ? 2.0 : 1.4)
        case .anything:
            return 0
        }
    }

    private func pickForMeIsSpeculative(genres: Set<Int>, text: String) -> Bool {
        !genres.intersection([878, 14, 10765]).isEmpty || text.containsAny(["superhero", "magic", "alien", "monster"])
    }

    private func pickForMeIsNonfictionOrTrueEvent(genres: Set<Int>, text: String) -> Bool {
        genres.contains(99) || pickForMeHistoricalEventScore(genres: genres, text: text) > 0
    }

    private func pickForMeActionScore(genres: Set<Int>, actionLevel: PickForMeActionLevel) -> Double {
        let hasAction = !genres.intersection([28, 12, 53, 10752, 10759]).isEmpty
        switch actionLevel {
        case .none:
            return hasAction ? -3.5 : 2.0
        case .little:
            return hasAction ? 0.8 : 1.4
        case .moderate:
            return hasAction ? 2.6 : -0.4
        case .lots:
            return hasAction ? 4.0 : -1.5
        case .noPreference:
            return 0
        }
    }

    private func pickForMeEngagementScore(genres: Set<Int>, text: String, engagement: PickForMeEngagement) -> Double {
        switch engagement {
        case .easy:
            return (genres.intersection([35, 12, 28, 10751]).isEmpty ? 0.4 : 2.4) - (text.containsAny(["conspiracy", "nonlinear", "mind-bending", "puzzle"]) ? 2.0 : 0)
        case .moderate:
            return genres.intersection([18, 53, 12, 80]).isEmpty ? 0.8 : 2.0
        case .focused:
            return (genres.intersection([9648, 53, 878, 80]).isEmpty ? 0 : 3.0) + (text.containsAny(["investigation", "conspiracy", "mystery", "puzzle", "secret"]) ? 2.0 : 0) - (genres.contains(35) && !genres.contains(18) ? 1.5 : 0)
        case .noPreference:
            return 0
        }
    }

    private func pickForMeGoreScore(genres: Set<Int>, text: String, goreLevel: PickForMeGoreLevel) -> Double {
        let likelyGory = genres.contains(27) || text.containsAny(["gore", "bloody", "blood", "slasher", "violent", "brutal"])
        switch goreLevel {
        case .low:
            return likelyGory ? -3.2 : 1.1
        case .some:
            return likelyGory ? 2.1 : -0.4
        case .high:
            return likelyGory ? 3.4 : -0.8
        case .noPreference:
            return 0
        }
    }

    private func pickForMeSexScore(text: String, sexLevel: PickForMeSexLevel) -> Double {
        let likelySexual = text.containsAny(["sexual", "sex", "erotic", "affair", "seduction", "stripper", "prostitute", "brothel", "nude", "nudity"])
        switch sexLevel {
        case .low:
            return likelySexual ? -3.0 : 1.0
        case .some:
            return likelySexual ? 2.0 : -0.4
        case .high:
            return likelySexual ? 3.2 : -0.8
        case .noPreference:
            return 0
        }
    }

    private func pickForMeRecommendationTypeScore(for item: MediaItem, recommendationType: PickForMeRecommendationType) -> Double {
        let rating = ratingSortValue(for: item)
        let isFromMainstreamLists = popular.contains(where: { $0.key == item.key }) || trending.contains(where: { $0.key == item.key }) || newReleases.contains(where: { $0.key == item.key })

        switch recommendationType {
        case .crowdPleaser:
            return isFromMainstreamLists ? 1.4 : 0.2
        case .acclaimed:
            return rating >= 8 ? 3.6 : rating >= 7 ? 2.0 : -0.6
        case .hiddenGem:
            return !isFromMainstreamLists && rating >= 6.5 ? 3.0 : -0.4
        case .noPreference:
            return 0
        }
    }

    private func pickForMeMinimumRatingScore(for item: MediaItem, minimumRating: PickForMeMinimumRating) -> Double {
        guard let minimum = minimumRating.minimumRating else { return 0 }
        let rating = ratingSortValue(for: item)

        if rating >= minimum {
            return 3.0 + min((rating - minimum) * 1.4, 2.2)
        }

        if rating >= minimum - 0.4 {
            return -0.4
        }

        if rating >= minimum - 0.8 {
            return -1.8
        }

        return -4.0
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

        if answers.sourceMaterial == .trueStory || answers.realism == .realWorld {
            return 5.0
        }

        return 8.0
    }

    private func pickForMeHistoricalWarDownweight(for answers: PickForMeAnswers) -> Double {
        if answers.actionLevels.contains(.none) || answers.actionLevels.contains(.little) {
            return 18.0
        }

        if answers.archetypes.contains(.mission) || answers.secondaryArchetypes.contains(.mission) {
            return 8.0
        }

        return 14.0
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
        case .superhero:
            return text.containsAny(["superhero", "super hero", "marvel", "dc comics", "batman", "superman", "spider-man", "spider man", "avengers", "x-men", "comic book"])
        case .verySad:
            return text.containsAny(["grief", "tragedy", "terminal", "mourning", "devastating", "death of"])
        case .foreignLanguage:
            return item.originalLanguage != nil && item.originalLanguage != "en"
        case .longRuntime:
            let minutes = detailsCache[item.key]?.runtime ?? item.runtime
            return (minutes ?? 0) >= 180
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

        let visibleResults = await filteredShortFilmsIfNeeded(
            enrichedResults,
            enabled: settings.hideShortFilmsFromSearch
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
        let sequelTokens: Set<String> = ["2", "3", "4", "5", "6", "7", "8", "9", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix"]

        if sequelTokens.contains(firstToken) {
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

    private func normalizedSearchText(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .split(separator: " ")
            .joined(separator: " ")
    }

    private func normalizedSearchCacheKey(_ query: String, filter: SearchFilter) -> String {
        let minimumRatingKey = minimumTMDbRatingFilter.map { String($0.rawValue) } ?? "none"
        return "\(filter.rawValue)|\(normalizedSearchText(query))|\(settings.prioritiseEnglish)|\(settings.hideAdultResults)|\(settings.hideWatchedFromSearch)|\(settings.hideLowestAgeRatings)|\(minimumRatingKey)|\(selectedRuntimeFilters.map(\.rawValue).sorted().joined(separator: ","))|\(settings.hideShortFilmsFromSearch)"
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
            let visibleItems = await filteredShortFilmsIfNeeded(preparedItems, enabled: settings.hideShortFilmsFromSearch)
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
            detailsCache[item.key] = try await tmdb.detail(for: item)
        } catch { }
    }
    
    func loadDetail(_ item: MediaItem) async {
        if detailsCache[item.key] == nil {
            do { detailsCache[item.key] = try await tmdb.detail(for: item) } catch { }
        }
        if let detail = detailsCache[item.key], let collectionID = detail.tmdbCollectionID {
            do {
                let collectionItems = try await backend.tmdbCollectionRecommendations(collectionID: collectionID)
                detailsCache[item.key] = detail.addingSimilarCandidates(collectionItems, source: item)
            } catch { }
        }
        if let detail = detailsCache[item.key] {
            do {
                let expandedTMDbItems = try await expandedTMDbSimilarCandidates(for: item, detail: detail)
                detailsCache[item.key] = detail.addingSimilarCandidates(expandedTMDbItems, source: item)
            } catch { }
        }
        if let detail = detailsCache[item.key] {
            do {
                let tasteDiveItems = try await tasteDiveCandidates(for: item)
                detailsCache[item.key] = detail.addingSimilarCandidates(
                    tasteDiveItems,
                    source: item,
                    sourceBoosts: Dictionary(uniqueKeysWithValues: tasteDiveItems.map { ($0.key, 10.0) })
                )
            } catch { }
        }
        await loadExternalRatings(item, priority: true)
        if providerCache[item.key] == nil {
            do {
                providerCache[item.key] = try await streaming.providers(for: item)
            } catch {
                providerCache[item.key] = []
            }
        }
    }

    private func expandedTMDbSimilarCandidates(for item: MediaItem, detail: MediaDetail) async throws -> [MediaItem] {
        if let cached = tmdbExpandedSimilarCache[item.key] {
            return cached
        }

        let personIDs = Array(detail.castAndKeyCrew.map(\.id).prefix(8))
        async let keywordItems = tmdb.keywordDiscoveryCandidates(for: item, keywordIDs: detail.keywordIDs)
        async let personItems = tmdb.sharedPersonCandidates(for: item, personIDs: personIDs)
        let candidates = try await (keywordItems + personItems)
            .uniqued()
            .filter { $0.shouldShowInDiscovery && !$0.isUpcoming && $0.key != item.key }
        tmdbExpandedSimilarCache[item.key] = candidates
        return candidates
    }

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

    func loadExternalRatings(_ item: MediaItem, priority: Bool = false) async {
        guard item.kind == .movie || item.kind == .tv else { return }
        if let cachedRatings = externalRatingsCache[item.key] {
            if cachedRatings.imdbRating != nil {
                return
            }

            if !priority && externalRatingEmptyRefreshes.contains(item.key) {
                return
            }
        }

        if !priority && externalRatingRequestCount >= externalRatingSessionLimit {
            externalRatingsCache[item.key] = .empty
            return
        }

        if externalRatingsCache[item.key] != nil {
            externalRatingEmptyRefreshes.insert(item.key)
        }

        externalRatingRequestCount += 1

        do {
            if let ratings = try await backend.ratings(for: item), ratings.hasAnyRating {
                externalRatingsCache[item.key] = ratings
                externalRatingEmptyRefreshes.remove(item.key)
            } else {
                externalRatingsCache[item.key] = .empty
            }
        } catch {
            print("IMDb ratings failed for \(item.title): \(error.localizedDescription)")
            externalRatingsCache[item.key] = nil
        }
    }

    func loadExternalRatings(for items: [MediaItem], limit: Int = 80) async {
        let cappedLimit = min(limit, externalRatingBatchLimit)
        for item in items.prefix(cappedLimit) {
            await loadExternalRatings(item)
        }
    }

    func ratingDisplayText(for item: MediaItem) -> String {
        if let imdbRating = externalRatingsCache[item.key]?.imdbRating {
            return "IMDb \(imdbRating.formatted(.number.precision(.fractionLength(1))))"
        }

        if externalRatingsCache[item.key] == nil {
            return "IMDb loading"
        }

        return "TMDb \(item.voteAverage.formatted(.number.precision(.fractionLength(1))))"
    }

    func ratingSortValue(for item: MediaItem) -> Double {
        if let imdbRating = externalRatingsCache[item.key]?.imdbRating {
            return imdbRating
        }

        if externalRatingsCache[item.key] == nil {
            return item.voteAverage
        }

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
            personCreditsCache[person.id] = []
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
        Task { await loadSmartRecommendations() }
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

        await loadExternalRatings(for: filteredCandidates, limit: 120)

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

        library.toggleFavourite(item)
        saveLocalSoon()
        objectWillChange.send()
        Task { await loadSmartRecommendations() }
    }

    func toggleNeverShowAgain(_ item: MediaItem) {
        guard item.kind == .movie || item.kind == .tv else { return }

        library.toggleNeverShowAgain(item)

        if library.isNeverShowAgain(item.key) {
            removeFromForYouRecommendations(item)
        }

        saveLocalSoon()
        objectWillChange.send()
        Task { await loadSmartRecommendations() }
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

    func importWatchedText(_ text: String, format: WatchedImportEntry.ImportFormat = .automatic) async -> [String] {
        let entries = WatchedImportEntry.report(for: text, format: format).entries
        var notFound: [String] = []

        for entry in entries {
            do {
                if let first = try await bestImportMatch(for: entry) {
                    library.markWatched(first)
                    library.recordWatchOrderChange(for: first)

                    library.ratings[first.key] = entry.rating

                    if entry.isFavourite {
                        library.favouriteKeys.insert(first.key)
                    }

                    generateDynamicCollections(from: first)
                } else {
                    notFound.append(entry.title)
                }
            } catch {
                notFound.append(entry.title)
            }
        }

        saveLocalSoon()
        Task { await loadSmartRecommendations() }
        return notFound
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

    private func bestImportMatch(for entry: WatchedImportEntry) async throws -> MediaItem? {
        let filter = entry.mediaFilter ?? .both
        let results = try await tmdb.search(query: entry.title, filter: filter, includeAdult: !settings.hideAdultResults)
        let normalizedTitle = WatchedImportEntry.normalizedTitle(entry.title)

        return results
            .filter { $0.kind == .movie || $0.kind == .tv }
            .sorted { lhs, rhs in
                let lhsScore = WatchedImportEntry.matchScore(lhs.title, normalizedTitle: normalizedTitle)
                let rhsScore = WatchedImportEntry.matchScore(rhs.title, normalizedTitle: normalizedTitle)

                if lhsScore != rhsScore {
                    return lhsScore > rhsScore
                }

                return lhs.voteAverage > rhs.voteAverage
            }
            .first
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
            minimumTMDbRatingFilter = nil
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
        settings.preferredRatingSource = .imdb
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
    
    var body: some View {
        BaseScreen(
            title: "Vestigo",
            filter: $model.mediaFilter,
            settings: model.settings,
            headerAccessory: AnyView(
                Button {
                    model.homePath.append(.settings)
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
            ),
            onRefresh: {
                await model.refreshHome()
            }
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
        case .settings: return []
        }
    }

    @ViewBuilder
    var body: some View {
        switch route {
        case .settings:
            SettingsView(model: model)
        default:
            BaseScreen(title: route.title, filter: $model.mediaFilter, settings: model.settings, onRefresh: {
                await model.refreshHome()
            }) {
                MediaGridOrList(items: items, hideWatchedForUpcoming: route == .upcoming, model: model)
            }
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
        BaseScreen(title: "Search", filter: .constant(model.searchFilter.mediaFilter ?? .movie), settings: model.settings, onRefresh: {
            await model.refreshSearch()
        }) {
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

private struct MixedSearchResults: View {
    let mediaItems: [MediaItem]
    let people: [PersonSummary]
    @ObservedObject var model: VestigoModel

    private var mediaChunks: [[MediaItem]] {
        stride(from: 0, to: mediaItems.count, by: 2).map { start in
            Array(mediaItems[start..<min(start + 2, mediaItems.count)])
        }
    }

    var body: some View {
        if mediaItems.isEmpty && people.isEmpty {
            StatusBubble(title: "No results", text: "No movies, series, or people matched this search.")
        } else {
            VStack(spacing: 16) {
                ForEach(Array(mediaChunks.enumerated()), id: \.offset) { index, chunk in
                    MediaGridOrList(items: chunk, hideWatchedForUpcoming: false, model: model)

                    let personStart = index * 2
                    let personEnd = min(personStart + 2, people.count)

                    if personStart < personEnd {
                        VStack(spacing: 12) {
                            ForEach(Array(people[personStart..<personEnd])) { person in
                                PersonSearchResultRow(person: person, model: model, expanded: true)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                if mediaChunks.isEmpty {
                    VStack(spacing: 12) {
                        ForEach(people.prefix(8)) { person in
                            PersonSearchResultRow(person: person, model: model, expanded: true)
                        }
                    }
                    .padding(.vertical, 4)
                } else if people.count > mediaChunks.count * 2 {
                    VStack(spacing: 12) {
                        ForEach(Array(people.dropFirst(mediaChunks.count * 2).prefix(4))) { person in
                            PersonSearchResultRow(person: person, model: model, expanded: true)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
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
        BaseScreen(title: route.genre.name, filter: $genreFilter, settings: model.settings, onRefresh: {
            await model.loadGenre(route.genre, filter: genreFilter, sort: genreSort, forceRefresh: true)
        }) {
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
    @State private var forYouPath: [ForYouRoute] = []

    private var recentWatchedItem: MediaItem? {
        model.library.lastWatchedItem
    }

    private var favouriteItem: MediaItem? {
        model.library.favouriteItems(for: forYouFilter).first
    }

    private var topGenreTitle: String {
        let watchedGenreIDs = filteredForYou(model.library.watchedItems).flatMap(\.genreIDs)
        guard let topGenreID = watchedGenreIDs.frequencySorted().first else { return "your taste" }
        return GenreDefinition.all.first(where: { $0.tmdbID == topGenreID })?.name ?? "your taste"
    }

    private var watchlistPicks: [MediaItem] {
        filteredForYou(model.library.watchlistItems)
            .sorted(
                using: .tmdbRating,
                ratings: model.library.ratings,
                externalRatings: model.externalRatingsCache,
                ratingSource: model.settings.preferredRatingSource
            )
    }

    var body: some View {
        NavigationStack(path: $forYouPath) {
            BaseScreen(title: "For You", filter: $forYouFilter, settings: model.settings, onRefresh: {
                await model.loadSmartRecommendations()
            }) {
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
                            forYouPath.append(.section(ForYouSection(title: sectionTitle, items: sectionItems)))
                        }
                    }

                    if let favouriteItem, !filteredForYou(model.moreLikeFavourite).isEmpty {
                        let sectionTitle = "More like your favourite \(favouriteItem.kind.label.lowercased()): \(favouriteItem.title)"
                        let sectionItems = filteredForYou(model.moreLikeFavourite)

                        MediaSection(title: sectionTitle, items: sectionItems, hideWatchedForUpcoming: false, model: model) {
                            forYouPath.append(.section(ForYouSection(title: sectionTitle, items: sectionItems)))
                        }
                    }

                    if !watchlistPicks.isEmpty {
                        let sectionTitle = "From your watchlist"
                        let sectionItems = watchlistPicks

                        MediaSection(title: sectionTitle, items: sectionItems, hideWatchedForUpcoming: false, model: model) {
                            forYouPath.append(.section(ForYouSection(title: sectionTitle, items: sectionItems)))
                        }
                    }

                    if !filteredForYou(model.seriesNext).isEmpty {
                        let sectionTitle = "Continue with related series"
                        let sectionItems = filteredForYou(model.seriesNext)

                        MediaSection(title: sectionTitle, items: sectionItems, hideWatchedForUpcoming: false, model: model) {
                            forYouPath.append(.section(ForYouSection(title: sectionTitle, items: sectionItems)))
                        }
                    }

                    if !filteredForYou(model.fromTopGenre).isEmpty {
                        let sectionTitle = "More from \(topGenreTitle)"
                        let sectionItems = filteredForYou(model.fromTopGenre)

                        MediaSection(title: sectionTitle, items: sectionItems, hideWatchedForUpcoming: false, model: model) {
                            forYouPath.append(.section(ForYouSection(title: sectionTitle, items: sectionItems)))
                        }
                    }

                    if !filteredForYou(model.trySomethingNewRecommendations).isEmpty {
                        let sectionTitle = "Try something new"
                        let sectionItems = filteredForYou(model.trySomethingNewRecommendations)

                        MediaSection(title: sectionTitle, items: sectionItems, hideWatchedForUpcoming: false, model: model) {
                            forYouPath.append(.section(ForYouSection(title: sectionTitle, items: sectionItems)))
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    forYouPath.append(.pickForMe)
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
            .navigationDestination(for: ForYouRoute.self) { route in
                switch route {
                case .section(let section):
                    FullMediaListView(title: section.title, items: section.items, model: model)
                case .pickForMe:
                    PickForMeView(model: model, startingFilter: forYouFilter)
                }
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

private struct PickForMeView: View {
    @ObservedObject var model: VestigoModel
    let startingFilter: MediaFilter
    @Environment(\.dismiss) private var dismiss
    @State private var answers: PickForMeAnswers
    @State private var step = 0
    @State private var results: [MediaItem] = []
    @State private var resultIndex = 0
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var fallbackText: String?

    private var steps: [PickForMeStep] {
        PickForMeStep.steps(for: answers)
    }

    init(model: VestigoModel, startingFilter: MediaFilter) {
        self.model = model
        self.startingFilter = startingFilter
        self._answers = State(initialValue: PickForMeAnswers())
    }

    var body: some View {
        ZStack {
            AppBackground(settings: model.settings)
                .ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    Color.clear
                        .frame(height: 0)
                        .id("pickForMeTop")

                    VStack(alignment: .leading, spacing: 24) {
                        header

                        if results.isEmpty {
                            questionContent
                        } else {
                            resultContent
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 28)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize, axes: .vertical)
                .onChange(of: step) { _, _ in
                    scrollToTop(with: proxy)
                }
                .onChange(of: resultIndex) { _, _ in
                    scrollToTop(with: proxy)
                }
                .onChange(of: results.isEmpty) { _, _ in
                    scrollToTop(with: proxy)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
            }
        }
        .onChange(of: answers.mediaFormat) { _, _ in
            if answers.isSeriesOnly {
                answers.runtime = nil
            }

            if step >= steps.count {
                step = max(steps.count - 1, 0)
            }
        }
        .onChange(of: answers.archetypes) { _, newValue in
            answers.secondaryArchetypes.subtract(newValue)
            if newValue.contains(.documentary) {
                answers.dealBreakers.remove(.documentary)
            }
            if newValue.contains(.war) {
                answers.dealBreakers.remove(.war)
            }
        }
        .onChange(of: answers.secondaryArchetypes) { _, newValue in
            if newValue.contains(.documentary) {
                answers.dealBreakers.remove(.documentary)
            }
            if newValue.contains(.war) {
                answers.dealBreakers.remove(.war)
            }
        }
        .onChange(of: answers.contentRatings) { _, _ in
            if !answers.shouldAskGoreQuestion {
                answers.goreLevel = nil
                answers.sexLevel = nil
            }

            if step >= steps.count {
                step = max(steps.count - 1, 0)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pick for me")
                .font(.largeTitle.bold())

            if results.isEmpty {
                Text("Answer each question. Use no preference when you do not care.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Recommendation \(resultIndex + 1) of \(results.count)")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var questionContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            progressView

            Text(currentStep.title)
                .font(.title2.bold())
                .frame(maxWidth: .infinity, alignment: .leading)

            if let subtitle = currentStep.subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            answerOptions

            if let errorText {
                StatusBubble(title: "Choose an answer", text: errorText)
            }

            HStack(spacing: 10) {
                Button {
                    goBack()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.headline.bold())
                        .frame(width: 104)
                        .frame(height: 52)
                        .contentShape(Rectangle())
                        .liquidGlass(cornerRadius: 26)
                }
                .buttonStyle(.plain)
                .disabled(isLoading || step == 0)
                .opacity(step == 0 ? 0.45 : 1)

                Button {
                    advance()
                } label: {
                    Label(step == steps.count - 1 ? "Check Results" : "Next", systemImage: step == steps.count - 1 ? "sparkles" : "chevron.right")
                    .font(.headline.bold())
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .contentShape(Rectangle())
                    .liquidGlass(cornerRadius: 26)
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
                .opacity(isLoading ? 0.55 : 1)
            }

            if isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Finding a good fit...")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var progressView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(step + 1) / \(steps.count)")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.12))
                    Capsule()
                        .fill(model.settings.accentColor)
                        .frame(width: proxy.size.width * CGFloat(step + 1) / CGFloat(steps.count))
                }
            }
            .frame(height: 7)
        }
    }

    @ViewBuilder private var answerOptions: some View {
        switch currentStep {
        case .format:
            mediaFormatChoiceList(selection: $answers.mediaFormat)
        case .archetype:
            primaryArchetypeChoiceList(selection: $answers.archetypes)
        case .secondaryArchetypes:
            multiChoiceList(secondaryArchetypeOptions, selection: $answers.secondaryArchetypes)
        case .genrePreferences:
            multiChoiceList(PickForMeGenrePreference.allCases, selection: $answers.genrePreferences)
        case .seriousness:
            singleChoiceList(PickForMeSeriousness.allCases, selection: $answers.seriousness)
        case .realism:
            singleChoiceList(PickForMeRealism.allCases, selection: $answers.realism)
        case .sourceMaterial:
            singleChoiceList(PickForMeSourceMaterial.allCases, selection: $answers.sourceMaterial)
        case .action:
            multiChoiceList(PickForMeActionLevel.allCases, selection: $answers.actionLevels)
        case .engagement:
            singleChoiceList(PickForMeEngagement.allCases, selection: $answers.engagement)
        case .recommendationType:
            singleChoiceList(PickForMeRecommendationType.allCases, selection: $answers.recommendationType)
        case .runtime:
            singleChoiceList(PickForMeRuntime.allCases, selection: $answers.runtime)
        case .releaseAge:
            singleChoiceList(PickForMeReleaseAge.allCases, selection: $answers.releaseAge)
        case .ageRating:
            multiChoiceList(PickForMeContentRating.allCases, selection: $answers.contentRatings)
        case .gore:
            singleChoiceList(PickForMeGoreLevel.allCases, selection: $answers.goreLevel)
        case .sex:
            singleChoiceList(PickForMeSexLevel.allCases, selection: $answers.sexLevel)
        case .minimumRating:
            singleChoiceList(PickForMeMinimumRating.allCases, selection: $answers.minimumRating)
        case .dealBreakers:
            multiChoiceList(dealBreakerOptions, selection: $answers.dealBreakers)
        }
    }

    private var resultContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            let item = results[resultIndex]

            if let fallbackText {
                StatusBubble(title: "Not enough data to decide", text: fallbackText)
            }

            HStack(alignment: .top, spacing: 18) {
                Button {
                    model.selectedItem = item
                } label: {
                    PosterView(item: item, width: 164, height: 238, isFavourite: model.library.isFavourite(item))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 10) {
                    Text(item.title)
                        .font(.title2.bold())
                        .lineLimit(3)

                    Text(resultMetadataText(for: item))
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    Text(item.overview.isEmpty ? "No overview is available for this title." : item.overview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(8)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            HStack(spacing: 10) {
                Button {
                    model.selectedItem = item
                } label: {
                    Label("Details", systemImage: "info.circle")
                        .font(.headline.bold())
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .liquidGlass(cornerRadius: 24)
                }
                .buttonStyle(.plain)

                Button {
                    model.toggleWatchlist(item)
                } label: {
                    Image(systemName: model.library.isInWatchlist(item.key) ? "bookmark.fill" : "bookmark")
                        .font(.headline.bold())
                        .frame(width: 54, height: 48)
                        .liquidGlass(cornerRadius: 24)
                }
                .buttonStyle(.plain)

                Button {
                    model.toggleWatched(item)
                } label: {
                    Image(systemName: model.library.isWatched(item.key) ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(.headline.bold())
                        .frame(width: 54, height: 48)
                        .liquidGlass(cornerRadius: 24)
                }
                .buttonStyle(.plain)
                .disabled(item.isUpcoming)
                .opacity(item.isUpcoming ? 0.45 : 1)
            }

            Button(role: model.library.isNeverShowAgain(item.key) ? nil : .destructive) {
                toggleNeverShowAgainForCurrentResult(item)
            } label: {
                Label(
                    model.library.isNeverShowAgain(item.key) ? "Show in recommendations again" : "Never show this again",
                    systemImage: model.library.isNeverShowAgain(item.key) ? "eye" : "eye.slash"
                )
                .font(.headline.bold())
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .liquidGlass(cornerRadius: 24)
            }
            .buttonStyle(.plain)

            Button {
                editAnswers()
            } label: {
                Label("Edit answers and regenerate", systemImage: "slider.horizontal.3")
                    .font(.headline.bold())
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .liquidGlass(cornerRadius: 24)
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                Button {
                    showPreviousResult()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.headline.bold())
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .liquidGlass(cornerRadius: 24)
                }
                .buttonStyle(.plain)
                .disabled(resultIndex == 0)
                .opacity(resultIndex == 0 ? 0.45 : 1)

                Button {
                    showNextResult()
                } label: {
                    Label(resultIndex == results.count - 1 ? "Retake" : "Next", systemImage: resultIndex == results.count - 1 ? "arrow.counterclockwise" : "chevron.right")
                        .font(.headline.bold())
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .liquidGlass(cornerRadius: 24)
                }
                .buttonStyle(.plain)
            }
        }
        .task(id: results[resultIndex].key) {
            await model.loadDetail(results[resultIndex])
        }
    }

    private var currentStep: PickForMeStep {
        steps[min(step, max(steps.count - 1, 0))]
    }

    private var secondaryArchetypeOptions: [PickForMeArchetype] {
        PickForMeArchetype.allCases.filter { option in
            option != .surprise && (option == .noPreference || !answers.archetypes.contains(option))
        }
    }

    private var dealBreakerOptions: [PickForMeDealBreaker] {
        PickForMeDealBreaker.allCases.filter { option in
            switch option {
            case .documentary:
                return !answers.wantsDocumentary
            case .war:
                return !answers.wantsWar
            default:
                return true
            }
        }
    }

    private var hasEnoughDataForSurprise: Bool {
        model.library.watchedItems.count >= 3
    }

    private func scrollToTop(with proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo("pickForMeTop", anchor: .top)
            }
        }
    }

    private func formatChoiceList(selection: Binding<MediaFilter?>) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                PickForMeOptionButton(title: MediaFilter.movie.title, subtitle: nil, isSelected: selection.wrappedValue == .movie) {
                    selection.wrappedValue = selection.wrappedValue == .movie ? nil : .movie
                    pruneAgeRatingsForCurrentFormat()
                    errorText = nil
                }

                PickForMeOptionButton(title: MediaFilter.tv.title, subtitle: nil, isSelected: selection.wrappedValue == .tv) {
                    selection.wrappedValue = selection.wrappedValue == .tv ? nil : .tv
                    pruneAgeRatingsForCurrentFormat()
                    errorText = nil
                }
            }

            PickForMeOptionButton(title: MediaFilter.both.title, subtitle: nil, isSelected: selection.wrappedValue == .both) {
                selection.wrappedValue = selection.wrappedValue == .both ? nil : .both
                pruneAgeRatingsForCurrentFormat()
                errorText = nil
            }
        }
    }

    private func singleChoiceList<Option: PickForMeOption>(_ options: [Option], selection: Binding<Option?>) -> some View {
        VStack(spacing: 10) {
            ForEach(options) { option in
                PickForMeOptionButton(title: option.title, subtitle: option.subtitle, isSelected: selection.wrappedValue == option) {
                    selection.wrappedValue = selection.wrappedValue == option ? nil : option
                    errorText = nil
                }
            }
        }
    }

    private func mediaFormatChoiceList(selection: Binding<PickForMeMediaFormat?>) -> some View {
        VStack(spacing: 10) {
            ForEach(PickForMeMediaFormat.allCases.filter { $0 != .both }) { option in
                PickForMeOptionButton(title: option.title, subtitle: option.subtitle, isSelected: selection.wrappedValue == option) {
                    selection.wrappedValue = option
                    errorText = nil
                }
            }
        }
    }

    private func primaryArchetypeChoiceList(selection: Binding<Set<PickForMeArchetype>>) -> some View {
        VStack(spacing: 10) {
            ForEach(PickForMeArchetype.allCases.filter { option in
                option != .noPreference && (option != .surprise || hasEnoughDataForSurprise)
            }) { option in
                PickForMeOptionButton(title: option.title, subtitle: option.subtitle, isSelected: selection.wrappedValue.contains(option)) {
                    selection.wrappedValue = [option]
                    answers.secondaryArchetypes.remove(option)
                    errorText = nil
                }
            }
        }
    }

    private func multiChoiceList<Option: PickForMeOption>(_ options: [Option], selection: Binding<Set<Option>>) -> some View {
        VStack(spacing: 10) {
            ForEach(options) { option in
                PickForMeOptionButton(title: option.title, subtitle: option.subtitle, isSelected: selection.wrappedValue.contains(option)) {
                    if option.isAnyOption {
                        selection.wrappedValue = [option]
                    } else {
                        selection.wrappedValue = selection.wrappedValue.filter { !$0.isAnyOption }
                        if selection.wrappedValue.contains(option) {
                            selection.wrappedValue.remove(option)
                        } else {
                            selection.wrappedValue.insert(option)
                        }
                    }

                    errorText = nil
                }
            }
        }
    }

    private func cappedMultiChoiceList<Option: PickForMeOption>(_ options: [Option], selection: Binding<Set<Option>>, maximumSelectionCount: Int) -> some View {
        VStack(spacing: 10) {
            ForEach(options) { option in
                PickForMeOptionButton(title: option.title, subtitle: option.subtitle, isSelected: selection.wrappedValue.contains(option)) {
                    if option.isAnyOption {
                        selection.wrappedValue = [option]
                    } else {
                        selection.wrappedValue = selection.wrappedValue.filter { !$0.isAnyOption }
                        if selection.wrappedValue.contains(option) {
                            selection.wrappedValue.remove(option)
                        } else if selection.wrappedValue.count < maximumSelectionCount {
                            selection.wrappedValue.insert(option)
                        } else {
                            errorText = "Choose up to \(maximumSelectionCount) options."
                            return
                        }
                    }

                    errorText = nil
                }
            }
        }
    }

    private func advance() {
        guard !isLoading else { return }
        guard currentStepIsAnswered else {
            errorText = "Please choose an answer before continuing."
            return
        }

        if step < steps.count - 1 {
            step += 1
        } else {
            Task { await loadResults() }
        }
    }

    private func clearCurrentAnswer() {
        switch currentStep {
        case .format:
            answers.mediaFormat = nil
        case .archetype:
            answers.archetypes = []
            answers.secondaryArchetypes = []
        case .secondaryArchetypes:
            answers.secondaryArchetypes = []
        case .genrePreferences:
            answers.genrePreferences = []
        case .seriousness:
            answers.seriousness = nil
        case .realism:
            answers.realism = nil
        case .sourceMaterial:
            answers.sourceMaterial = nil
        case .action:
            answers.actionLevels = []
        case .engagement:
            answers.engagement = nil
        case .recommendationType:
            answers.recommendationType = nil
        case .runtime:
            answers.runtime = nil
        case .releaseAge:
            answers.releaseAge = nil
        case .ageRating:
            answers.contentRatings = []
            answers.goreLevel = nil
            answers.sexLevel = nil
        case .gore:
            answers.goreLevel = nil
        case .sex:
            answers.sexLevel = nil
        case .minimumRating:
            answers.minimumRating = nil
        case .dealBreakers:
            answers.dealBreakers = []
        }

        errorText = nil
    }

    private func pruneAgeRatingsForCurrentFormat() {
    }

    private func goBack() {
        if !results.isEmpty {
            results = []
            resultIndex = 0
            step = steps.count - 1
        } else if step > 0 {
            step -= 1
        } else {
            dismiss()
        }
    }

    private func loadResults() async {
        isLoading = true
        errorText = nil
        let shouldUseFallback = answers.meaningfulQuestionCount == 0
        fallbackText = shouldUseFallback ? "Here are some popular movies and shows instead." : nil
        let queryAnswers = shouldUseFallback ? PickForMeAnswers(mediaFormat: answers.mediaFormat) : answers
        let picked = await model.pickForMeRecommendations(for: queryAnswers)
        isLoading = false

        if picked.isEmpty {
            errorText = "Please repeat the quiz and try different answer combinations."
        } else {
            results = picked
            resultIndex = 0
        }
    }

    private func resultMetadataText(for item: MediaItem) -> String {
        var parts = [item.displayKindLabel, item.releaseDateReadable]

        if let ageRating = model.detailsCache[item.key]?.ageRating,
           !ageRating.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(ageRating)
        }

        parts.append(model.ratingDisplayText(for: item))
        return parts.joined(separator: " • ")
    }

    private func showPreviousResult() {
        guard resultIndex > 0 else { return }
        resultIndex -= 1
    }

    private func showNextResult() {
        if resultIndex < results.count - 1 {
            resultIndex += 1
        } else {
            results = []
            resultIndex = 0
            step = 0
        }
    }

    private func toggleNeverShowAgainForCurrentResult(_ item: MediaItem) {
        let willHide = !model.library.isNeverShowAgain(item.key)
        model.toggleNeverShowAgain(item)

        guard willHide else { return }
        results.removeAll { $0.key == item.key }

        if results.isEmpty {
            editAnswers()
        } else {
            resultIndex = min(resultIndex, results.count - 1)
        }
    }

    private func editAnswers() {
        results = []
        resultIndex = 0
        fallbackText = nil
        step = 0
        errorText = nil
    }

    private var currentStepIsAnswered: Bool {
        switch currentStep {
        case .format:
            return answers.mediaFormat != nil
        case .archetype:
            return !answers.archetypes.isEmpty
        case .secondaryArchetypes:
            return !answers.secondaryArchetypes.isEmpty
        case .genrePreferences:
            return !answers.genrePreferences.isEmpty
        case .seriousness:
            return answers.seriousness != nil
        case .realism:
            return answers.realism != nil
        case .sourceMaterial:
            return answers.sourceMaterial != nil
        case .action:
            return !answers.actionLevels.isEmpty
        case .engagement:
            return answers.engagement != nil
        case .recommendationType:
            return answers.recommendationType != nil
        case .runtime:
            return answers.runtime != nil
        case .releaseAge:
            return answers.releaseAge != nil
        case .ageRating:
            return !answers.contentRatings.isEmpty
        case .gore:
            return answers.goreLevel != nil
        case .sex:
            return answers.sexLevel != nil
        case .minimumRating:
            return answers.minimumRating != nil
        case .dealBreakers:
            return !answers.dealBreakers.isEmpty
        }
    }
}

private struct PickForMeOptionButton: View {
    let title: String
    let subtitle: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.subheadline.bold())
                        .lineLimit(2)

                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.headline.bold())
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .liquidGlass(cornerRadius: 28)
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(.primary.opacity(isSelected ? 0.45 : 0), lineWidth: 1.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

    // MARK: - Watchlist

    private struct WatchlistView: View {
        @ObservedObject var model: VestigoModel

        var sortedItems: [MediaItem] {
            model.library.watchlistItems.sorted(
                using: model.sortOption,
                ratings: model.library.ratings,
                externalRatings: model.externalRatingsCache,
                ratingSource: model.settings.preferredRatingSource
            )
        }

        var unwatchedItems: [MediaItem] {
            sortedItems.filter { !model.library.isWatched($0.key) }
        }

        var watchedItems: [MediaItem] {
            sortedItems.filter { model.library.isWatched($0.key) }
        }

        var body: some View {
            BaseScreen(title: "Watchlist", filter: .constant(.both), settings: model.settings, onRefresh: {
                await model.loadExternalRatings(for: model.library.watchlistItems, limit: 120)
            }) {
                VStack(alignment: .leading, spacing: 14) {
                    SortPicker(sort: $model.sortOption, includeMyRating: true, ratingSource: model.settings.preferredRatingSource)
                    
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
        
        private var visibleCollections: [(collection: MediaCollection, items: [MediaItem])] {
            model.library.collections.compactMap { collection in
                let items = visibleItems(in: collection)
                return items.isEmpty ? nil : (collection, items)
            }
        }

        private var collectionIconItemsByID: [UUID: MediaItem] {
            Self.collectionIconItemsByID(for: visibleCollections, library: model.library)
        }

        private func visibleItems(in collection: MediaCollection) -> [MediaItem] {
            collection.itemKeys
                .compactMap { model.library.items[$0] }
                .filter { $0.shouldShowInDiscovery }
        }

        private static func collectionIconItemsByID(for collections: [(collection: MediaCollection, items: [MediaItem])], library: UserLibrary) -> [UUID: MediaItem] {
            let sortedCollections = collections.sorted { lhs, rhs in
                if lhs.items.count != rhs.items.count {
                    return lhs.items.count < rhs.items.count
                }
                return lhs.collection.name.localizedCaseInsensitiveCompare(rhs.collection.name) == .orderedAscending
            }

            var result: [UUID: MediaItem] = [:]
            var usedKeys = Set<MediaKey>()

            func sortedCandidates(for entry: (collection: MediaCollection, items: [MediaItem])) -> [MediaItem] {
                entry.items.sorted { lhs, rhs in
                    lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
            }

            for entry in sortedCollections where entry.items.count == 1 {
                guard let item = sortedCandidates(for: entry).first else { continue }
                result[entry.collection.id] = item
                usedKeys.insert(item.key)
            }

            for entry in sortedCollections where entry.items.count > 1 {
                let candidates = sortedCandidates(for: entry)
                guard !candidates.isEmpty else { continue }

                let unusedCandidates = candidates.filter { !usedKeys.contains($0.key) }
                let usableCandidates = unusedCandidates.isEmpty ? candidates : unusedCandidates
                let iconIndex = entry.collection.name.unicodeScalars.map { Int($0.value) }.reduce(0, +) % usableCandidates.count
                let item = usableCandidates[iconIndex]

                result[entry.collection.id] = item
                usedKeys.insert(item.key)
            }

            return result
        }

        private static func collectionRowIdentity(for collection: MediaCollection, iconItem: MediaItem?) -> String {
            let itemSignature = collection.itemKeys
                .map(\.stableID)
                .sorted()
                .joined(separator: "|")
            let iconSignature = iconItem?.key.stableID ?? "folder"
            return "\(collection.id.uuidString)-\(iconSignature)-\(itemSignature)"
        }
        
        var body: some View {
            NavigationStack(path: $collectionPath) {
                BaseScreen(title: "Collections", filter: .constant(.both), settings: model.settings, onRefresh: {
                    for collection in model.library.collections {
                        await model.loadCollectionRecommendations(for: collection.id)
                    }
                }) {
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
                            FavouritesCollectionView(model: model)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "star")
                                    .font(.system(size: 18, weight: .bold))
                                    .frame(width: 26)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Favourites")
                                        .font(.headline.bold())
                                        .foregroundStyle(.primary)

                                    Text(model.library.favouriteKeys.count == 1 ? "1 favourite title" : "\(model.library.favouriteKeys.count) favourite titles")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.title3.bold())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(14)
                            .liquidGlass(cornerRadius: 22)
                            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        
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

                        ForEach(visibleCollections, id: \.collection.id) { entry in
                            let collection = entry.collection
                            let iconItem = collectionIconItemsByID[collection.id]
                            Button {
                                collectionPath.append(collection.id)
                            } label: {
                                CollectionRow(
                                    collection: collection,
                                    count: entry.items.count,
                                    iconItem: iconItem
                                )
                                .id(Self.collectionRowIdentity(for: collection, iconItem: iconItem))
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
    
    private struct FavouritesCollectionView: View {
        @ObservedObject var model: VestigoModel
        @State private var filter: MediaFilter = .both
        
        private var visibleItems: [MediaItem] {
            model.library.favouriteItems(for: filter)
        }
        
        var body: some View {
            BaseScreen(title: "Favourites", filter: $filter, settings: model.settings, onRefresh: {
                await model.loadExternalRatings(for: visibleItems, limit: 120)
            }) {
                VStack(alignment: .leading, spacing: 14) {
                    FilterPills(filter: $filter, options: [.movie, .tv, .both]) { }
                    
                    if visibleItems.isEmpty {
                        StatusBubble(title: "No favourites yet", text: "Movies and series you mark as favourites will appear here.")
                    } else {
                        MediaGridOrList(items: visibleItems, hideWatchedForUpcoming: false, model: model)
                    }
                }
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
        nonisolated static let baseURL = URL(string: "https://mtttuyvpjyugudkevchj.supabase.co/functions/v1/vestigo-api")!
    }

    private struct ExternalRatings: Codable, Hashable {
        let imdbID: String?
        let imdbRating: Double?
        let imdbVotes: String?
        let rottenTomatoesRating: Int?
        let rottenTomatoesText: String?

        static let empty = ExternalRatings(
            imdbID: nil,
            imdbRating: nil,
            imdbVotes: nil,
            rottenTomatoesRating: nil,
            rottenTomatoesText: nil
        )

        init(
            imdbID: String?,
            imdbRating: Double?,
            imdbVotes: String?,
            rottenTomatoesRating: Int?,
            rottenTomatoesText: String?
        ) {
            self.imdbID = imdbID
            self.imdbRating = imdbRating
            self.imdbVotes = imdbVotes
            self.rottenTomatoesRating = rottenTomatoesRating
            self.rottenTomatoesText = rottenTomatoesText
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: RatingsCodingKey.self)
            imdbID = Self.decodeString(from: container, keys: ["imdbID", "imdbId", "imdb_id", "imdbid"])
            imdbRating = Self.decodeDouble(from: container, keys: ["imdbRating", "imdb_rating", "imdb", "imdbScore", "imdb_score"])
            imdbVotes = Self.decodeString(from: container, keys: ["imdbVotes", "imdb_votes", "imdbVoteCount", "imdb_vote_count"])
            rottenTomatoesRating = Self.decodeInt(from: container, keys: ["rottenTomatoesRating", "rotten_tomatoes_rating", "tomatometer", "rtRating", "rt_rating"])
            rottenTomatoesText = Self.decodeString(from: container, keys: ["rottenTomatoesText", "rotten_tomatoes_text", "rottenTomatoes", "rotten_tomatoes", "rtText", "rt_text"])
        }

        var hasAnyRating: Bool {
            imdbRating != nil || rottenTomatoesRating != nil || rottenTomatoesText != nil
        }

        var rottenTomatoesDisplayText: String? {
            if let rottenTomatoesText, !rottenTomatoesText.isEmpty {
                return "Rotten Tomatoes: \(rottenTomatoesText)"
            }

            if let rottenTomatoesRating {
                return "Rotten Tomatoes: \(rottenTomatoesRating)%"
            }

            return nil
        }

        private struct RatingsCodingKey: CodingKey {
            let stringValue: String
            let intValue: Int? = nil

            init?(stringValue: String) {
                self.stringValue = stringValue
            }

            init?(intValue: Int) {
                return nil
            }
        }

        private static func decodeString(from container: KeyedDecodingContainer<RatingsCodingKey>, keys: [String]) -> String? {
            for key in keys {
                guard let codingKey = RatingsCodingKey(stringValue: key) else { continue }
                if let value = try? container.decode(String.self, forKey: codingKey), !value.isEmpty, value != "N/A" {
                    return value
                }
                if let value = try? container.decode(Double.self, forKey: codingKey) {
                    return value.formatted(.number.precision(.fractionLength(1)))
                }
                if let value = try? container.decode(Int.self, forKey: codingKey) {
                    return String(value)
                }
            }

            return nil
        }

        private static func decodeDouble(from container: KeyedDecodingContainer<RatingsCodingKey>, keys: [String]) -> Double? {
            for key in keys {
                guard let codingKey = RatingsCodingKey(stringValue: key) else { continue }
                if let value = try? container.decode(Double.self, forKey: codingKey) {
                    return value
                }
                if let value = try? container.decode(Int.self, forKey: codingKey) {
                    return Double(value)
                }
                if let text = try? container.decode(String.self, forKey: codingKey) {
                    let cleaned = text.replacingOccurrences(of: "/10", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if let value = Double(cleaned), value > 0 {
                        return value
                    }
                }
            }

            return nil
        }

        private static func decodeInt(from container: KeyedDecodingContainer<RatingsCodingKey>, keys: [String]) -> Int? {
            for key in keys {
                guard let codingKey = RatingsCodingKey(stringValue: key) else { continue }
                if let value = try? container.decode(Int.self, forKey: codingKey) {
                    return value
                }
                if let value = try? container.decode(Double.self, forKey: codingKey) {
                    return Int(value.rounded())
                }
                if let text = try? container.decode(String.self, forKey: codingKey) {
                    let cleaned = text.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if let value = Int(cleaned) {
                        return value
                    }
                }
            }

            return nil
        }
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

        nonisolated var mediaItem: MediaItem {
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

        func ratings(for item: MediaItem) async throws -> ExternalRatings? {
            guard item.kind == .movie || item.kind == .tv else { return nil }

            let releaseYear = item.releaseDate.flatMap { releaseDate -> String? in
                guard releaseDate.count >= 4 else { return nil }
                return String(releaseDate.prefix(4))
            }

            var components = URLComponents(url: baseURL.appending(path: "ratings"), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "tmdbID", value: String(item.id)),
                URLQueryItem(name: "kind", value: item.kind.rawValue),
                URLQueryItem(name: "title", value: item.title),
                URLQueryItem(name: "year", value: releaseYear)
            ]

            guard let url = components.url else { return nil }
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse else { return nil }

            guard (200...299).contains(httpResponse.statusCode) else {
                return nil
            }

            let decoded = try JSONDecoder().decode(BackendRatingsResponse.self, from: data)
            return decoded.ratings
        }

        static func normalizedTitle(_ value: String) -> String {
            value
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .lowercased()
                .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private struct BackendFranchiseMembershipResponse: nonisolated Decodable {
        let ok: Bool
        let franchise: TVDBFranchiseList?
    }
    
    private struct BackendFranchiseRecommendationsResponse: nonisolated Decodable {
        let ok: Bool
        let results: [BackendMediaItemDTO]
    }

    private struct BackendTMDbCollectionResponse: nonisolated Decodable {
        let ok: Bool
        let collection: BackendTMDbCollectionDTO?
    }

    private struct BackendRatingsResponse: nonisolated Decodable {
        let ok: Bool
        let ratings: ExternalRatings?
    }

    private struct BackendTMDbCollectionDTO: nonisolated Decodable, Identifiable {
        let id: Int
        let name: String
        let overview: String?
        let items: [BackendMediaItemDTO]

        nonisolated var mediaItems: [MediaItem] {
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

        private var activeFranchiseSourceItems: [MediaItem] {
            (model.library.watchedItems + model.library.watchlistItems)
                .uniqued()
                .filter(\.shouldShowInDiscovery)
        }

        private var franchises: [FranchiseCollection] {
            let discoveredIDs = Set(tmdbCollectionFranchises.map(\.id))
            let seeded = FranchiseLibrary.defaultFranchises(
                matching: activeFranchiseSourceItems,
                tvdbLists: tvdbFranchises
            )
            .filter { !discoveredIDs.contains($0.id) }

            return (tmdbCollectionFranchises + seeded)
                .filter { visibleItemCount(for: $0) > 0 }
                .sorted { lhs, rhs in
                    lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
        }

        private var seriesFranchises: [FranchiseCollection] {
            tmdbCollectionFranchises
                .filter { visibleItemCount(for: $0) > 0 }
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
        
        private func visibleItemCount(for franchise: FranchiseCollection) -> Int {
            FranchiseLibrary.items(in: franchise, from: activeFranchiseSourceItems).count
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
            BaseScreen(title: screenMode.title, filter: .constant(.both), settings: model.settings, onRefresh: {
                await loadDiscoveredTMDbCollections()
            }) {
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
                                            count: visibleItemCount(for: franchise)
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
                                            count: visibleItemCount(for: franchise)
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
                                        count: visibleItemCount(for: franchise)
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
                                        count: visibleItemCount(for: franchise)
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
            let movieItems = (model.library.watchedItems + model.library.watchlistItems)
                .uniqued()
                .filter { $0.kind == .movie && $0.shouldShowInDiscovery }
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

            let discovered = collectionsByID.values.compactMap { collection -> FranchiseCollection? in
                let items = collection.mediaItems.filter(\.shouldShowInDiscovery)
                guard items.count >= 2 else { return nil }

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
                library: model.library,
                externalRatings: model.externalRatingsCache,
                ratingSource: model.settings.preferredRatingSource
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
                (franchiseItems + backendRecommendations).uniqued().filter(\.shouldShowInDiscovery),
                using: sort,
                library: model.library,
                externalRatings: model.externalRatingsCache,
                ratingSource: model.settings.preferredRatingSource
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
                (franchiseItems + backendRecommendations).uniqued().filter(\.shouldShowInDiscovery),
                using: sort,
                library: model.library,
                externalRatings: model.externalRatingsCache,
                ratingSource: model.settings.preferredRatingSource
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
            BaseScreen(title: franchise.title, filter: .constant(.both), settings: model.settings, onRefresh: {
                await loadBackendRecommendations()
                await model.loadExternalRatings(for: backendRecommendations, limit: 120)
            }) {
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

                    SortPicker(sort: $sort, includeMyRating: mode == .watched, ratingSource: model.settings.preferredRatingSource)
                        .onChange(of: mode) { _, newMode in
                            if newMode == .recommended && sort == .myRating {
                                sort = .tmdbRating
                            }
                        }

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
                let visibleResults = results.filter(\.shouldShowInDiscovery)
                await MainActor.run {
                    backendRecommendations = visibleResults
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

        static func sortedItems(_ items: [MediaItem], using sort: SortOption, library: UserLibrary, externalRatings: [MediaKey: ExternalRatings] = [:], ratingSource: RatingSource = .imdb) -> [MediaItem] {
            items.sorted { lhs, rhs in
                comesBefore(lhs, rhs, using: sort, library: library, externalRatings: externalRatings, ratingSource: ratingSource)
            }
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
            return collection.itemKeys.compactMap { model.library.items[$0] }.sorted(
                using: sort,
                ratings: model.library.ratings,
                externalRatings: model.externalRatingsCache,
                ratingSource: model.settings.preferredRatingSource
            )
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
                .sorted(
                    using: sort,
                    ratings: model.library.ratings,
                    externalRatings: model.externalRatingsCache,
                    ratingSource: model.settings.preferredRatingSource
                )
        }
        
        var body: some View {
            BaseScreen(title: collection?.name ?? "Collection", filter: .constant(.both), settings: model.settings, onRefresh: {
                await model.loadCollectionRecommendations(for: collectionID)
                await model.loadExternalRatings(for: items + recommendedItems, limit: 120)
            }) {
                VStack(spacing: 14) {
                    SortPicker(sort: $sort, includeMyRating: mode != .recommended, ratingSource: model.settings.preferredRatingSource)
                        .onChange(of: mode) { _, newMode in
                            if newMode == .recommended && sort == .myRating {
                                sort = .tmdbRating
                            }
                        }
                    
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
    
    private struct SettingsView: View {
        @ObservedObject var model: VestigoModel
        @State private var clearPresses = 0
        @State private var showClearConfirm = false
        @State private var importText = ""
        @State private var importNotFound: [String] = []
        @State private var showImportNotFoundAlert = false
        @State private var pendingImportText: String?
        @State private var importWarningMessage = ""
        @State private var showImportWarningAlert = false
        @State private var showImportFilePicker = false
        @State private var isImporting = false
        @State private var pendingImportFormat: WatchedImportEntry.ImportFormat = .automatic
        @State private var selectedCategory: SettingsCategory = .content
        @State private var importPlaceholderIndex = 0

        private enum SettingsCategory: String, CaseIterable, Identifiable {
            case content
            case display
            case data

            var id: String { rawValue }
            var title: String {
                switch self {
                case .display: return "Display"
                case .content: return "Content"
                case .data: return "Data"
                }
            }
        }

        private var importPlaceholderText: String {
            let examples = [
                "Star Wars 5 f m\nRed Notice 4.5\nThe Flash 4 s",
                "Star Wars 5 f m, Red Notice 4.5, The Flash 4 s"
            ]
            return examples[importPlaceholderIndex % examples.count]
        }
        
        var body: some View {
            BaseScreen(title: "Settings", filter: .constant(.both), settings: model.settings, contentTopPadding: 18) {
                VStack(alignment: .leading, spacing: 18) {
                    settingsCategoryPills

                    if selectedCategory == .display {
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
                    }
                    
                    if selectedCategory == .content {
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
                            Text("Ratings source: IMDb")
                                .font(.headline.bold())

                            Text("IMDb scores come from OMDb and are used for rating displays, rating filters, and rating sorts when available. TMDb remains the catalog source for finding titles. Rotten Tomatoes is shown only on detail pages.")
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

                        VStack(alignment: .leading, spacing: 6) {
                            Toggle("Hide lowest age ratings", isOn: $model.settings.hideLowestAgeRatings)
                                .font(.headline.bold())
                                .tint(model.settings.accentColor)

                            Text("When this is on, Vestigo hides titles rated for the youngest audiences, including G, U, TV-Y, TV-Y7, and TV-G, where certification data is available.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .settingBubble()
                        .onChange(of: model.settings.hideLowestAgeRatings) { _, _ in
                            model.searchResults = model.preparedResults(model.searchResults)
                            model.updateSearch()
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
                        
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 10) {
                                Toggle("Search", isOn: $model.settings.hideUpcomingFromSearch)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.primary)
                                    .tint(model.settings.accentColor)
                                    .padding(.trailing, 6)

                                Toggle("For You / Recommended", isOn: $model.settings.hideUpcomingFromRecommended)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.primary)
                                    .tint(model.settings.accentColor)
                                    .padding(.trailing, 6)

                                Toggle("Collection and franchise recommendations", isOn: $model.settings.hideUpcomingFromCollectionRecommendations)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.primary)
                                    .tint(model.settings.accentColor)
                                    .padding(.trailing, 6)
                            }
                            .padding(.top, 8)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Hide upcoming releases")
                                    .font(.headline.bold())
                                    .foregroundStyle(.primary)

                                Text("Choose where unreleased titles should be hidden. Home does not have a toggle because Upcoming releases is its own carousel.")
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
                            
                            Text("Choose whether category pages open sorted by IMDb rating or release date.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .settingBubble()
                        
                    }
                    }
                    
                    if selectedCategory == .data {
                    Text("Data")
                        .sectionTitle()
                        .padding(.top, 6)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Import watched titles as title, star rating, optional f for favourite, and m for movie or s for series. .txt can use one item per line or commas; .csv uses commas only.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            
                            TextField(importPlaceholderText, text: $importText, axis: .vertical)
                                .lineLimit(3...5)
                                .textFieldStyle(.plain)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .liquidGlass(cornerRadius: 18)
                            
                            Button {
                                importWatchedData(importText)
                            } label: {
                                HStack(alignment: .center, spacing: 10) {
                                    Image(systemName: "tray.and.arrow.down")
                                        .font(.system(size: 17, weight: .semibold))
                                        .frame(width: 24, height: 22, alignment: .center)
                                    
                                    Text(isImporting ? "Importing..." : "Import pasted data")
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
                            .disabled(isImporting || importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            Button {
                                showImportFilePicker = true
                            } label: {
                                HStack(alignment: .center, spacing: 10) {
                                    Image(systemName: "doc.badge.plus")
                                        .font(.system(size: 17, weight: .semibold))
                                        .frame(width: 24, height: 22, alignment: .center)

                                    Text("Import .txt or .csv file")
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
                            .disabled(isImporting)
                        }
                        .padding(10)
                        .liquidGlass(cornerRadius: 22)
                        
                        HStack(spacing: 10) {
                            ForEach(ExportFormat.allCases) { format in
                                Button {
                                    model.prepareExport(format: format)
                                } label: {
                                    HStack(alignment: .center, spacing: 8) {
                                        Image(systemName: "square.and.arrow.up")
                                            .font(.system(size: 17, weight: .semibold))
                                            .frame(width: 22, height: 22, alignment: .center)

                                        Text("Export \(format.title)")
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
                            }
                        }
                        .fileExporter(isPresented: $model.showExporter, document: model.exportDocument, contentType: model.exportFormat.contentType, defaultFilename: model.exportFormat.filename) { _ in }
                        
                        Button("Reset settings") {
                            model.settings = AppSettings()
                            model.searchFilter = model.settings.defaultSearchFilter
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
            }
            .onChange(of: model.settings) { _, _ in Storage.save(model.settings, key: "Vestigo.settings") }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    guard !Task.isCancelled else { return }
                    importPlaceholderIndex = (importPlaceholderIndex + 1) % 2
                }
            }
            .alert("Delete all Vestigo data?", isPresented: $showClearConfirm) {
                Button("Cancel", role: .cancel) { clearPresses = 0 }
                Button("Delete", role: .destructive) {
                    model.clearAllData()
                    clearPresses = 0
                }
            } message: {
                Text("This removes watched items, ratings, watchlist, collections, episode progress, and settings from local storage.")
            }
            .alert("The following items were not found", isPresented: $showImportNotFoundAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(importNotFound.joined(separator: "\n"))
            }
            .alert("Double-check import formatting", isPresented: $showImportWarningAlert) {
                Button("Cancel", role: .cancel) {
                    pendingImportText = nil
                }
                Button("Continue") {
                    if let pendingImportText {
                        let textToImport = pendingImportText
                        let formatToImport = pendingImportFormat
                        self.pendingImportText = nil
                        importWatchedData(textToImport, format: formatToImport, skipsWarnings: true)
                    }
                }
            } message: {
                Text(importWarningMessage)
            }
            .fileImporter(isPresented: $showImportFilePicker, allowedContentTypes: [.plainText, .commaSeparatedText], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    importWatchedFile(url)
                case .failure:
                    break
                }
            }
        }

        private var settingsCategoryPills: some View {
            Picker("Settings category", selection: $selectedCategory) {
                ForEach(SettingsCategory.allCases) { category in
                    Text(category.title).tag(category)
                }
            }
            .pickerStyle(.segmented)
            .liquidGlass(cornerRadius: 18)
        }

        private func importWatchedData(_ text: String, format: WatchedImportEntry.ImportFormat = .automatic, skipsWarnings: Bool = false) {
            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedText.isEmpty else { return }

            let report = WatchedImportEntry.report(for: trimmedText, format: format)
            if !skipsWarnings, let warningMessage = WatchedImportEntry.warningMessage(for: report) {
                pendingImportText = trimmedText
                pendingImportFormat = format
                importWarningMessage = warningMessage
                showImportWarningAlert = true
                return
            }

            isImporting = true
            Task {
                let notFound = await model.importWatchedText(trimmedText, format: format)
                await MainActor.run {
                    importNotFound = notFound
                    showImportNotFoundAlert = !notFound.isEmpty
                    isImporting = false
                }
            }
        }

        private func importWatchedFile(_ url: URL) {
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
            importText = text
            let fileExtension = url.pathExtension.lowercased()
            let format: WatchedImportEntry.ImportFormat = fileExtension == "csv" ? .commaSeparated : .automatic
            importWatchedData(text, format: format)
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
        var suppressedItemKey: MediaKey?
        
        func body(content: Content) -> some View {
            ZStack {
                content
                
                if let item = model.pendingRatingPromptItem, item.key != suppressedItemKey {
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
        func ratingPromptOverlay(model: VestigoModel, suppressedItemKey: MediaKey? = nil) -> some View {
            modifier(RatingPromptOverlay(model: model, suppressedItemKey: suppressedItemKey))
        }
    }
    
    
    // MARK: - Detail
    
    private struct DetailView: View {
        let item: MediaItem
        @ObservedObject var model: VestigoModel
        var allowsPersonSheet: Bool = true
        @Environment(\.imageRefreshToken) private var imageRefreshToken
        @State private var showCast = false
        @State private var showCollections = false
        @State private var selectedNestedItem: MediaItem?
        @State private var isPosterPreviewPresented = false
        
        private var detail: MediaDetail? { model.detailsCache[item.key] }
        private var providers: [StreamingOption] { model.providerCache[item.key] ?? [] }
        private var externalRatings: ExternalRatings? { model.externalRatingsCache[item.key] }
        
        private var selectedPersonBinding: Binding<PersonSummary?> {
            Binding(
                get: { allowsPersonSheet ? model.selectedPerson : nil },
                set: { model.selectedPerson = $0 }
            )
        }
        
        var body: some View {
            detailSheetSurface
                .overlay {
                    if isPosterPreviewPresented {
                        posterPreviewOverlay
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.18), value: isPosterPreviewPresented)
                .favouriteReplacementOverlay(model: model)
                .ratingPromptOverlay(model: model, suppressedItemKey: item.key)
                .presentationBackground(.clear)
                .presentationCornerRadius(54)
                .task { await model.loadDetail(item) }
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
                Button {
                    isPosterPreviewPresented = true
                } label: {
                    PosterView(item: item, width: 126, height: 188, isFavourite: model.library.isFavourite(item))
                }
                .buttonStyle(.plain)
                .disabled(item.posterURL == nil)
                .accessibilityLabel("Open poster")
                
                VStack(alignment: .leading, spacing: 10) {
                    titleText
                    metadataText
                    ageRatingText
                    rottenTomatoesText
                    dateText
                    primaryCrewText
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
        }

        private var posterPreviewOverlay: some View {
            GeometryReader { proxy in
                ZStack {
                    Color.black.opacity(0.72)
                        .ignoresSafeArea()
                        .onTapGesture {
                            isPosterPreviewPresented = false
                        }
                    
                    posterPreviewImage(maxSize: proxy.size)
                        .onTapGesture { }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }

        private func posterPreviewImage(maxSize: CGSize) -> some View {
            let width = min(maxSize.width * 0.86, maxSize.height * 0.82 * 2 / 3)
            let height = width * 1.5
            
            return AsyncImage(url: item.posterURL?.refreshedImageURL(token: imageRefreshToken)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                default:
                    ProgressView()
                        .tint(.white)
                }
            }
                .frame(width: width, height: height)
                .background(.black.opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.38), radius: 28, x: 0, y: 18)
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

        @ViewBuilder private var rottenTomatoesText: some View {
            if let rottenTomatoesText = externalRatings?.rottenTomatoesDisplayText {
                Text(rottenTomatoesText)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
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
                        title: "Watched",
                        systemName: model.library.isWatched(item.key) ? "checkmark.circle.fill" : "checkmark.circle"
                    ) {
                        model.toggleWatched(item, showsRatingPrompt: false)
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
            let yearText = item.kind == .tv ? (detail?.yearRangeText ?? item.releaseYearText) : item.releaseYearText
            var parts = [item.kind.displayLabel(runtime: detail?.runtime ?? item.runtime), yearText]
            
            if item.kind == .movie, let runtime = detail?.runtime, runtime > 0 {
                parts.append(formatRuntime(runtime))
            }
            
            if let originalLanguage = item.originalLanguage, !originalLanguage.isEmpty {
                parts.append("Original language: \(originalLanguage.uppercased())")
            }
            
            parts.append(model.ratingDisplayText(for: item))
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
        @State private var isBiographyExpanded = false
        
        private var credits: [MediaItem] {
            model.personCreditsCache[person.id] ?? []
        }
        
        private var sortedKnownForCredits: [MediaItem] {
            credits.sorted { lhs, rhs in
                switch knownForSort {
                case .rating:
                    let lhsRating = model.ratingSortValue(for: lhs)
                    let rhsRating = model.ratingSortValue(for: rhs)
                    if lhsRating != rhsRating {
                        return lhsRating > rhsRating
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
                    await model.loadExternalRatings(for: credits, limit: 80)
                }
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
            VStack(alignment: .leading, spacing: 7) {
                Text(person.name)
                    .font(.title2.bold())
                    .lineLimit(2)
                
                Text(person.role.isEmpty ? "Known for" : person.role)
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                
                if let detail = model.personDetails[person.id] {
                    if let metadata = detail.compactMetadataText {
                        Text(metadata)
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    
                    let biographyText = isBiographyExpanded ? detail.fullBiography : detail.detailBiography

                    if let biography = biographyText {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(biography)
                                .font(.caption)
                                .foregroundStyle(.primary.opacity(0.82))
                                .lineLimit(isBiographyExpanded ? nil : 3)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            if detail.fullBiography != nil {
                                Button(isBiographyExpanded ? "Show less" : "More") {
                                    withAnimation(.smooth(duration: 0.2)) {
                                        isBiographyExpanded.toggle()
                                    }
                                }
                                .font(.caption.bold())
                                .buttonStyle(.plain)
                                .foregroundStyle(model.settings.accentColor)
                            }
                        }
                        .padding(.top, 2)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
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
            .task(id: item.key) {
                await model.loadExternalRatings(item)
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
            "\(item.kind.label) • \(item.releaseDateReadable) • \(model.ratingDisplayText(for: item))"
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
        @Environment(\.imageRefreshToken) private var imageRefreshToken
        
        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(0.10))
                
                AsyncImage(url: url?.refreshedImageURL(token: imageRefreshToken)) { phase in
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
        }
    }
    
    // MARK: - Reusable Media UI
    
    private struct BaseScreen<Content: View>: View {
        let title: String
        @Binding var filter: MediaFilter
        let settings: AppSettings
        let headerAccessory: AnyView
        let contentTopPadding: CGFloat
        let onRefresh: (() async -> Void)?
        @ViewBuilder let content: Content
        @Environment(\.refreshImages) private var refreshImages
        
        init(
            title: String,
            filter: Binding<MediaFilter>,
            settings: AppSettings,
            headerAccessory: AnyView = AnyView(EmptyView()),
            contentTopPadding: CGFloat = 0,
            onRefresh: (() async -> Void)? = nil,
            @ViewBuilder content: () -> Content
        ) {
            self.title = title
            self._filter = filter
            self.settings = settings
            self.headerAccessory = headerAccessory
            self.contentTopPadding = contentTopPadding
            self.onRefresh = onRefresh
            self.content = content()
        }
        
        var body: some View {
            ZStack {
                AppBackground(settings: settings)
                    .ignoresSafeArea()
                
                scrollContent
            }
        }

        @ViewBuilder private var scrollContent: some View {
            if let onRefresh {
                baseScroll
                    .refreshable {
                        refreshImages()
                        await onRefresh()
                    }
            } else {
                baseScroll
            }
        }

        @ViewBuilder private var baseScroll: some View {
            let scroll = ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    if onRefresh != nil {
                        Color.clear
                            .frame(height: 1)
                    }

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
            .scrollBounceBehavior(onRefresh == nil ? .basedOnSize : .always, axes: .vertical)
            .scrollDismissesKeyboard(.immediately)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)

            if onRefresh == nil {
                scroll.scrollViewTouchTuning(axis: .vertical)
            } else {
                scroll
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

            Button(role: model.library.isNeverShowAgain(item.key) ? nil : .destructive) {
                model.toggleNeverShowAgain(item)
            } label: {
                Label(
                    model.library.isNeverShowAgain(item.key) ? "Show in recommendations again" : "Never show this again",
                    systemImage: model.library.isNeverShowAgain(item.key) ? "eye" : "eye.slash"
                )
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
                
                Text("\(item.releaseDateReadable) • \(model.ratingDisplayText(for: item))")
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
            .task(id: item.key) {
                await model.loadExternalRatings(item)
            }
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
        @Environment(\.imageRefreshToken) private var imageRefreshToken
        
        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: width * 0.18, style: .continuous)
                    .fill(item.genreGradient)
                AsyncImage(url: item.posterURL?.refreshedImageURL(token: imageRefreshToken)) { phase in
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
        @Environment(\.imageRefreshToken) private var imageRefreshToken
        
        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: width * 0.18, style: .continuous)
                    .fill(.white.opacity(0.12))
                
                AsyncImage(url: person.profileURL?.refreshedImageURL(token: imageRefreshToken)) { phase in
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
        @Environment(\.imageRefreshToken) private var imageRefreshToken
        
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
                    AsyncImage(url: url.refreshedImageURL(token: imageRefreshToken)) { phase in
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
    private enum SearchFilter: String, CaseIterable, Identifiable, Codable, Hashable {
        case all
        case movie
        case tv
        case people

        static var allCases: [SearchFilter] {
            [.movie, .tv, .all, .people]
        }

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "Both"
            case .movie: return "Movies"
            case .tv: return "Series"
            case .people: return "People"
            }
        }

        var mediaFilter: MediaFilter? {
            switch self {
            case .all: return .both
            case .movie: return .movie
            case .tv: return .tv
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
        var title: String { "IMDb \(rawValue)+" }
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
        let ratingSource: RatingSource
        
        var body: some View {
            Picker("Sort", selection: $sort) {
                Text("Released").tag(SortOption.releaseDate)
                
                if includeMyRating {
                    Text("My rating").tag(SortOption.myRating)
                }
                
                Text(ratingSource.title).tag(SortOption.tmdbRating)
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

            if let cachedImage = RemoteImageMemoryCache.shared.image(for: url) {
                setLoadedImage(cachedImage, for: url)
                return
            }
            
            do {
                let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20)
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
                RemoteImageMemoryCache.shared.setImage(image, for: url)
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
        let iconItem: MediaItem?
        
        private var collectionIcon: some View {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(0.10))

                if let iconItem {
                    PosterView(item: iconItem, width: 48, height: 48, isFavourite: false)
                        .id(iconItem.key.stableID)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    Image(systemName: collection.isDynamic ? "square.grid.2x2" : "folder")
                        .font(.title3.bold())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        
        var body: some View {
            HStack(spacing: 12) {
                collectionIcon
                
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
        private let base = "https://mtttuyvpjyugudkevchj.supabase.co/functions/v1/vestigo-api"
        
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

            if let keywordIDs = Self.specialCategoryKeywordIDs[genreID] {
                return try await discoverKeywordCategory(keywordIDs: keywordIDs, filter: filter, sort: sort)
            }

            async let discoveredItems = discoverCategoryItems(genreID: genreID, filter: filter)
            async let curatedItems = curatedCategoryItems(genreID: genreID, filter: filter)

            return try await (discoveredItems + curatedItems)
                .uniqued()
                .prefixArray(50)
        }

        private func discoverCategoryItems(genreID: Int, filter: MediaFilter) async throws -> [MediaItem] {
            switch filter {
            case .both:
                async let movies = discoverCategorySingleMedia(genreID: genreID, media: "movie")
                async let series = discoverCategorySingleMedia(genreID: genreID, media: "tv")
                return try await (movies + series)
                    .uniqued()
                    .prefixArray(50)
            case .movie:
                return try await discoverCategorySingleMedia(genreID: genreID, media: "movie")
            case .tv:
                return try await discoverCategorySingleMedia(genreID: genreID, media: "tv")
            }
        }

        private func discoverKeywordCategory(keywordIDs: [Int], filter: MediaFilter, sort: GenreSort) async throws -> [MediaItem] {
            switch filter {
            case .both:
                async let movies = discoverKeywordCategorySingleMedia(keywordIDs: keywordIDs, media: "movie", sort: sort)
                async let series = discoverKeywordCategorySingleMedia(keywordIDs: keywordIDs, media: "tv", sort: sort)
                return try await (movies + series).uniqued().prefixArray(50)
            case .movie:
                return try await discoverKeywordCategorySingleMedia(keywordIDs: keywordIDs, media: "movie", sort: sort)
            case .tv:
                return try await discoverKeywordCategorySingleMedia(keywordIDs: keywordIDs, media: "tv", sort: sort)
            }
        }

        private func discoverKeywordCategorySingleMedia(keywordIDs: [Int], media: String, sort: GenreSort) async throws -> [MediaItem] {
            try await fetchListPages(path: "/discover/\(media)", query: [
                URLQueryItem(name: "sort_by", value: sort.tmdbSort),
                URLQueryItem(name: "with_keywords", value: keywordIDs.map(String.init).joined(separator: "|")),
                URLQueryItem(name: "include_adult", value: "false"),
                URLQueryItem(name: "include_video", value: "false"),
                URLQueryItem(name: "vote_count.gte", value: media == "movie" ? "80" : "50"),
                URLQueryItem(name: "vote_average.gte", value: "5.5"),
                URLQueryItem(name: "region", value: "US"),
                URLQueryItem(name: "watch_region", value: "US")
            ], pages: 5)
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
            
            let limitedEntries = Array(filteredEntries.prefix(6))
            try await withThrowingTaskGroup(of: MediaItem?.self) { group in
                for entry in limitedEntries {
                    group.addTask {
                        try await resolveCuratedEntry(entry)
                    }
                }

                for try await item in group {
                    if let item {
                        resolved.append(item)
                    }
                }
            }
            
            return resolved
                .uniqued()
                .prefixArray(6)
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

        private static let basedOnTrueStoryCategoryID = 30001
        private static let basedOnBookCategoryID = 30002
        private static let basedOnGameCategoryID = 30003

        private static let specialCategoryKeywordIDs: [Int: [Int]] = [
            basedOnTrueStoryCategoryID: [9672],
            basedOnBookCategoryID: [818],
            basedOnGameCategoryID: [41645]
        ]
        
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

        func discoverPickForMe(filter: MediaFilter, genreIDs: Set<Int>, runtime: PickForMeRuntime?, minimumRating: Double, includeAdult: Bool, sortBy: String) async throws -> [MediaItem] {
            switch filter {
            case .movie:
                return try await discoverPickForMeSingleMedia(media: "movie", genreIDs: genreIDs, runtime: runtime, minimumRating: minimumRating, includeAdult: includeAdult, sortBy: sortBy)
            case .tv:
                return try await discoverPickForMeSingleMedia(media: "tv", genreIDs: genreIDs, runtime: runtime, minimumRating: minimumRating, includeAdult: includeAdult, sortBy: sortBy)
            case .both:
                async let movies = discoverPickForMeSingleMedia(media: "movie", genreIDs: genreIDs, runtime: runtime, minimumRating: minimumRating, includeAdult: includeAdult, sortBy: sortBy)
                async let series = discoverPickForMeSingleMedia(media: "tv", genreIDs: genreIDs, runtime: runtime, minimumRating: minimumRating, includeAdult: includeAdult, sortBy: sortBy)
                return try await movies + series
            }
        }

        func discoverSourceMaterial(_ sourceMaterial: PickForMeSourceMaterial, filter: MediaFilter) async throws -> [MediaItem] {
            let keywordIDs = sourceMaterial.keywordIDs
            guard !keywordIDs.isEmpty else { return [] }

            switch filter {
            case .movie:
                return try await discoverSourceMaterialSingleMedia(keywordIDs: keywordIDs, media: "movie")
            case .tv:
                return try await discoverSourceMaterialSingleMedia(keywordIDs: keywordIDs, media: "tv")
            case .both:
                async let movies = discoverSourceMaterialSingleMedia(keywordIDs: keywordIDs, media: "movie")
                async let series = discoverSourceMaterialSingleMedia(keywordIDs: keywordIDs, media: "tv")
                return try await movies + series
            }
        }

        private func discoverSourceMaterialSingleMedia(keywordIDs: [Int], media: String) async throws -> [MediaItem] {
            return try await fetchListPages(path: "/discover/\(media)", query: [
                URLQueryItem(name: "sort_by", value: "vote_average.desc"),
                URLQueryItem(name: "with_keywords", value: keywordIDs.map(String.init).joined(separator: "|")),
                URLQueryItem(name: "include_adult", value: "false"),
                URLQueryItem(name: "include_video", value: "false"),
                URLQueryItem(name: "vote_count.gte", value: media == "movie" ? "80" : "50"),
                URLQueryItem(name: "vote_average.gte", value: "5.5"),
                URLQueryItem(name: "region", value: "US"),
                URLQueryItem(name: "watch_region", value: "US")
            ], pages: 2)
        }

        private func discoverPickForMeSingleMedia(media: String, genreIDs: Set<Int>, runtime: PickForMeRuntime?, minimumRating: Double, includeAdult: Bool, sortBy: String) async throws -> [MediaItem] {
            var query: [URLQueryItem] = [
                URLQueryItem(name: "sort_by", value: sortBy),
                URLQueryItem(name: "include_adult", value: includeAdult ? "true" : "false"),
                URLQueryItem(name: "include_video", value: "false"),
                URLQueryItem(name: "region", value: "US"),
                URLQueryItem(name: "watch_region", value: "US"),
                URLQueryItem(name: "vote_count.gte", value: media == "movie" ? "120" : "80")
            ]

            if !genreIDs.isEmpty {
                query.append(URLQueryItem(name: "with_genres", value: genreIDs.map(String.init).sorted().joined(separator: ",")))
            }

            if minimumRating > 0 {
                query.append(URLQueryItem(name: "vote_average.gte", value: String(format: "%.1f", minimumRating)))
            }

            if let minimumMinutes = runtime?.minimumMinutes {
                query.append(URLQueryItem(name: "with_runtime.gte", value: String(minimumMinutes)))
            }

            if let maximumMinutes = runtime?.maximumMinutes {
                query.append(URLQueryItem(name: "with_runtime.lte", value: String(maximumMinutes)))
            }

            return try await fetchListPages(path: "/discover/\(media)", query: query, pages: 3)
        }

        func keywordDiscoveryCandidates(for item: MediaItem, keywordIDs: [Int]) async throws -> [MediaItem] {
            let keywordIDs = Array(keywordIDs.prefix(8))
            guard !keywordIDs.isEmpty else { return [] }
            let media = item.kind == .tv ? "tv" : "movie"
            return try await fetchListPages(path: "/discover/\(media)", query: [
                URLQueryItem(name: "sort_by", value: "popularity.desc"),
                URLQueryItem(name: "with_keywords", value: keywordIDs.map(String.init).joined(separator: "|")),
                URLQueryItem(name: "include_adult", value: "false"),
                URLQueryItem(name: "include_video", value: "false"),
                URLQueryItem(name: "vote_count.gte", value: item.kind == .tv ? "50" : "80"),
                URLQueryItem(name: "vote_average.gte", value: "5.8"),
                URLQueryItem(name: "region", value: "US"),
                URLQueryItem(name: "watch_region", value: "US")
            ], pages: 2)
        }

        func sharedPersonCandidates(for item: MediaItem, personIDs: [Int]) async throws -> [MediaItem] {
            let personIDs = Array(personIDs.prefix(8))
            guard !personIDs.isEmpty else { return [] }
            let media = item.kind == .tv ? "tv" : "movie"
            return try await fetchListPages(path: "/discover/\(media)", query: [
                URLQueryItem(name: "sort_by", value: "popularity.desc"),
                URLQueryItem(name: "with_people", value: personIDs.map(String.init).joined(separator: "|")),
                URLQueryItem(name: "include_adult", value: "false"),
                URLQueryItem(name: "include_video", value: "false"),
                URLQueryItem(name: "vote_count.gte", value: item.kind == .tv ? "50" : "80"),
                URLQueryItem(name: "vote_average.gte", value: "5.8"),
                URLQueryItem(name: "region", value: "US"),
                URLQueryItem(name: "watch_region", value: "US")
            ], pages: 2)
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
            
            return try await fetchListPages(path: "/discover/\(media)", query: query, pages: 2)
                .filter { item in
                    guard item.kind == .movie || item.kind == .tv else { return false }
                    return item.categoryGenreIDs.contains(genreID)
                }
        }
        
        private func tmdbGenreIDsToQuery(for genreID: Int, media: String) -> [Int] {
            guard media == "tv" else { return [genreID] }
            
            switch genreID {
            case 28:
                return [10759]
            case 878:
                return []
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
                case 16, 35, 10762, 10764, 10767:
                    return "60"
                case 878, 14:
                    return "120"
                default:
                    return "100"
                }
            }
            
            switch genreID {
            case 16, 27, 35, 37, 99, 36, 10752, 10749, 10751:
                return "150"
            default:
                return "220"
            }
        }
        
        private func minimumVoteAverage(for genreID: Int, media: String) -> String {
            if media == "tv" {
                switch genreID {
                case 27:
                    return "5.8"
                case 35, 10762, 10764, 10767:
                    return "6.0"
                default:
                    return "6.1"
                }
            }
            
            switch genreID {
            case 27:
                return "5.7"
            case 35, 37, 99, 36, 10752, 10749, 10751:
                return "5.9"
            default:
                return "6.0"
            }
        }
        
        func recommendations(for key: MediaKey) async throws -> [MediaItem] {
            try await fetchList(path: "/\(key.kind.tmdbPath)/\(key.id)/recommendations", query: [])
                .filter { $0.shouldShowInDiscovery && !$0.isUpcoming }
        }
        
        func sameSeriesOrSimilar(for key: MediaKey) async throws -> [MediaItem] {
            try await fetchList(path: "/\(key.kind.tmdbPath)/\(key.id)/similar", query: [])
                .filter { $0.shouldShowInDiscovery && !$0.isUpcoming }
        }
        
        func detail(for item: MediaItem) async throws -> MediaDetail {
            let response: TMDbDetailResponse = try await fetch(path: "/\(item.kind.tmdbPath)/\(item.id)", query: [URLQueryItem(
                name: "append_to_response",
                value: item.kind == .movie
                ? "credits,similar,recommendations,keywords,watch/providers,release_dates"
                : "credits,similar,recommendations,keywords,watch/providers,content_ratings"
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
            var comps = URLComponents(string: base + "/tmdb-proxy")!
            comps.queryItems = [
                URLQueryItem(name: "path", value: path),
                URLQueryItem(name: "page", value: String(page))
            ] + query
            guard let url = comps.url else { throw URLError(.badURL) }
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) { throw URLError(.badServerResponse) }
            return try JSONDecoder().decode(T.self, from: data)
        }
    }

    private struct TasteDiveService {
        private let base = "https://mtttuyvpjyugudkevchj.supabase.co/functions/v1/vestigo-api"

        func similarTitles(for title: String, kind: MediaKind) async throws -> [String] {
            guard kind == .movie || kind == .tv else { return [] }

            var components = URLComponents(string: base + "/tastedive-similar")!
            components.queryItems = [
                URLQueryItem(name: "q", value: title),
                URLQueryItem(name: "type", value: kind == .tv ? "show" : "movie"),
                URLQueryItem(name: "limit", value: "20")
            ]

            guard let url = components.url else { throw URLError(.badURL) }
            let (data, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                throw URLError(.badServerResponse)
            }

            let decoded = try JSONDecoder().decode(TasteDiveSimilarResponse.self, from: data)
            return decoded.results
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
    }

    private struct TasteDiveSimilarResponse: Decodable {
        let ok: Bool
        let results: [String]
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
        let birthday: String?
        let deathday: String?
        let placeOfBirth: String?
        let knownForDepartment: String?
        
        enum CodingKeys: String, CodingKey {
            case id
            case biography
            case birthday
            case deathday
            case placeOfBirth = "place_of_birth"
            case knownForDepartment = "known_for_department"
        }
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
        let birthday: String?
        let deathday: String?
        let placeOfBirth: String?
        let knownForDepartment: String?
        
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
            case birthday
            case deathday
            case placeOfBirth = "place_of_birth"
            case knownForDepartment = "known_for_department"
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
        let keywords: TMDbKeywordsResponse?
        
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
            case keywords
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
            belongsToCollection: TMDbCollectionReference?,
            keywords: TMDbKeywordsResponse?
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
            self.keywords = keywords
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
                belongsToCollection: belongsToCollection,
                keywords: keywords
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
    
    private struct TMDbKeywordsResponse: Decodable {
        let keywords: [TMDbKeyword]?
        let results: [TMDbKeyword]?

        var keywordIDs: [Int] {
            (keywords ?? results ?? []).map(\.id)
        }
    }

    private struct TMDbKeyword: Decodable, Hashable {
        let id: Int
        let name: String
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
        
        var extraPreviewText: String? {
            if !role.isEmpty {
                return "Known for \(role.lowercased())"
            }
            return nil
        }
    }
    
    private struct PersonDetail: Codable, Hashable {
        let id: Int
        let biography: String
        let birthday: String?
        let deathday: String?
        let placeOfBirth: String?
        let knownForDepartment: String?
        
        nonisolated init(
            id: Int,
            biography: String,
            birthday: String? = nil,
            deathday: String? = nil,
            placeOfBirth: String? = nil,
            knownForDepartment: String? = nil
        ) {
            self.id = id
            self.biography = biography
            self.birthday = birthday
            self.deathday = deathday
            self.placeOfBirth = placeOfBirth
            self.knownForDepartment = knownForDepartment
        }
        
        init(response: TMDbPersonDetailResponse) {
            id = response.id
            biography = response.biography ?? ""
            birthday = response.birthday
            deathday = response.deathday
            placeOfBirth = response.placeOfBirth
            knownForDepartment = response.knownForDepartment
        }
        
        var lifespanText: String? {
            let birthYear = birthday?.prefix(4)
            let deathYear = deathday?.prefix(4)
            
            if let birthYear, let deathYear {
                return "\(birthYear)–\(deathYear)"
            }
            
            if let birthYear {
                return "\(birthYear)–present"
            }
            
            return nil
        }
        
        var shortBiography: String? {
            let trimmed = biography.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let sentenceEndings: [Character] = [".", "!", "?"]
            if let firstSentenceEnd = trimmed.firstIndex(where: { sentenceEndings.contains($0) }) {
                let end = trimmed.index(after: firstSentenceEnd)
                return String(trimmed[..<end])
            }
            return String(trimmed.prefix(180))
        }

        var detailBiography: String? {
            let trimmed = biography.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if trimmed.count <= 700 { return trimmed }
            return String(trimmed.prefix(700)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
        }
        
        var fullBiography: String? {
            let trimmed = biography.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        var tinyBiography: String? {
            guard let shortBiography else { return nil }
            let trimmed = shortBiography.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if trimmed.count <= 95 { return trimmed }
            return String(trimmed.prefix(95)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
        }
        
        var compactMetadataText: String? {
            var parts: [String] = []
            if let lifespanText { parts.append(lifespanText) }
            if let knownForDepartment, !knownForDepartment.isEmpty { parts.append(knownForDepartment) }
            if let placeOfBirth, !placeOfBirth.isEmpty { parts.append(placeOfBirth) }
            return parts.isEmpty ? nil : parts.joined(separator: " • ")
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
        
        nonisolated init(
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
    
    private struct MediaKey: Codable, nonisolated Hashable, Identifiable {
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
        let keywordIDs: [Int]
        
        init(response: TMDbDetailResponse, fallback: MediaItem) {
            let crewList: [PersonDTO] = response.credits?.crew ?? []
            let castList: [PersonDTO] = response.credits?.cast ?? []
            tmdbCollectionID = response.belongsToCollection?.id
            firstAirDate = response.firstAirDate
            lastAirDate = response.lastAirDate
            status = response.status
            runtime = response.runtime
            ageRating = response.usAgeRating
            keywordIDs = response.keywords?.keywordIDs ?? []
            
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
            similar = Self.rankedSimilarItems(
                mappedSimilar.uniqued().filter { $0.shouldShowInDiscovery && !$0.isUpcoming && $0.key != fallback.key },
                source: fallback,
                cast: mappedCast,
                keyCrew: uniqueKeyCrew,
                runtime: runtime,
                sourceBoosts: [:]
            )
        }

        func addingSimilarCandidates(_ candidates: [MediaItem], source: MediaItem, sourceBoosts: [MediaKey: Double] = [:]) -> MediaDetail {
            MediaDetail(
                director: director,
                creator: creator,
                cast: cast,
                castAndKeyCrew: castAndKeyCrew,
                seasons: seasons,
                similar: Self.rankedSimilarItems(
                    (similar + candidates).uniqued().filter { $0.shouldShowInDiscovery && !$0.isUpcoming && $0.key != source.key },
                    source: source,
                    cast: cast,
                    keyCrew: castAndKeyCrew,
                    runtime: runtime,
                    sourceBoosts: sourceBoosts
                ),
                firstAirDate: firstAirDate,
                lastAirDate: lastAirDate,
                status: status,
                runtime: runtime,
                ageRating: ageRating,
                tmdbCollectionID: tmdbCollectionID,
                keywordIDs: keywordIDs
            )
        }

        private init(director: PersonSummary?, creator: PersonSummary?, cast: [PersonSummary], castAndKeyCrew: [PersonSummary], seasons: [SeasonInfo], similar: [MediaItem], firstAirDate: String?, lastAirDate: String?, status: String?, runtime: Int?, ageRating: String?, tmdbCollectionID: Int?, keywordIDs: [Int]) {
            self.director = director
            self.creator = creator
            self.cast = cast
            self.castAndKeyCrew = castAndKeyCrew
            self.seasons = seasons
            self.similar = similar
            self.firstAirDate = firstAirDate
            self.lastAirDate = lastAirDate
            self.status = status
            self.runtime = runtime
            self.ageRating = ageRating
            self.tmdbCollectionID = tmdbCollectionID
            self.keywordIDs = keywordIDs
        }

        private static func rankedSimilarItems(_ items: [MediaItem], source: MediaItem, cast: [PersonSummary], keyCrew: [PersonSummary], runtime: Int?, sourceBoosts: [MediaKey: Double]) -> [MediaItem] {
            let sourceGenres = Set(source.genreIDs)
            let sourceText = normalizedSimilarityText("\(source.title) \(source.overview)")
            let sourceTokens = Set(sourceText.split(separator: " ").map(String.init).filter { $0.count >= 4 })
            let castNames = Set(cast.prefix(6).map { normalizedSimilarityText($0.name) })
            let crewNames = Set(keyCrew.prefix(6).map { normalizedSimilarityText($0.name) })

            return items
                .map { item -> (item: MediaItem, score: Double) in
                    let itemGenres = Set(item.genreIDs)
                    let itemText = normalizedSimilarityText("\(item.title) \(item.overview)")
                    let itemTokens = Set(itemText.split(separator: " ").map(String.init).filter { $0.count >= 4 })
                    let sharedSpecificTokens = sourceTokens.intersection(itemTokens).filter { !broadSimilarityTokens.contains($0) }
                    var score = 0.0

                    score += titleRelationshipScore(sourceTitle: source.title, itemTitle: item.title)

                    score += Double(sharedSpecificTokens.count) * 4.0
                    score += Double(sourceGenres.intersection(itemGenres).count) * 1.4

                    if item.originalLanguage == source.originalLanguage {
                        score += 2.0
                    }

                    if let sourceYear = source.releaseYearNumber, let itemYear = item.releaseYearNumber {
                        let distance = abs(sourceYear - itemYear)
                        if distance <= 3 {
                            score += 2.0
                        } else if distance <= 8 {
                            score += 0.8
                        }
                    }

                    if let runtime, let itemRuntime = item.runtime {
                        let runtimeDistance = abs(runtime - itemRuntime)
                        if runtimeDistance <= 15 {
                            score += 1.4
                        } else if runtimeDistance <= 30 {
                            score += 0.6
                        }
                    }

                    if itemText.containsAny(Array(castNames)) {
                        score += 3.0
                    }

                    if itemText.containsAny(Array(crewNames)) {
                        score += 4.0
                    }

                    score += sourceBoosts[item.key] ?? 0
                    score += min(item.voteAverage, 10) * 0.25

                    return (item, score)
                }
                .sorted { lhs, rhs in
                    if lhs.score != rhs.score { return lhs.score > rhs.score }
                    return lhs.item.voteAverage > rhs.item.voteAverage
                }
                .map(\.item)
        }

        private static let broadSimilarityTokens: Set<String> = [
            "movie", "film", "series", "story", "life", "world", "young", "find", "must", "when", "after", "about", "into", "from", "their", "with"
        ]

        private static func normalizedSimilarityText(_ value: String) -> String {
            value
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .lowercased()
                .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private static func titleStem(_ value: String) -> String {
            normalizedSimilarityText(value)
                .replacingOccurrences(of: "\\b(the|a|an|part|chapter|season|movie|film)\\b", with: "", options: .regularExpression)
                .split(separator: " ")
                .prefix(3)
                .joined(separator: " ")
        }

        private static func titleRelationshipScore(sourceTitle: String, itemTitle: String) -> Double {
            let source = normalizedSimilarityText(sourceTitle)
            let item = normalizedSimilarityText(itemTitle)
            guard !source.isEmpty, !item.isEmpty else { return 0 }
            if source == item { return 42 }

            if item.hasPrefix(source + " ") {
                let suffix = item.dropFirst(source.count).trimmingCharacters(in: .whitespacesAndNewlines)
                let firstToken = suffix.split(separator: " ").first.map(String.init) ?? ""
                let sequelTokens: Set<String> = ["2", "3", "4", "5", "6", "7", "8", "9", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix"]

                if sequelTokens.contains(firstToken) {
                    return 92
                }

                if suffix.hasPrefix("part ") || suffix.hasPrefix("chapter ") || suffix.hasPrefix("vol ") || suffix.hasPrefix("volume ") {
                    return 78
                }

                return 38
            }

            let sourceStem = titleStem(sourceTitle)
            let itemStem = titleStem(itemTitle)
            if !sourceStem.isEmpty && sourceStem == itemStem { return 36 }
            if !sourceStem.isEmpty && (itemStem.contains(sourceStem) || sourceStem.contains(itemStem)) { return 18 }
            return 0
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
        var favouriteKeys: Set<MediaKey> = []
        var neverShowAgain: Set<MediaKey> = []
        var watchedOrder: [MediaKey] = []
        var collections: [MediaCollection] = []
        var watchedEpisodes: Set<EpisodeKey> = []

        private enum CodingKeys: String, CodingKey {
            case items
            case watchlist
            case watched
            case ratings
            case favouriteKeys
            case neverShowAgain
            case watchedOrder
            case collections
            case watchedEpisodes
        }

        init() { }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            items = try container.decodeIfPresent([MediaKey: MediaItem].self, forKey: .items) ?? [:]
            watchlist = try container.decodeIfPresent(Set<MediaKey>.self, forKey: .watchlist) ?? []
            watched = try container.decodeIfPresent(Set<MediaKey>.self, forKey: .watched) ?? []
            ratings = try container.decodeIfPresent([MediaKey: Double].self, forKey: .ratings) ?? [:]
            favouriteKeys = try container.decodeIfPresent(Set<MediaKey>.self, forKey: .favouriteKeys) ?? []
            neverShowAgain = try container.decodeIfPresent(Set<MediaKey>.self, forKey: .neverShowAgain) ?? []
            watchedOrder = try container.decodeIfPresent([MediaKey].self, forKey: .watchedOrder) ?? []
            collections = try container.decodeIfPresent([MediaCollection].self, forKey: .collections) ?? []
            watchedEpisodes = try container.decodeIfPresent(Set<EpisodeKey>.self, forKey: .watchedEpisodes) ?? []
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(items, forKey: .items)
            try container.encode(watchlist, forKey: .watchlist)
            try container.encode(watched, forKey: .watched)
            try container.encode(ratings, forKey: .ratings)
            try container.encode(favouriteKeys, forKey: .favouriteKeys)
            try container.encode(neverShowAgain, forKey: .neverShowAgain)
            try container.encode(watchedOrder, forKey: .watchedOrder)
            try container.encode(collections, forKey: .collections)
            try container.encode(watchedEpisodes, forKey: .watchedEpisodes)
        }

        var watchlistItems: [MediaItem] { watchlist.compactMap { items[$0] } }
        var watchedItems: [MediaItem] { watched.compactMap { items[$0] } }

        func isInWatchlist(_ key: MediaKey) -> Bool { watchlist.contains(key) }
        func isWatched(_ key: MediaKey) -> Bool { watched.contains(key) }
        func isNeverShowAgain(_ key: MediaKey) -> Bool { neverShowAgain.contains(key) }

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

        var favouriteItems: [MediaItem] {
            favouriteKeys.compactMap { items[$0] }
        }

        var lastWatchedItem: MediaItem? {
            for key in watchedOrder.reversed() {
                if watched.contains(key), let item = items[key] {
                    return item
                }
            }
            return watchedItems.last
        }

        func favouriteItems(for filter: MediaFilter) -> [MediaItem] {
            let favourites = favouriteItems
            switch filter {
            case .both:
                return favourites.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            case .movie:
                return favourites
                    .filter { $0.kind == .movie }
                    .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            case .tv:
                return favourites
                    .filter { $0.kind == .tv }
                    .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            }
        }

        func isFavourite(_ item: MediaItem) -> Bool {
            favouriteKeys.contains(item.key)
        }

        mutating func toggleFavourite(_ item: MediaItem) {
            items[item.key] = item
            if favouriteKeys.contains(item.key) {
                favouriteKeys.remove(item.key)
            } else {
                favouriteKeys.insert(item.key)
            }
        }

        mutating func toggleNeverShowAgain(_ item: MediaItem) {
            items[item.key] = item
            if neverShowAgain.contains(item.key) {
                neverShowAgain.remove(item.key)
            } else {
                neverShowAgain.insert(item.key)
            }
        }

        mutating func clearFavourites(for filter: MediaFilter) {
            switch filter {
            case .both:
                favouriteKeys.removeAll()
            case .movie:
                favouriteKeys = favouriteKeys.filter { $0.kind != .movie }
            case .tv:
                favouriteKeys = favouriteKeys.filter { $0.kind != .tv }
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
        var hideAdultResults: Bool = false
        var hideAnimeResults: Bool = false
        var hideLowestAgeRatings: Bool = false
        var hideWatchedFromHome: Bool = false
        var hideWatchedFromSearch: Bool = false
        var hideShortFilmsFromHome = false
        var hideShortFilmsFromSearch = false
        var hideShortFilmsFromRecommended = false
        var hideShortFilmsFromCollectionRecommendations = false
        var defaultSearchFilter: SearchFilter = .all
        var defaultHomeFilter: MediaFilter = .both
        var defaultCategorySort: GenreSort = .tmdbRating
        var showUpcomingReleases: Bool = true
        var hideUpcomingFromSearch = false
        var hideUpcomingFromRecommended = false
        var hideUpcomingFromCollectionRecommendations = false
        var warnBeforeReplacingFavourite = true
        var promptToRateAfterMarkingWatched = true
        var preferredRatingSource: RatingSource = .imdb
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
    private enum RatingSource: String, Codable, CaseIterable, Identifiable, Hashable {
        case tmdb
        case imdb

        var id: String { rawValue }

        var title: String {
            switch self {
            case .tmdb: return "TMDb"
            case .imdb: return "IMDb"
            }
        }
    }
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
    private enum GenreSort: String, Codable, CaseIterable, Identifiable { case tmdbRating, releaseDate; var id: String { rawValue }; var title: String { self == .tmdbRating ? "IMDb rating" : "Released" }; var tmdbSort: String { self == .tmdbRating ? "popularity.desc" : "primary_release_date.desc" } }
    private enum SwipeContext { case none, watchlist, collection(UUID) }
    private enum SectionRoute: String, Hashable {
        case trending, popular, newReleases, upcoming, settings
        
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
            case .settings:
                return "Settings"
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
        var mediaScope: MediaFilter = .both
        
        var imageURLValue: URL? {
            URL(string: imageURL)
        }
        
        static let all = [
            GenreDefinition(name: "Action", tmdbID: 28, iconicFilm: "Die Hard", imageURL: "https://image.tmdb.org/t/p/w780/4HWAQu28e2yaWrtupFPGFkdNU7V.jpg"),
            GenreDefinition(name: "Adventure", tmdbID: 12, iconicFilm: "Indiana Jones", imageURL: "https://image.tmdb.org/t/p/w780/ceG9VzoRAVGwivFU403Wc3AHRys.jpg"),
            GenreDefinition(name: "Sci-Fi", tmdbID: 878, iconicFilm: "Blade Runner 2049", imageURL: "https://image.tmdb.org/t/p/w780/8rpDcsfLJypbO6vREc0547VKqEv.jpg"),
            GenreDefinition(name: "Fantasy", tmdbID: 14, iconicFilm: "The Lord of the Rings", imageURL: "https://image.tmdb.org/t/p/w780/6oom5QYQ2yQTMJIbnvbkBL9cHo6.jpg"),
            GenreDefinition(name: "Drama", tmdbID: 18, iconicFilm: "The Godfather", imageURL: "https://image.tmdb.org/t/p/w780/3bhkrj58Vtu7enYsRolD1fZdja1.jpg"),
            GenreDefinition(name: "Horror", tmdbID: 27, iconicFilm: "Alien", imageURL: "https://image.tmdb.org/t/p/w500/vfrQk5IPloGg1v9Rzbh2Eg3VGyM.jpg"),
            GenreDefinition(name: "Animation", tmdbID: 16, iconicFilm: "Spirited Away", imageURL: "https://image.tmdb.org/t/p/w780/39wmItIWsg5sZMyRUHLkWBcuVCM.jpg"),
            GenreDefinition(name: "Crime", tmdbID: 80, iconicFilm: "Pulp Fiction", imageURL: "https://image.tmdb.org/t/p/w500/d5iIlFn5s0ImszYzBPb8JPIfbXD.jpg"),
            GenreDefinition(name: "Comedy", tmdbID: 35, iconicFilm: "Airplane!", imageURL: "https://image.tmdb.org/t/p/w780/hiURvJjCgk0s10urHVCg80TFF11.jpg"),
            GenreDefinition(name: "Mystery", tmdbID: 9648, iconicFilm: "Knives Out", imageURL: "https://image.tmdb.org/t/p/w780/pThyQovXQrw2m0s9x82twj48Jq4.jpg"),
            GenreDefinition(name: "Thriller", tmdbID: 53, iconicFilm: "Gone Girl", imageURL: "https://image.tmdb.org/t/p/w780/qymaJhucquUwjpb8oiqynMeXnID.jpg"),
            GenreDefinition(name: "Romance", tmdbID: 10749, iconicFilm: "Before Sunrise", imageURL: "https://image.tmdb.org/t/p/w780/kf1Jb1c2JAOqjuzA3H4oDM263uB.jpg", mediaScope: .movie),
            GenreDefinition(name: "Family", tmdbID: 10751, iconicFilm: "Paddington", imageURL: "https://image.tmdb.org/t/p/w780/2M2JxEv3HSpjnZWjY9NOdGgfUd.jpg", mediaScope: .movie),
            GenreDefinition(name: "Documentary", tmdbID: 99, iconicFilm: "Free Solo", imageURL: "https://image.tmdb.org/t/p/w780/oQHF0Y4gCw6VdPmapjsbZoxY2ht.jpg"),
            GenreDefinition(name: "History", tmdbID: 36, iconicFilm: "Oppenheimer", imageURL: "https://image.tmdb.org/t/p/w780/8Gxv8gSFCU0XGDykEGv7zR1n2ua.jpg", mediaScope: .movie),
            GenreDefinition(name: "Based on a True Story", tmdbID: 30001, iconicFilm: "The Social Network", imageURL: "https://image.tmdb.org/t/p/w780/n0ybibhJtQ5icDqTp8eRytcIHJx.jpg"),
            GenreDefinition(name: "Based on a Book", tmdbID: 30002, iconicFilm: "The Lord of the Rings", imageURL: "https://image.tmdb.org/t/p/w780/6oom5QYQ2yQTMJIbnvbkBL9cHo6.jpg"),
            GenreDefinition(name: "Based on a Game", tmdbID: 30003, iconicFilm: "The Last of Us", imageURL: "https://image.tmdb.org/t/p/w780/uKvVjHNqB5VmOrdxqAt2F7J78ED.jpg"),
            GenreDefinition(name: "War", tmdbID: 10752, iconicFilm: "1917", imageURL: "https://image.tmdb.org/t/p/w780/iZf0KyrE25z1sage4SYFLCCrMi9.jpg", mediaScope: .movie),
            GenreDefinition(name: "Western", tmdbID: 37, iconicFilm: "Unforgiven", imageURL: "https://image.tmdb.org/t/p/w780/yKyLJmRAtyXEEYKOvPhKHXIcPq9.jpg"),
            GenreDefinition(name: "Reality", tmdbID: 10764, iconicFilm: "The Traitors", imageURL: "https://image.tmdb.org/t/p/w780/7lD7Q3dP6tQheQw3JIgYfR3MN6Y.jpg", mediaScope: .tv),
            GenreDefinition(name: "Talk", tmdbID: 10767, iconicFilm: "Hot Ones", imageURL: "https://image.tmdb.org/t/p/w780/2n95p9isIi1LYTscTcGytlI4zYd.jpg", mediaScope: .tv),
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
        var categoryGenreIDs: Set<Int> {
            Set(genreIDs.compactMap { Self.categoryGenrePriorityMap[$0] })
        }
        
        private static let categoryGenrePriorityMap: [Int: Int] = [
            28: 28,
            12: 12,
            878: 878,
            10765: 14,
            14: 14,
            18: 18,
            27: 27,
            16: 16,
            80: 80,
            35: 35,
            9648: 9648,
            53: 53,
            10749: 10749,
            10751: 10751,
            99: 99,
            36: 36,
            10752: 10752,
            10768: 10752,
            37: 37,
            10762: 10762,
            10764: 10764,
            10767: 10767,
            10759: 28
        ]
    }
    
    
    // MARK: - Helpers
    
    private enum DynamicCollections {
        static func inferredSeriesNames(for item: MediaItem) -> [String] {
            []
        }
        static func broadCollections(for item: MediaItem) -> [String] {
            var genreNames: Set<String> = []

            for genreID in item.genreIDs {
                if let movieGenreName = GenreDefinition.all.first(where: { $0.tmdbID == genreID })?.name {
                    genreNames.insert(movieGenreName)
                }

                for tvGenreName in tvGenreNames(for: genreID) {
                    genreNames.insert(tvGenreName)
                }
            }

            return Array(genreNames).sorted()
        }

        private static func tvGenreNames(for genreID: Int) -> [String] {
            switch genreID {
            case 10759:
                return ["Action", "Adventure"]
            case 16:
                return ["Animation"]
            case 35:
                return ["Comedy"]
            case 80:
                return ["Crime"]
            case 99:
                return ["Documentary"]
            case 18:
                return ["Drama"]
            case 10751:
                return ["Family"]
            case 10762:
                return ["Kids"]
            case 9648:
                return ["Mystery"]
            case 10763:
                return ["News"]
            case 10764:
                return ["Reality"]
            case 10765:
                return ["Fantasy"]
            case 10766:
                return ["Soap"]
            case 10767:
                return ["Talk"]
            case 10768:
                return ["War", "Politics"]
            case 37:
                return ["Western"]
            default:
                return []
            }
        }

        static func tmdbGenreIDs(forCollectionName name: String) -> Set<Int> {
            switch name.lowercased() {
            case "action":
                return [28, 10759]
            case "adventure":
                return [12, 10759]
            case "animation":
                return [16]
            case "comedy":
                return [35]
            case "crime":
                return [80]
            case "documentary":
                return [99]
            case "drama":
                return [18]
            case "family":
                return [10751]
            case "fantasy":
                return [14, 10765]
            case "horror":
                return [27]
            case "kids":
                return [10762]
            case "mystery":
                return [9648]
            case "news":
                return [10763]
            case "reality":
                return [10764]
            case "sci-fi", "science fiction", "sci fi":
                return [878, 10765]
            case "soap":
                return [10766]
            case "talk":
                return [10767]
            case "war":
                return [10752, 10768]
            case "politics":
                return [10768]
            case "western":
                return [37]
            default:
                if let genre = GenreDefinition.all.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                    return [genre.tmdbID]
                }
                return []
            }
        }

        static func item(_ item: MediaItem, belongsToCollectionNamed collectionName: String) -> Bool {
            let genreIDs = tmdbGenreIDs(forCollectionName: collectionName)
            guard !genreIDs.isEmpty else { return false }
            return !Set(item.genreIDs).intersection(genreIDs).isEmpty
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
                return ($0.releaseDateValue ?? .distantPast) > ($1.releaseDateValue ?? .distantPast)
            }
        }
        
        func sortedBySimilarity(to seed: MediaItem) -> [MediaItem] {
            sorted { lhs, rhs in
                let lhsScore = lhs.similarityScore(to: seed)
                let rhsScore = rhs.similarityScore(to: seed)
                
                if lhsScore != rhsScore {
                    return lhsScore > rhsScore
                }
                
                return (lhs.releaseDateValue ?? .distantPast) > (rhs.releaseDateValue ?? .distantPast)
            }
        }
        
        func sorted(
            using option: SortOption,
            ratings: [MediaKey: Double],
            externalRatings: [MediaKey: ExternalRatings] = [:],
            ratingSource: RatingSource = .tmdb
        ) -> [MediaItem] {
            func ratingValue(for item: MediaItem) -> Double {
                if ratingSource == .imdb,
                   let imdbRating = externalRatings[item.key]?.imdbRating {
                    return imdbRating
                }

                return -1
            }

            return sorted { a, b in
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
                    let av = ratingValue(for: a)
                    let bv = ratingValue(for: b)
                    if av != bv { return av > bv }
                }
                return (a.releaseDateValue ?? .distantPast) > (b.releaseDateValue ?? .distantPast)
            }
        }
        
        func sortedByCategoryRank() -> [MediaItem] {
            sorted { a, b in
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

    private extension String {
        func containsAny(_ needles: [String]) -> Bool {
            needles.contains { contains($0) }
        }
    }

    private struct LiquidGlassModifier: ViewModifier {
        @Environment(\.colorScheme) private var colorScheme
        let cornerRadius: CGFloat

        func body(content: Content) -> some View {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

            if #available(iOS 26.0, *) {
                content
                    .padding(1)
                    .background(.clear, in: shape)
                    .glassEffect(.regular, in: shape)
                    .overlay {
                        shape.fill(colorScheme == .light ? .black.opacity(0.055) : .clear)
                    }
                    .overlay {
                        shape.stroke(colorScheme == .light ? .black.opacity(0.12) : .clear, lineWidth: 1)
                    }
                    .clipShape(shape)
                    .shadow(color: .black.opacity(colorScheme == .light ? 0.12 : 0.18), radius: 16, x: 0, y: 9)
            } else {
                content
                    .background {
                        shape
                            .fill(.ultraThinMaterial)
                            .background(
                                shape.fill(colorScheme == .light ? .black.opacity(0.075) : .white.opacity(0.10))
                            )
                            .overlay {
                                shape.stroke(colorScheme == .light ? .black.opacity(0.12) : .white.opacity(0.16), lineWidth: 1)
                            }
                            .shadow(color: .black.opacity(colorScheme == .light ? 0.10 : 0.22), radius: 18, x: 0, y: 10)
                    }
                    .clipShape(shape)
            }
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
        func liquidGlass(cornerRadius: CGFloat = 24) -> some View {
            modifier(LiquidGlassModifier(cornerRadius: cornerRadius))
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
        let alwaysBounce: Bool
        
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
            scrollView.alwaysBounceVertical = axis == .vertical && alwaysBounce
            scrollView.alwaysBounceHorizontal = axis == .horizontal && alwaysBounce
            
            let verticalInset = scrollView.adjustedContentInset.top + scrollView.adjustedContentInset.bottom
            let horizontalInset = scrollView.adjustedContentInset.left + scrollView.adjustedContentInset.right
            let canScrollVertically = scrollView.contentSize.height + verticalInset > scrollView.bounds.height + 1
            let canScrollHorizontally = scrollView.contentSize.width + horizontalInset > scrollView.bounds.width + 1
            
            scrollView.isScrollEnabled = true
            
            if axis == .horizontal {
                scrollView.bounces = alwaysBounce || canScrollHorizontally
            } else {
                scrollView.bounces = alwaysBounce || canScrollVertically
            }
        }
    }
    
    private extension View {
        func scrollViewTouchTuning(axis: Axis.Set = .vertical, alwaysBounce: Bool = false) -> some View {
            background(ScrollViewTouchTuningView(axis: axis, alwaysBounce: alwaysBounce))
        }
    }
#else
    private extension View {
        func scrollViewTouchTuning(axis: Axis.Set = .vertical, alwaysBounce: Bool = false) -> some View {
            self
        }
    }
#endif
    
    
    // MARK: - For You Section Route Model
    
    private enum ForYouRoute: Hashable {
        case section(ForYouSection)
        case pickForMe
    }

    private struct ForYouSection: Identifiable, Hashable {
        let id = UUID()
        let title: String
        let items: [MediaItem]
    }

    private protocol PickForMeOption: Identifiable, Hashable {
        var title: String { get }
        var subtitle: String? { get }
        var isAnyOption: Bool { get }
    }

    private extension PickForMeOption {
        var subtitle: String? { nil }
        var isAnyOption: Bool { false }
    }

    extension MediaFilter: PickForMeOption {}

    private struct PickForMeAnswers: Hashable {
        var mediaFormat: PickForMeMediaFormat?
        var archetypes: Set<PickForMeArchetype> = []
        var secondaryArchetypes: Set<PickForMeArchetype> = []
        var genrePreferences: Set<PickForMeGenrePreference> = []
        var seriousness: PickForMeSeriousness?
        var realism: PickForMeRealism?
        var sourceMaterial: PickForMeSourceMaterial?
        var actionLevels: Set<PickForMeActionLevel> = []
        var engagement: PickForMeEngagement?
        var recommendationType: PickForMeRecommendationType?
        var runtime: PickForMeRuntime?
        var releaseAge: PickForMeReleaseAge?
        var contentRatings: Set<PickForMeContentRating> = []
        var goreLevel: PickForMeGoreLevel?
        var sexLevel: PickForMeSexLevel?
        var minimumRating: PickForMeMinimumRating?
        var dealBreakers: Set<PickForMeDealBreaker> = []

        var answeredQuestionCount: Int {
            var count = 0
            if mediaFormat != nil { count += 1 }
            if !archetypes.isEmpty { count += 1 }
            if !secondaryArchetypes.isEmpty { count += 1 }
            if !genrePreferences.isEmpty { count += 1 }
            if seriousness != nil { count += 1 }
            if realism != nil { count += 1 }
            if sourceMaterial != nil { count += 1 }
            if !actionLevels.isEmpty { count += 1 }
            if engagement != nil { count += 1 }
            if recommendationType != nil { count += 1 }
            if runtime != nil { count += 1 }
            if releaseAge != nil { count += 1 }
            if !contentRatings.isEmpty { count += 1 }
            if goreLevel != nil { count += 1 }
            if sexLevel != nil { count += 1 }
            if minimumRating != nil { count += 1 }
            if !dealBreakers.isEmpty { count += 1 }
            return count
        }

        var meaningfulQuestionCount: Int {
            var count = 0
            if mediaFormat != nil { count += 1 }
            if !archetypes.isEmpty && !archetypes.contains(.surprise) { count += 1 }
            if !secondaryArchetypes.isEmpty && !secondaryArchetypes.contains(where: \.isAnyOption) { count += 1 }
            if !genrePreferences.isEmpty && !genrePreferences.contains(.noPreference) { count += 1 }
            if let seriousness, seriousness != .noPreference { count += 1 }
            if let realism, realism != .anything { count += 1 }
            if let sourceMaterial, sourceMaterial != .noPreference { count += 1 }
            if !actionLevels.isEmpty && !actionLevels.contains(.noPreference) { count += 1 }
            if let engagement, engagement != .noPreference { count += 1 }
            if let recommendationType, recommendationType != .noPreference { count += 1 }
            if !isSeriesOnly, let runtime, runtime != .any { count += 1 }
            if let releaseAge, releaseAge != .noPreference { count += 1 }
            if !contentRatings.isEmpty && !contentRatings.contains(.any) { count += 1 }
            if let goreLevel, goreLevel != .noPreference { count += 1 }
            if let sexLevel, sexLevel != .noPreference { count += 1 }
            if let minimumRating, minimumRating != .any { count += 1 }
            if !dealBreakers.isEmpty && !dealBreakers.contains(.none) { count += 1 }
            return count
        }

        var effectiveMediaFilter: MediaFilter {
            mediaFormat?.mediaFilter ?? .both
        }

        var isSeriesOnly: Bool {
            mediaFormat == .series
        }

        var shouldAskGoreQuestion: Bool {
            PickForMeContentRating.selectionAllowsGoreQuestion(contentRatings)
        }

        var wantsDocumentary: Bool {
            archetypes.contains(.documentary) || secondaryArchetypes.contains(.documentary)
        }

        var wantsHumanTriumph: Bool {
            archetypes.contains(.humanTriumph) || secondaryArchetypes.contains(.humanTriumph)
        }

        var wantsStrictHistorical: Bool {
            archetypes.contains(.historical) ||
            secondaryArchetypes.contains(.historical)
        }

        var wantsHistoryFlavor: Bool {
            genrePreferences.contains(.history)
        }

        var wantsHistorical: Bool {
            wantsStrictHistorical || wantsHistoryFlavor
        }

        var wantsWar: Bool {
            archetypes.contains(.war) ||
            secondaryArchetypes.contains(.war) ||
            genrePreferences.contains(.war)
        }
    }

    private enum PickForMeStep: CaseIterable {
        case format, archetype, secondaryArchetypes, genrePreferences, seriousness, realism, sourceMaterial, action, engagement, recommendationType, runtime, releaseAge, ageRating, gore, sex, minimumRating, dealBreakers

        static func steps(for answers: PickForMeAnswers) -> [PickForMeStep] {
            var steps: [PickForMeStep] = [
                .format,
                .archetype
            ]

            if !answers.archetypes.contains(.surprise) {
                steps.append(.secondaryArchetypes)
            }

            steps.append(contentsOf: [
                .genrePreferences,
                .seriousness,
                .realism,
                .sourceMaterial,
                .action,
                .engagement,
                .recommendationType
            ])

            if !answers.isSeriesOnly {
                steps.append(.runtime)
            }

            steps.append(contentsOf: [
                .releaseAge,
                .ageRating
            ])

            if answers.shouldAskGoreQuestion {
                steps.append(.gore)
                steps.append(.sex)
            }

            steps.append(contentsOf: [
                .minimumRating,
                .dealBreakers
            ])

            return steps
        }

        var title: String {
            switch self {
            case .format: return "What do you want to watch?"
            case .archetype: return "What are you in the mood for?"
            case .secondaryArchetypes: return "Anything else sound good?"
            case .genrePreferences: return "Any genre flavors you want?"
            case .seriousness: return "How serious should it be?"
            case .realism: return "How realistic should it be?"
            case .sourceMaterial: return "Should it be based on something?"
            case .action: return "How much action do you want?"
            case .engagement: return "How mentally engaging should it be?"
            case .recommendationType: return "What type of recommendation do you want?"
            case .runtime: return "How much time do you have?"
            case .releaseAge: return "How recent should it be?"
            case .ageRating: return "What content rating are you comfortable with?"
            case .gore: return "How much gore do you want?"
            case .sex: return "How much sexual content do you want?"
            case .minimumRating: return "How highly rated should it be?"
            case .dealBreakers: return "Any deal breakers?"
            }
        }

        var subtitle: String? {
            switch self {
            case .format: return "Choose one."
            case .archetype: return "Choose one. Documentary is a strict filter; Historical means stories about historical events."
            case .secondaryArchetypes: return "Choose any number, or choose no preference. Documentary is strict; Historical means stories about historical events."
            case .genrePreferences: return "These are light boosts. History only nudges older true-event stories upward."
            case .seriousness: return "This is a ranking preference, not a strict filter."
            case .realism: return "Real-world only is a strict filter. The other answers are ranking preferences."
            case .sourceMaterial: return "Strict filter. Choose no preference if the source does not matter."
            case .action: return "This is a ranking preference, not a strict filter."
            case .engagement: return "Easy viewing means relaxed. Fully focused means something more demanding."
            case .recommendationType: return "This changes ranking and candidate sources, not a hard filter."
            case .runtime: return "Runtime filters out movies outside the time window you choose."
            case .releaseAge: return "Release age is a strict filter, not a ranking boost."
            case .ageRating: return "This is a maximum rating filter when data is available. Missing data is penalized."
            case .gore: return "This is a ranking preference, not a strict filter."
            case .sex: return "This is a ranking preference, not a strict filter."
            case .minimumRating: return "Strong rating preference. Uses IMDb when available."
            case .dealBreakers: return "Strict filters. Choose none if nothing applies."
            }
        }
    }

    private enum PickForMeMediaFormat: String, CaseIterable, PickForMeOption {
        case movies, series, both

        init(_ filter: MediaFilter) {
            switch filter {
            case .movie:
                self = .movies
            case .tv:
                self = .series
            case .both:
                self = .both
            }
        }

        var id: String { rawValue }
        var title: String {
            switch self {
            case .movies: return "Movies"
            case .series: return "Series"
            case .both: return "Both"
            }
        }
        var isAnyOption: Bool { self == .both }
        var mediaFilter: MediaFilter {
            switch self {
            case .movies: return .movie
            case .series: return .tv
            case .both: return .both
            }
        }
    }

    private enum PickForMeArchetype: String, CaseIterable, PickForMeOption {
        case feelGood, comedy, mystery, thriller, smartProblems, mission, heist, adventure, characterRelationships, humanTriumph, documentary, historical, war, epicSpectacle, mindBending, horror, thoughtfulSciFi, surprise, noPreference
        var id: String { rawValue }
        var title: String {
            switch self {
            case .feelGood: return "Feel-Good"
            case .comedy: return "Comedy"
            case .mystery: return "Mystery"
            case .thriller: return "Thriller"
            case .smartProblems: return "Smart people solving problems"
            case .mission: return "Mission"
            case .heist: return "Heist"
            case .adventure: return "Adventure"
            case .characterRelationships: return "Character and Relationships"
            case .humanTriumph: return "Human Triumph"
            case .documentary: return "Documentary"
            case .historical: return "Historical"
            case .war: return "War"
            case .epicSpectacle: return "Epic / Spectacle"
            case .mindBending: return "Mind-Bending"
            case .horror: return "Horror"
            case .thoughtfulSciFi: return "Thought-Provoking Sci-Fi"
            case .surprise: return "Surprise me"
            case .noPreference: return "No preference"
            }
        }
        var subtitle: String? {
            switch self {
            case .feelGood: return "Uplifting, optimistic, and heartwarming."
            case .comedy: return "Built primarily to make you laugh."
            case .mystery: return "Driven by uncovering hidden information."
            case .thriller: return "Tension, danger, suspense, or pursuit."
            case .smartProblems: return "Experts, teams, investigations, planning, or persistence."
            case .mission: return "A specific objective, operation, rescue, or survival mission."
            case .heist: return "A robbery, con, caper, theft, or elaborate scheme."
            case .adventure: return "Exploration, discovery, and excitement."
            case .characterRelationships: return "Relationships, family dynamics, and personal growth."
            case .humanTriumph: return "Overcoming hurdles, resilience, achievement, or against-the-odds stories."
            case .documentary: return "Nonfiction, real subjects, and factual storytelling."
            case .historical: return "Fiction or nonfiction about a historical event."
            case .war: return "War, combat, military conflict, or wartime survival."
            case .epicSpectacle: return "Scale, visuals, action, and world-building."
            case .mindBending: return "Twists, puzzles, unusual structure, or reality-questioning stories."
            case .horror: return "Fear, dread, terror, or psychological discomfort."
            case .thoughtfulSciFi: return "Idea-driven science fiction, ethics, technology, or consciousness."
            case .surprise: return "Let the app lean on your history and strong ratings."
            case .noPreference: return nil
            }
        }
        var isAnyOption: Bool { self == .surprise || self == .noPreference }
    }

    private enum PickForMeSeriousness: String, CaseIterable, PickForMeOption {
        case lightFun, mostlyFun, balanced, serious, intense, noPreference
        var id: String { rawValue }
        var title: String {
            switch self {
            case .lightFun: return "Light and fun"
            case .mostlyFun: return "Mostly fun"
            case .balanced: return "Balanced"
            case .serious: return "Serious"
            case .intense: return "Intense"
            case .noPreference: return "No preference"
            }
        }
        var isAnyOption: Bool { self == .noPreference }
    }

    private enum PickForMeGenrePreference: String, CaseIterable, PickForMeOption {
        case space, fantasy, sciFi, history, crime, war, romance, animation, family, horror, noPreference
        var id: String { rawValue }
        var title: String {
            switch self {
            case .space: return "Space"
            case .fantasy: return "Fantasy"
            case .sciFi: return "Sci-Fi"
            case .history: return "History"
            case .crime: return "Crime"
            case .war: return "War"
            case .romance: return "Romance"
            case .animation: return "Animation"
            case .family: return "Family"
            case .horror: return "Horror"
            case .noPreference: return "No preference"
            }
        }
        var isAnyOption: Bool { self == .noPreference }
    }

    private enum PickForMeRealism: String, CaseIterable, PickForMeOption {
        case realWorld, mostlyRealistic, someSpeculative, completelyFictional, anything
        var id: String { rawValue }
        var title: String {
            switch self {
            case .realWorld: return "Real-world only"
            case .mostlyRealistic: return "Mostly realistic"
            case .someSpeculative: return "Some sci-fi or fantasy"
            case .completelyFictional: return "Completely fictional"
            case .anything: return "No preference"
            }
        }
        var isAnyOption: Bool { self == .anything }
    }

    private enum PickForMeSourceMaterial: String, CaseIterable, PickForMeOption {
        case trueStory, book, game, noPreference
        var id: String { rawValue }
        var title: String {
            switch self {
            case .trueStory: return "Based on a true story"
            case .book: return "Based on a book"
            case .game: return "Based on a game"
            case .noPreference: return "No preference"
            }
        }
        var isAnyOption: Bool { self == .noPreference }
        var keywordIDs: [Int] {
            switch self {
            case .trueStory: return [9672]
            case .book: return [818]
            case .game: return [41645]
            case .noPreference: return []
            }
        }
    }

    private enum PickForMeActionLevel: String, CaseIterable, PickForMeOption {
        case none, little, moderate, lots, noPreference
        var id: String { rawValue }
        var title: String {
            switch self {
            case .none: return "None"
            case .little: return "A little"
            case .moderate: return "Moderate"
            case .lots: return "Lots"
            case .noPreference: return "No preference"
            }
        }
        var isAnyOption: Bool { self == .noPreference }
    }

    private enum PickForMeEngagement: String, CaseIterable, PickForMeOption {
        case easy, moderate, focused, noPreference
        var id: String { rawValue }
        var title: String {
            switch self {
            case .easy: return "Easy viewing"
            case .moderate: return "Moderately engaging"
            case .focused: return "Fully focused"
            case .noPreference: return "No preference"
            }
        }
        var isAnyOption: Bool { self == .noPreference }
    }

    private enum PickForMeGoreLevel: String, CaseIterable, PickForMeOption {
        case low, some, high, noPreference
        var id: String { rawValue }
        var title: String {
            switch self {
            case .low: return "Low gore"
            case .some: return "Some gore"
            case .high: return "A lot of gore"
            case .noPreference: return "No preference"
            }
        }
        var isAnyOption: Bool { self == .noPreference }
    }

    private enum PickForMeSexLevel: String, CaseIterable, PickForMeOption {
        case low, some, high, noPreference
        var id: String { rawValue }
        var title: String {
            switch self {
            case .low: return "Low sexual content"
            case .some: return "Some sexual content"
            case .high: return "A lot of sexual content"
            case .noPreference: return "No preference"
            }
        }
        var isAnyOption: Bool { self == .noPreference }
    }

    private enum PickForMeRecommendationType: String, CaseIterable, PickForMeOption {
        case crowdPleaser, acclaimed, hiddenGem, noPreference
        var id: String { rawValue }
        var title: String {
            switch self {
            case .crowdPleaser: return "Popular crowd-pleaser"
            case .acclaimed: return "Critically acclaimed"
            case .hiddenGem: return "Hidden gem"
            case .noPreference: return "No preference"
            }
        }
        var isAnyOption: Bool { self == .noPreference }
    }

    private enum PickForMeRuntime: String, CaseIterable, PickForMeOption {
        case underNinety, underTwoHours, underTwoAndHalfHours, any
        var id: String { rawValue }
        var title: String {
            switch self {
            case .underNinety: return "Under 90 minutes"
            case .underTwoHours: return "Under 2 hours"
            case .underTwoAndHalfHours: return "Under 2.5 hours"
            case .any: return "Any length"
            }
        }
        var isAnyOption: Bool { self == .any }
        var minimumMinutes: Int? { nil }
        var maximumMinutes: Int? {
            switch self {
            case .underNinety: return 89
            case .underTwoHours: return 119
            case .underTwoAndHalfHours: return 149
            case .any: return nil
            }
        }
        func contains(_ minutes: Int) -> Bool {
            guard let maximumMinutes else { return true }
            return minutes <= maximumMinutes
        }
    }

    private enum PickForMeReleaseAge: String, CaseIterable, PickForMeOption {
        case newReleases, lastFiveYears, olderThanFiveYears, lastTenYears, olderThanTenYears, lastTwentyFiveYears, olderThanTwentyFiveYears, noPreference
        var id: String { rawValue }
        var title: String {
            switch self {
            case .newReleases: return "New releases"
            case .lastFiveYears: return "Last 5 years"
            case .olderThanFiveYears: return "Older than 5 years"
            case .lastTenYears: return "Last 10 years"
            case .olderThanTenYears: return "Older than 10 years"
            case .lastTwentyFiveYears: return "Last 25 years"
            case .olderThanTwentyFiveYears: return "Older than 25 years"
            case .noPreference: return "No preference"
            }
        }
        var isAnyOption: Bool { self == .noPreference }
        var minimumYearsOld: Int? {
            switch self {
            case .olderThanFiveYears: return 5
            case .olderThanTenYears: return 10
            case .olderThanTwentyFiveYears: return 25
            case .newReleases, .lastFiveYears, .lastTenYears, .lastTwentyFiveYears, .noPreference: return nil
            }
        }
        var maximumYearsOld: Int? {
            switch self {
            case .lastFiveYears: return 5
            case .lastTenYears: return 10
            case .lastTwentyFiveYears: return 25
            case .newReleases, .olderThanFiveYears, .olderThanTenYears, .olderThanTwentyFiveYears, .noPreference: return nil
            }
        }
    }

    private enum PickForMeContentRating: String, CaseIterable, PickForMeOption {
        case g, pg, pg13, r, nc17, any
        var id: String { rawValue }
        var title: String {
            switch self {
            case .g: return "G / U"
            case .pg: return "PG"
            case .pg13: return "PG-13 / 12A"
            case .r: return "R / 15"
            case .nc17: return "NC-17 / 18"
            case .any: return "Any rating"
            }
        }
        var isAnyOption: Bool { self == .any }
        private var maturityRank: Int {
            switch self {
            case .g: return 0
            case .pg: return 1
            case .pg13: return 2
            case .r: return 3
            case .nc17: return 4
            case .any: return Int.max
            }
        }

        static func selectionAllows(_ selection: Set<PickForMeContentRating>, rating rawRating: String) -> Bool {
            guard !selection.contains(.any),
                  let actualRank = rank(for: rawRating),
                  let maximumAllowedRank = selection.map(\.maturityRank).max()
            else {
                return true
            }

            return actualRank <= maximumAllowedRank
        }

        static func selectionAllowsGoreQuestion(_ selection: Set<PickForMeContentRating>) -> Bool {
            selection.contains(.any) || selection.contains(.r) || selection.contains(.nc17)
        }

        private static func rank(for rawRating: String) -> Int? {
            let normalized = rawRating.uppercased().replacingOccurrences(of: "_", with: "-")
            switch normalized {
            case "G", "U", "TV-Y", "TV-G": return 0
            case "PG", "TV-Y7", "TV-PG": return 1
            case "PG-13", "12", "12A", "TV-14": return 2
            case "R", "15", "TV-MA": return 3
            case "NC-17", "18": return 4
            default: return nil
            }
        }
    }

    private enum PickForMeMinimumRating: String, CaseIterable, PickForMeOption {
        case eight, sevenHalf, seven, sixHalf, any
        var id: String { rawValue }
        var title: String {
            switch self {
            case .eight: return "8.0+"
            case .sevenHalf: return "7.5+"
            case .seven: return "7.0+"
            case .sixHalf: return "6.5+"
            case .any: return "Any rating"
            }
        }
        var isAnyOption: Bool { self == .any }
        var minimumRating: Double? {
            switch self {
            case .eight: return 8.0
            case .sevenHalf: return 7.5
            case .seven: return 7.0
            case .sixHalf: return 6.5
            case .any: return nil
            }
        }
    }

    private enum PickForMeDealBreaker: String, CaseIterable, PickForMeOption {
        case horror, romanceHeavy, animation, documentary, war, superhero, verySad, foreignLanguage, longRuntime, none
        var id: String { rawValue }
        var title: String {
            switch self {
            case .horror: return "Horror"
            case .romanceHeavy: return "Romance-heavy"
            case .animation: return "Animation"
            case .documentary: return "Documentary"
            case .war: return "War"
            case .superhero: return "Superhero"
            case .verySad: return "Very sad"
            case .foreignLanguage: return "Foreign language (not English)"
            case .longRuntime: return "Long runtime (180+ minutes)"
            case .none: return "None"
            }
        }
        var isAnyOption: Bool { self == .none }
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
// MARK: - Dynamic Collections Sorting Helper

private extension Array where Element == MediaCollection {
    /// Sorts dynamic collections by item count descending, then name ascending (case-insensitive).
    func sortedDynamicCollections() -> [MediaCollection] {
        self.sorted { lhs, rhs in
            if lhs.itemKeys.count != rhs.itemKeys.count {
                return lhs.itemKeys.count > rhs.itemKeys.count
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
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
    
    private enum ExportFormat: String, CaseIterable, Identifiable {
        case text
        case csv

        var id: String { rawValue }
        var title: String {
            switch self {
            case .text: return ".txt"
            case .csv: return ".csv"
            }
        }
        var separator: String {
            switch self {
            case .text: return "\n"
            case .csv: return ", "
            }
        }
        var contentType: UTType {
            switch self {
            case .text: return .plainText
            case .csv: return .commaSeparatedText
            }
        }
        var filename: String {
            switch self {
            case .text: return "Vestigo Watched"
            case .csv: return "Vestigo Watched CSV"
            }
        }
    }

    private struct ExportDocument: FileDocument {
        static var readableContentTypes: [UTType] { [.plainText, .commaSeparatedText] }
        var text: String
        init(text: String = "") { self.text = text }
        init(configuration: ReadConfiguration) throws { text = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? "" }
        func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
    }
    
    
    
// MARK: - Person Search Result Row
private struct PersonSearchResultRow: View {
    let person: PersonSummary
    @ObservedObject var model: VestigoModel
    var expanded: Bool = false
    var body: some View {
        Button {
            model.selectedPerson = person
        } label: {
            HStack(spacing: expanded ? 16 : 12) {
                PersonImageView(
                    person: person,
                    width: expanded ? 78 : 58,
                    height: expanded ? 96 : 76
                )

                VStack(alignment: .leading, spacing: expanded ? 7 : 5) {
                    Text(person.name)
                        .font(expanded ? .title3.bold() : .headline.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    if let detail = model.personDetails[person.id], let metadata = detail.compactMetadataText {
                        Text(metadata)
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text(person.role.isEmpty ? "Known for" : person.role)
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if expanded, let detail = model.personDetails[person.id], let summary = detail.tinyBiography {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if expanded, let extraPreviewText = person.extraPreviewText {
                        Text(extraPreviewText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, expanded ? 16 : 12)
            .padding(.vertical, expanded ? 16 : 12)
            .liquidGlass(cornerRadius: expanded ? 26 : 22)
        }
        .buttonStyle(.plain)
        .task {
            await model.loadPersonDetailIfNeeded(person)
        }
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
