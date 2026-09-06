import SwiftUI
import Foundation

extension VestigoModel {

    func refreshImages() {
        imageRefreshToken &+= 1
        URLCache.shared.removeAllCachedResponses()
        #if canImport(UIKit)
        ImageCache.shared.clear()
        #endif
    }

    func bootstrap() async {
        URLCache.shared = URLCache(
            memoryCapacity: 50 * 1024 * 1024,
            diskCapacity: 300 * 1024 * 1024
        )

        loadLocal()
        loadFriendsCache()
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

        // Resolve CloudKit record name eagerly so myInviteURL always includes &rid=
        // before the user can open the QR sheet or share a link.
        if settings.socialMyRecordName.isEmpty {
            if let myRecord = await publicSync.getMyRecordName() {
                settings.socialMyRecordName = myRecord
                saveSettings()
            }
        }

        Task {
            await syncFromCloudOnLaunch()
            await loadHome()
        }

        Task {
            await publishPublicProfile()
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

    func saveCurrentHomeFeedCache() {
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
}
