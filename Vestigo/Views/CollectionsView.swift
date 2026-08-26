import SwiftUI
import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(WebKit)
import WebKit
#endif
#if canImport(UserNotifications)
import UserNotifications
#endif

// MARK: - Collections
// Franchises use a dedicated pushed screen from Collections.
// TVDB wiring should stay out of this file; use app configuration or a secure API layer for the API key.

struct CollectionsView: View {
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

struct FavouritesCollectionView: View {
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
enum FranchiseCollectionScreenMode {
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

struct FranchiseCollectionsView: View {
    let screenMode: FranchiseCollectionScreenMode
    @ObservedObject var model: VestigoModel
    @State private var selectedFranchise: FranchiseCollection?
    @State private var tvdbFranchises: [String: TVDBFranchiseList] = [:]
    @State private var tmdbCollectionFranchises: [FranchiseCollection] = []
    @State private var exactProviderFranchises: [FranchiseCollection] = []
    @State private var tvdbLoadError: String?
    @State private var isLoadingFranchises = false
    private let backendClient = VestigoBackendClient()

    private var activeFranchiseSourceItems: [MediaItem] {
        (model.library.watchedItems + model.library.watchlistItems)
            .uniqued()
            .filter(\.shouldShowInDiscovery)
    }

    private var franchises: [FranchiseCollection] {
        let discoveredIDs = Set((tmdbCollectionFranchises + exactProviderFranchises).map(\.id))
        let seeded = FranchiseLibrary.defaultFranchises(
            matching: activeFranchiseSourceItems,
            tvdbLists: tvdbFranchises
        )
        .filter { !discoveredIDs.contains($0.id) }

        return (tmdbCollectionFranchises + exactProviderFranchises + seeded)
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
                        if isLoadingFranchises {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        } else {
                            StatusBubble(
                                title: screenMode.emptyTitle,
                                text: screenMode.emptyText
                            )
                        }
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
                        if isLoadingFranchises {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        } else {
                            StatusBubble(
                                title: screenMode.emptyTitle,
                                text: screenMode.emptyText
                            )
                        }
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
                        if isLoadingFranchises {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        } else {
                            StatusBubble(
                                title: screenMode.emptyTitle,
                                text: screenMode.emptyText
                            )
                        }
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
            isLoadingFranchises = true
            async let tmdb: () = loadDiscoveredTMDbCollections()
            async let provider: () = loadExactProviderFranchises()
            async let tvdb: () = loadTVDBFranchises()
            _ = await (tmdb, provider, tvdb)
            isLoadingFranchises = false
        }
    }

    private func loadExactProviderFranchises() async {
        var collectionsByMembership: [String: FranchiseCollection] = [:]

        // Tasks fetch network data only; @MainActor property accesses stay in the for-await body
        await withTaskGroup(of: (MediaItem, [MediaItem])?.self) { group in
            for item in activeFranchiseSourceItems {
                group.addTask {
                    guard let raw = try? await self.backendClient.exactFranchiseRecommendations(
                        id: "\(item.kind.rawValue)-\(item.id)",
                        matching: item.title
                    ).uniqued() else { return nil }
                    return (item, raw)
                }
            }

            // for-await runs on the caller's actor (@MainActor for SwiftUI task), so
            // shouldShowInDiscovery, posterURL, tmdbPath, and FranchiseCollection init are all safe here
            for await result in group {
                guard let (item, rawItems) = result else { continue }
                let items = rawItems.filter(\.shouldShowInDiscovery)
                guard items.count >= 2 else { continue }

                let collection = FranchiseCollection(
                    id: "provider-franchise-\(item.key.stableID)",
                    title: item.title,
                    logoSystemName: item.kind == .tv ? "tv" : "film.stack",
                    logoURL: items.first(where: { $0.posterURL != nil })?.posterURL ?? item.posterURL,
                    aliases: [],
                    description: "Provider-backed franchise discovered from your library.",
                    tvdbListQuery: item.title,
                    tmdbCollectionID: nil,
                    exactMemberIDs: Set(items.map { "\($0.kind.tmdbPath)-\($0.id)" })
                )

                let membershipKey = collection.exactMemberIDs.sorted().joined(separator: "|")
                guard !membershipKey.isEmpty else { continue }

                if let existing = collectionsByMembership[membershipKey] {
                    if collection.title.count < existing.title.count {
                        collectionsByMembership[membershipKey] = collection
                    }
                } else {
                    collectionsByMembership[membershipKey] = collection
                }
            }
        }

        await MainActor.run {
            exactProviderFranchises = collectionsByMembership.values.sorted { lhs, rhs in
                lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }
    }

    private func loadTVDBFranchises() async {
        do {
            let loaded = try await withThrowingTaskGroup(of: (String, TVDBFranchiseList?).self) { group in
                for franchise in FranchiseLibrary.seedFranchises {
                    group.addTask {
                        let list = try await self.backendClient.franchiseList(id: franchise.id, matching: franchise.tvdbListQuery)
                        return (franchise.id, list)
                    }
                }
                var result: [String: TVDBFranchiseList] = [:]
                for try await (id, list) in group {
                    if let list { result[id] = list }
                }
                return result
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

        await withTaskGroup(of: BackendTMDbCollectionDTO?.self) { group in
            for item in movieItems {
                group.addTask { try? await self.backendClient.tmdbCollection(for: item) }
            }
            for await collection in group {
                if let collection { collectionsByID[collection.id] = collection }
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

struct FranchiseCollectionRow: View {
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

// CollectionDetailMode enum for CollectionDetailView
enum CollectionDetailMode: String, CaseIterable, Identifiable, Hashable {
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

struct CollectionDetailView: View {
    let collectionID: UUID
    @ObservedObject var model: VestigoModel
    @State private var sort: SortOption = .tmdbRating
    @State private var sortDirection: SortDirection = .descending
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
            ratingSource: model.settings.preferredRatingSource,
            direction: sortDirection
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
                ratingSource: model.settings.preferredRatingSource,
                direction: sortDirection
            )
    }
    
    var body: some View {
        BaseScreen(title: collection?.name ?? "Collection", filter: .constant(.both), settings: model.settings, onRefresh: {
            await model.loadCollectionRecommendations(for: collectionID)
            await model.loadExternalRatings(for: items + recommendedItems, limit: 120)
        }) {
            VStack(spacing: 14) {
                SortRow(direction: $sortDirection) {
                    SortPicker(sort: $sort, includeMyRating: mode != .recommended, ratingSource: model.settings.preferredRatingSource)
                        .onChange(of: mode) { _, newMode in
                            if newMode == .recommended && sort == .myRating {
                                sort = .tmdbRating
                            }
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

struct CollectionDetailModePicker: View {
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

