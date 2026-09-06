import SwiftUI
import Foundation

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
