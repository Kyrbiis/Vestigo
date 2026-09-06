import SwiftUI
import Foundation

enum FranchiseDetailMode: String, CaseIterable, Identifiable, Hashable {
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

struct FranchiseDetailView: View {
    let franchise: FranchiseCollection
    @ObservedObject var model: VestigoModel
    @State private var sort: SortOption = .tmdbRating
    @State private var sortDirection: SortDirection = .descending
    @State private var mode: FranchiseDetailMode = .watched
    @State private var universeMediaFilter: MediaFilter = .both
    @State private var backendRecommendations: [MediaItem] = []
    @State private var backendRecommendationError: String?
    @State private var isLoadingBackendRecommendations = true
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
            ratingSource: model.settings.preferredRatingSource,
            direction: sortDirection
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
            ratingSource: model.settings.preferredRatingSource,
            direction: sortDirection
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
            ratingSource: model.settings.preferredRatingSource,
            direction: sortDirection
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

                SortRow(direction: $sortDirection) {
                    SortPicker(sort: $sort, includeMyRating: mode == .watched, ratingSource: model.settings.preferredRatingSource)
                        .onChange(of: mode) { _, newMode in
                            if newMode == .recommended && sort == .myRating {
                                sort = .tmdbRating
                            }
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
                results = try await backendClient.exactFranchiseRecommendations(id: franchise.id, matching: franchise.tvdbListQuery)
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
