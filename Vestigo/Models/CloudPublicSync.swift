import Foundation
#if canImport(CloudKit)
import CloudKit
#endif

struct CloudPublicSyncService {
    private let publicDB = CKContainer.default().publicCloudDatabase
    private let recordType = "VestigoPublicProfile"

    // MARK: - Publish own profile

    func publishProfile(settings: AppSettings, library: UserLibrary, avatarData: Data? = nil) async -> String {
        #if canImport(CloudKit)
        do {
            let userID = try await CKContainer.default().userRecordID()
            let recordID = CKRecord.ID(recordName: "vp-\(userID.recordName)")

            let record: CKRecord
            do {
                record = try await publicDB.record(for: recordID)
            } catch let err as CKError where err.code == .unknownItem {
                record = CKRecord(recordType: recordType, recordID: recordID)
            }

            record["inviteID"] = settings.socialInviteID as CKRecordValue
            record["displayName"] = settings.name as CKRecordValue
            record["sharesWatchlist"] = (!settings.socialDontShare && settings.socialShareWatchlist) as CKRecordValue
            record["sharesWatched"] = (!settings.socialDontShare && settings.socialShareWatched) as CKRecordValue
            record["favouriteKeys"] = library.favouriteKeys.map { $0.stableID } as CKRecordValue
            record["lastActiveAt"] = Date() as CKRecordValue

            let featuredItems: [MediaItem] = settings.socialFeaturedItemKeys.isEmpty
                ? Array(library.items.values
                    .filter { library.isFavourite($0) }
                    .sorted { $0.voteAverage > $1.voteAverage }
                    .prefix(6))
                : settings.socialFeaturedItemKeys.compactMap { k in
                    library.items.values.first { $0.key.stableID == k }
                }
            let excitedForItems: [MediaItem] = settings.socialExcitedForKeys.compactMap { k in
                library.items.values.first { $0.key.stableID == k }
                    ?? settings.socialExcitedForItemCache.first { $0.key.stableID == k }
            }

            if let data = try? JSONEncoder().encode(featuredItems) {
                record["featuredPayload"] = CKAsset(fileURL: try writeTemp(data, name: "featured"))
            }
            if let data = try? JSONEncoder().encode(excitedForItems) {
                record["excitedForPayload"] = CKAsset(fileURL: try writeTemp(data, name: "excitedFor"))
            }

            var ratingsDict: [String: Double] = [:]
            for item in library.watchedItems {
                if let r = library.ratings[item.key] { ratingsDict[item.key.stableID] = r }
            }
            if !ratingsDict.isEmpty, let data = try? JSONEncoder().encode(ratingsDict) {
                record["ratingsPayload"] = CKAsset(fileURL: try writeTemp(data, name: "ratings"))
            }

            let sharing = !settings.socialDontShare
            if sharing && settings.socialShareWatchlist, let data = try? JSONEncoder().encode(library.watchlistItems) {
                record["watchlistPayload"] = CKAsset(fileURL: try writeTemp(data, name: "watchlist"))
            } else {
                record["watchlistPayload"] = nil as CKAsset?
            }
            if sharing && settings.socialShareWatched {
                let sortedWatched = library.watchedItems.sorted {
                    (library.watchedDates[$0.key] ?? .distantPast) > (library.watchedDates[$1.key] ?? .distantPast)
                }
                if let data = try? JSONEncoder().encode(sortedWatched) {
                    record["watchedPayload"] = CKAsset(fileURL: try writeTemp(data, name: "watched"))
                }
                var datesDict: [String: Double] = [:]
                for item in sortedWatched {
                    if let d = library.watchedDates[item.key] { datesDict[item.key.stableID] = d.timeIntervalSince1970 }
                }
                if !datesDict.isEmpty, let data = try? JSONEncoder().encode(datesDict) {
                    record["watchedDatesPayload"] = CKAsset(fileURL: try writeTemp(data, name: "watchedDates"))
                }
            } else {
                record["watchedPayload"] = nil as CKAsset?
                record["watchedDatesPayload"] = nil as CKAsset?
            }

            if let avatarData {
                record["avatarPayload"] = CKAsset(fileURL: try writeTemp(avatarData, name: "avatar"))
            } else {
                record["avatarPayload"] = nil as CKAsset?
            }

            do {
                _ = try await publicDB.save(record)
                return "publish OK · name: \(settings.name)"
            } catch let err as CKError where err.localizedDescription.contains("production schema") {
                // One or more fields not yet in production schema — strip optional fields and retry
                record["avatarPayload"] = nil as CKAsset?
                record["favouriteKeys"] = nil as [String]?
                record["inviteID"] = nil as String?
                record["ratingsPayload"] = nil as CKAsset?
                record["watchedDatesPayload"] = nil as CKAsset?
                _ = try await publicDB.save(record)
                return "publish OK (schema limited) · name: \(settings.name)"
            }
        } catch {
            return "publish error: \(error.localizedDescription)"
        }
        #else
        return "CloudKit unavailable"
        #endif
    }

    // MARK: - Fetch friends by confirmed record IDs

    func fetchFriends(recordIDs: [String]) async -> ([FriendProfile], String) {
        #if canImport(CloudKit)
        guard !recordIDs.isEmpty else { return ([], "No friends added yet") }

        let ckIDs = recordIDs.map { CKRecord.ID(recordName: $0) }
        var profiles: [FriendProfile] = []

        do {
            let results = try await publicDB.records(for: ckIDs)
            for (_, result) in results {
                guard let record = try? result.get() else { continue }
                if let profile = makeProfile(from: record) {
                    profiles.append(profile)
                }
            }
        } catch {
            return (profiles, "Error: \(error.localizedDescription)")
        }

        let sorted = profiles.sorted { ($0.recentActivity ?? .distantPast) > ($1.recentActivity ?? .distantPast) }
        return (sorted, "\(sorted.count) friends loaded")
        #else
        return ([], "CloudKit unavailable")
        #endif
    }

    // MARK: - Find profile by invite ID (fallback when rid is missing from URL)

    func findProfile(byInviteID inviteID: String) async -> FriendProfile? {
        #if canImport(CloudKit)
        let pred = NSPredicate(format: "inviteID == %@", inviteID)
        let query = CKQuery(recordType: recordType, predicate: pred)
        do {
            let (results, _) = try await publicDB.records(matching: query, resultsLimit: 1)
            for (_, result) in results {
                if let record = try? result.get() { return makeProfile(from: record) }
            }
        } catch { }
        return nil
        #else
        return nil
        #endif
    }

    // MARK: - Send friend request (so the other person auto-adds us)

    func sendFriendRequest(fromRecordName: String, fromDisplayName: String, toRecordName: String) async {
        #if canImport(CloudKit)
        let recordName = "vfr-\(fromRecordName)-\(toRecordName)"
        let recordID = CKRecord.ID(recordName: recordName)
        let record = CKRecord(recordType: "VestigoFriendRequest", recordID: recordID)
        record["fromRecordName"] = fromRecordName as CKRecordValue
        record["fromDisplayName"] = fromDisplayName as CKRecordValue
        record["toRecordName"] = toRecordName as CKRecordValue
        record["createdAt"] = Date() as CKRecordValue
        _ = try? await publicDB.save(record)
        #endif
    }

    // MARK: - Fetch incoming friend requests addressed to this user

    func fetchIncomingRequests(myRecordName: String) async -> [(id: String, name: String, recordName: String)] {
        #if canImport(CloudKit)
        let pred = NSPredicate(format: "toRecordName == %@", myRecordName)
        let query = CKQuery(recordType: "VestigoFriendRequest", predicate: pred)
        var results: [(id: String, name: String, recordName: String)] = []
        do {
            let (matchResults, _) = try await publicDB.records(matching: query)
            for (_, result) in matchResults {
                guard let record = try? result.get() else { continue }
                let fromName = (record["fromDisplayName"] as? String) ?? "Unknown"
                let fromRID = (record["fromRecordName"] as? String) ?? ""
                if !fromRID.isEmpty {
                    results.append((id: record.recordID.recordName, name: fromName, recordName: fromRID))
                }
            }
        } catch {
            // VestigoFriendRequest record type may not exist yet in production schema — silently ignore
        }
        return results
        #else
        return []
        #endif
    }

    // MARK: - Get this user's own CloudKit record name

    func getMyRecordName() async -> String? {
        #if canImport(CloudKit)
        guard let userID = try? await CKContainer.default().userRecordID() else { return nil }
        return "vp-\(userID.recordName)"
        #else
        return nil
        #endif
    }

    // MARK: - Helpers

    #if canImport(CloudKit)
    private func makeProfile(from record: CKRecord) -> FriendProfile? {
        let name = (record["displayName"] as? String) ?? ""
        guard !name.isEmpty else { return nil }

        let sharesWatchlist = (record["sharesWatchlist"] as? Bool) ?? false
        let sharesWatched = (record["sharesWatched"] as? Bool) ?? false
        let lastActiveAt = record["lastActiveAt"] as? Date
        let favouriteKeys = Set((record["favouriteKeys"] as? [String]) ?? [])

        var featuredItems: [MediaItem] = []
        var excitedForItems: [MediaItem] = []
        var watchlistItems: [MediaItem] = []
        var watchedItems: [MediaItem] = []

        if let asset = record["featuredPayload"] as? CKAsset,
           let url = asset.fileURL, let data = try? Data(contentsOf: url) {
            featuredItems = (try? JSONDecoder().decode([MediaItem].self, from: data)) ?? []
        }
        if let asset = record["excitedForPayload"] as? CKAsset,
           let url = asset.fileURL, let data = try? Data(contentsOf: url) {
            excitedForItems = (try? JSONDecoder().decode([MediaItem].self, from: data)) ?? []
        }
        if sharesWatchlist, let asset = record["watchlistPayload"] as? CKAsset,
           let url = asset.fileURL, let data = try? Data(contentsOf: url) {
            watchlistItems = (try? JSONDecoder().decode([MediaItem].self, from: data)) ?? []
        }
        if sharesWatched, let asset = record["watchedPayload"] as? CKAsset,
           let url = asset.fileURL, let data = try? Data(contentsOf: url) {
            watchedItems = (try? JSONDecoder().decode([MediaItem].self, from: data)) ?? []
        }

        var ratingsBySid: [String: Double] = [:]
        if let asset = record["ratingsPayload"] as? CKAsset,
           let url = asset.fileURL, let data = try? Data(contentsOf: url) {
            ratingsBySid = (try? JSONDecoder().decode([String: Double].self, from: data)) ?? [:]
        }
        var ratings: [MediaKey: Double] = [:]
        for item in watchedItems + watchlistItems {
            if let r = ratingsBySid[item.key.stableID] { ratings[item.key] = r }
        }

        var imageData: Data? = nil
        if let asset = record["avatarPayload"] as? CKAsset,
           let url = asset.fileURL {
            imageData = try? Data(contentsOf: url)
        }

        var watchedDates: [String: Date] = [:]
        if let asset = record["watchedDatesPayload"] as? CKAsset,
           let url = asset.fileURL, let data = try? Data(contentsOf: url),
           let rawDates = try? JSONDecoder().decode([String: Double].self, from: data) {
            watchedDates = rawDates.mapValues { Date(timeIntervalSince1970: $0) }
        }

        return FriendProfile(
            id: record.recordID.recordName,
            name: name,
            imageData: imageData,
            recentActivity: lastActiveAt,
            featuredItems: featuredItems,
            excitedForItems: excitedForItems,
            sharesWatchlist: sharesWatchlist,
            sharesWatched: sharesWatched,
            watchlistItems: watchlistItems,
            watchedItems: watchedItems,
            ratings: ratings,
            favouriteKeys: favouriteKeys,
            watchedDates: watchedDates
        )
    }
    #endif

    private func writeTemp(_ data: Data, name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vestigo-pub-\(name)-\(UUID().uuidString).json")
        try data.write(to: url, options: [.atomic])
        return url
    }
}
