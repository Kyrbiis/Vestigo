import SwiftUI
import Foundation

extension VestigoModel {

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
            if settings.autoTrackWatchDate { library.setWatchedDateIfUnset(for: item.key) }
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
        pendingRatingPromptDate = library.watchedDates[item.key]
        pendingRatingPromptMakeFavourite = library.isFavourite(item)
        pendingRatingPromptRestoreWatchlist = restoreWatchlistOnCancel
    }

    func confirmPendingRatingPrompt() {
        guard let item = pendingRatingPromptItem else { return }
        let shouldMakeFavourite = pendingRatingPromptMakeFavourite

        setRating(pendingRatingPromptValue, for: item)
        if let date = pendingRatingPromptDate {
            setWatchedDate(date, for: item)
        }
        pendingRatingPromptItem = nil
        pendingRatingPromptValue = 0
        pendingRatingPromptDate = nil
        pendingRatingPromptMakeFavourite = false
        pendingRatingPromptRestoreWatchlist = false

        if shouldMakeFavourite, !library.isFavourite(item) {
            requestToggleFavourite(item)
        } else if !shouldMakeFavourite, library.isFavourite(item) {
            requestToggleFavourite(item)
        }
    }

    func dismissPendingRatingPrompt() {
        if let item = pendingRatingPromptItem {
            withdrawPendingRatingPromptWatchedStatus(for: item)
        }

        pendingRatingPromptItem = nil
        pendingRatingPromptValue = 0
        pendingRatingPromptDate = nil
        pendingRatingPromptMakeFavourite = false
        pendingRatingPromptRestoreWatchlist = false
    }

    func withdrawPendingRatingPromptWatchedStatus(for item: MediaItem) {
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

    func removeFromForYouRecommendations(_ item: MediaItem) {
        recommendations.removeAll { $0.key == item.key }
        moreLikeLastWatched.removeAll { $0.key == item.key }
        moreLikeFavourite.removeAll { $0.key == item.key }
        fromTopGenre.removeAll { $0.key == item.key }
        trySomethingNewRecommendations.removeAll { $0.key == item.key }
        seriesNext.removeAll { $0.key == item.key }
    }

    func removeFromCollectionRecommendations(_ item: MediaItem) {
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

}
