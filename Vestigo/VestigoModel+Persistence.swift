import SwiftUI
import Foundation

extension VestigoModel {

    func loadLocal() {
        library = Storage.load(UserLibrary.self, key: "Vestigo.library") ?? UserLibrary()
        settings = Storage.load(AppSettings.self, key: "Vestigo.settings") ?? AppSettings()
        externalRatingsCache = Storage.load([MediaKey: ExternalRatings].self, key: "Vestigo.externalRatings") ?? [:]
        calendarEventIDs = Storage.load([MediaKey: String].self, key: "Vestigo.calendarEventIDs") ?? [:]
        describeItResultsCache = Storage.load([String: [ThematicSearchResult]].self, key: "Vestigo.describeItCache") ?? [:]
        providerCache = Storage.load([MediaKey: [StreamingOption]].self, key: "Vestigo.providerCache") ?? [:]

        // Stamp any watched items that predate date tracking with today's date (idempotent).
        for key in library.watched { library.setWatchedDateIfUnset(for: key) }

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

    func syncFromCloudOnLaunch() async {
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

    func offerStreamingSetupIfNeeded() {
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

    func schedulePublicProfilePublish() {
        publishTask?.cancel()
        publishTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let self else { return }
            let result = await self.publicSync.publishProfile(settings: self.settings, library: self.library, avatarData: self.userAvatarData)
            await MainActor.run { self.publishDiagnostic = result }
        }
    }

    func publishPublicProfile() async {
        // Get record name first (fast, cached CloudKit user ID) so myInviteURL
        // has &rid= before the slow CKRecord upload begins.
        if let myRecord = await publicSync.getMyRecordName(), settings.socialMyRecordName != myRecord {
            settings.socialMyRecordName = myRecord
            saveSettings()
        }
        let diagnostic = await publicSync.publishProfile(settings: settings, library: library, avatarData: userAvatarData)
        publishDiagnostic = diagnostic
    }

    func saveLocalSoon() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            await MainActor.run { self?.saveLocal() }
        }
    }

    func saveLocal() {
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

    func applyKVSnapshot(_ snapshot: KVLibrarySnapshot) {
        guard !isApplyingCloudSnapshot else { return }
        isApplyingCloudSnapshot = true
        defer { isApplyingCloudSnapshot = false }
        library = snapshot.library
        settings = snapshot.settings
        searchFilter = settings.defaultSearchFilter
        mediaFilter = settings.defaultHomeFilter
        saveLocal()
    }

    func loadFriendsCache() {
        guard let data = try? Data(contentsOf: friendsCacheURL),
              let cached = try? JSONDecoder().decode([FriendProfile].self, from: data),
              !cached.isEmpty else { return }
        friends = cached
    }

    func saveFriendsCache() {
        guard !friends.isEmpty,
              let data = try? JSONEncoder().encode(friends) else { return }
        try? data.write(to: friendsCacheURL, options: .atomic)
    }

}
