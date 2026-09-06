import SwiftUI
import Foundation

extension VestigoModel {

    func checkIncomingFriendRequests() async {
        guard Date().timeIntervalSince(lastIncomingCheck) > 60 else { return }
        lastIncomingCheck = Date()
        guard !settings.socialMyRecordName.isEmpty else {
            logLink("checkIncoming: skipped — myRecordName is empty")
            return
        }
        let myRIDSuffix = String(settings.socialMyRecordName.suffix(8))
        logLink("checkIncoming: querying for myRID=…\(myRIDSuffix)")
        let (incoming, fetchError) = await publicSync.fetchIncomingRequests(myRecordName: settings.socialMyRecordName)
        if let err = fetchError {
            logLink("checkIncoming: fetch error — \(err)")
            return
        }
        logLink("checkIncoming: found \(incoming.count) request(s)")
        var newFriendIDs: [String] = []
        for req in incoming {
            if settings.socialProcessedRequestIDs.contains(req.id) {
                // Already processed this specific request record — skip regardless of current friend status
            } else if settings.socialConfirmedFriendIDs.contains(req.recordName) {
                logLink("checkIncoming: already friend \(req.name), marking request processed")
                settings.socialProcessedRequestIDs.append(req.id)
            } else {
                logLink("checkIncoming: adding \(req.name)")
                settings.socialConfirmedFriendIDs.append(req.recordName)
                settings.socialProcessedRequestIDs.append(req.id)
                newFriendIDs.append(req.recordName)
            }
        }
        // Prevent unbounded growth from request spam — keep only the most recent 500 processed IDs
        if settings.socialProcessedRequestIDs.count > 500 {
            settings.socialProcessedRequestIDs = Array(settings.socialProcessedRequestIDs.suffix(500))
        }
        if !newFriendIDs.isEmpty {
            saveSettings()
            await loadFriends()
            for friendID in newFriendIDs {
                let result = await publicSync.sendFriendRequest(
                    fromRecordName: settings.socialMyRecordName,
                    fromDisplayName: settings.name,
                    toRecordName: friendID
                )
                logLink("checkIncoming: reciprocal request → \(result)")
            }
        }
    }

    func loadFriends() async {
        friendsLoading = true
        await checkRemovalNotices()
        let (profiles, diagnostic) = await publicSync.fetchFriends(recordIDs: settings.socialConfirmedFriendIDs)
        friends = profiles
        friendsDiagnostic = diagnostic
        friendsLoading = false
        if !profiles.isEmpty { saveFriendsCache() }
        // Prune stored IDs that returned no record (stale adds from old broken links)
        let resolvedIDs = Set(profiles.map(\.id))
        let pruned = settings.socialConfirmedFriendIDs.filter { resolvedIDs.contains($0) || $0.hasPrefix("vp-") }
        if pruned.count != settings.socialConfirmedFriendIDs.count {
            settings.socialConfirmedFriendIDs = pruned
            saveSettings()
        }
    }

    func handleFriendLink(inviteID: String, recordID: String? = nil, displayName: String? = nil) async {
        logLink("handleFriendLink: inviteID=\(inviteID) rid=\(recordID ?? "nil") myRID=\(settings.socialMyRecordName.isEmpty ? "EMPTY" : settings.socialMyRecordName.suffix(8))")
        if let rid = recordID, !rid.isEmpty {
            let name = displayName?.isEmpty == false ? displayName! : "this person"
            logLink("handleFriendLink: fast path → setPendingAdd name=\(name)")
            await MainActor.run {
                pendingFriendAdd = PendingFriendAdd(id: rid, name: name)
                selectTab(.friends)
            }
        } else {
            logLink("handleFriendLink: fallback path — querying CloudKit for inviteID")
            var profile = await publicSync.findProfile(byInviteID: inviteID)
            if profile == nil {
                logLink("handleFriendLink: first query returned nil, retrying in 2s")
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                profile = await publicSync.findProfile(byInviteID: inviteID)
            }
            if let profile {
                logLink("handleFriendLink: fallback found profile name=\(profile.name)")
                await MainActor.run {
                    pendingFriendAdd = PendingFriendAdd(id: profile.id, name: profile.name)
                    selectTab(.friends)
                }
            } else {
                logLink("handleFriendLink: fallback — no profile found after retry")
            }
        }
    }

    func addFriend(recordID: String) {
        guard !settings.socialConfirmedFriendIDs.contains(recordID) else {
            pendingFriendAdd = nil
            return
        }
        settings.socialConfirmedFriendIDs.append(recordID)
        saveSettings()
        pendingFriendAdd = nil
        // Refresh list immediately; notify the other person in parallel
        Task { await loadFriends() }
        Task {
            if !settings.socialMyRecordName.isEmpty {
                let result = await publicSync.sendFriendRequest(
                    fromRecordName: settings.socialMyRecordName,
                    fromDisplayName: settings.name,
                    toRecordName: recordID
                )
                logLink("addFriend: sendFriendRequest → \(result)")
            } else {
                logLink("addFriend: skipped sendFriendRequest — myRecordName empty")
            }
        }
    }

    func removeFriend(recordID: String) {
        settings.socialConfirmedFriendIDs.removeAll { $0 == recordID }
        friends.removeAll { $0.id == recordID }
        saveSettings()
        Task { await loadFriends() }
        guard !settings.socialMyRecordName.isEmpty else { return }
        let myName = settings.name
        let myRecord = settings.socialMyRecordName
        Task {
            await publicSync.sendRemovalNotice(
                fromRecordName: myRecord,
                fromDisplayName: myName,
                toRecordName: recordID
            )
        }
    }

    func checkRemovalNotices() async {
        guard !settings.socialMyRecordName.isEmpty else { return }
        let (notices, _) = await publicSync.fetchRemovalNotices(myRecordName: settings.socialMyRecordName)
        var newRemovals: [String] = []
        for notice in notices {
            guard !settings.socialProcessedRemovalIDs.contains(notice.id) else { continue }
            settings.socialProcessedRemovalIDs.append(notice.id)
            if settings.socialConfirmedFriendIDs.contains(notice.recordName) {
                settings.socialConfirmedFriendIDs.removeAll { $0 == notice.recordName }
                friends.removeAll { $0.id == notice.recordName }
                newRemovals.append(notice.name)
            }
        }
        if settings.socialProcessedRemovalIDs.count > 500 {
            settings.socialProcessedRemovalIDs = Array(settings.socialProcessedRemovalIDs.suffix(500))
        }
        if !newRemovals.isEmpty {
            saveSettings()
            pendingRemovalNames.append(contentsOf: newRemovals)
        }
    }

    func refreshFriend(recordID: String) async -> FriendProfile? {
        let (profiles, _) = await publicSync.fetchFriends(recordIDs: [recordID])
        if let updated = profiles.first, let idx = friends.firstIndex(where: { $0.id == recordID }) {
            friends[idx] = updated
        }
        return profiles.first
    }

    func scheduleRecommendationsRefresh() {
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

    func thematicSearch(query: String, filter: MediaFilter) async throws -> [ThematicSearchResult] {
        let service = ThematicSearchService(tmdb: tmdb)
        return try await service.search(rawQuery: query, filter: filter)
    }

}
