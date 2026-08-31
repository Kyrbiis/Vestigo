import Foundation
import CryptoKit
#if canImport(CloudKit)
import CloudKit
#endif
#if canImport(Contacts)
import Contacts
#endif

struct CloudPublicSyncService {
    private let publicDB = CKContainer.default().publicCloudDatabase
    private let recordType = "VestigoPublicProfile"

    // MARK: - Publish own profile

    func publishProfile(settings: AppSettings, library: UserLibrary) async {
        #if canImport(CloudKit)
        do {
            let userID = try await CKContainer.default().userRecordID()
            let recordID = CKRecord.ID(recordName: userID.recordName)

            let record: CKRecord
            do {
                record = try await publicDB.record(for: recordID)
            } catch let err as CKError where err.code == .unknownItem {
                record = CKRecord(recordType: recordType, recordID: recordID)
            }

            let (phoneHashes, emailHashes) = await myContactHashes()
            record["phoneHashes"] = phoneHashes as CKRecordValue
            record["emailHashes"] = emailHashes as CKRecordValue
            record["displayName"] = settings.name as CKRecordValue
            record["sharesWatchlist"] = (!settings.socialDontShare && settings.socialShareWatchlist) as CKRecordValue
            record["sharesWatched"] = (!settings.socialDontShare && settings.socialShareWatched) as CKRecordValue
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
            }

            if let data = try? JSONEncoder().encode(featuredItems) {
                record["featuredPayload"] = CKAsset(fileURL: try writeTemp(data, name: "featured"))
            }
            if let data = try? JSONEncoder().encode(excitedForItems) {
                record["excitedForPayload"] = CKAsset(fileURL: try writeTemp(data, name: "excitedFor"))
            }

            let sharing = !settings.socialDontShare
            if sharing && settings.socialShareWatchlist, let data = try? JSONEncoder().encode(library.watchlistItems) {
                record["watchlistPayload"] = CKAsset(fileURL: try writeTemp(data, name: "watchlist"))
            } else {
                record["watchlistPayload"] = nil as CKAsset?
            }
            if sharing && settings.socialShareWatched, let data = try? JSONEncoder().encode(library.watchedItems) {
                record["watchedPayload"] = CKAsset(fileURL: try writeTemp(data, name: "watched"))
            } else {
                record["watchedPayload"] = nil as CKAsset?
            }

            _ = try await publicDB.save(record)
        } catch {
            // Non-critical — ignore silently
        }
        #endif
    }

    // MARK: - Discover friends

    func fetchFriends(contacts: [CNContact]) async -> [FriendProfile] {
        #if canImport(CloudKit) && canImport(Contacts)
        guard !contacts.isEmpty else { return [] }

        var hashToContact: [String: CNContact] = [:]
        for contact in contacts {
            for phone in contact.phoneNumbers {
                let h = sha256(normalizePhone(phone.value.stringValue))
                if !h.isEmpty { hashToContact[h] = contact }
            }
            for email in contact.emailAddresses {
                let h = sha256(normalizeEmail(email.value as String))
                if !h.isEmpty { hashToContact[h] = contact }
            }
        }
        guard !hashToContact.isEmpty else { return [] }

        let allHashes = Array(hashToContact.keys)
        var fetchedRecords: [CKRecord] = []

        // Batch into groups of 30 hashes, run concurrently
        await withTaskGroup(of: [CKRecord].self) { group in
            let batchSize = 30
            for i in stride(from: 0, to: allHashes.count, by: batchSize) {
                let batch = Array(allHashes[i..<min(i + batchSize, allHashes.count)])
                group.addTask {
                    var records: [CKRecord] = []
                    let preds = batch.flatMap { h in [
                        NSPredicate(format: "phoneHashes CONTAINS %@", h),
                        NSPredicate(format: "emailHashes CONTAINS %@", h)
                    ]}
                    let compound = NSCompoundPredicate(orPredicateWithSubpredicates: preds)
                    do {
                        let query = CKQuery(recordType: self.recordType, predicate: compound)
                        let (results, _) = try await self.publicDB.records(matching: query)
                        for (_, result) in results {
                            if let record = try? result.get() { records.append(record) }
                        }
                    } catch { }
                    return records
                }
            }
            for await records in group { fetchedRecords += records }
        }

        // Deduplicate by record ID
        var seenIDs = Set<String>()
        fetchedRecords = fetchedRecords.filter { seenIDs.insert($0.recordID.recordName).inserted }

        var profiles: [FriendProfile] = []
        for record in fetchedRecords {
            let name = (record["displayName"] as? String) ?? ""
            let sharesWatchlist = (record["sharesWatchlist"] as? Bool) ?? false
            let sharesWatched = (record["sharesWatched"] as? Bool) ?? false
            let lastActiveAt = record["lastActiveAt"] as? Date

            let phoneHashes = (record["phoneHashes"] as? [String]) ?? []
            let emailHashes = (record["emailHashes"] as? [String]) ?? []
            var matchedContact: CNContact? = nil
            for h in phoneHashes + emailHashes {
                if let c = hashToContact[h] { matchedContact = c; break }
            }

            let displayName: String
            if !name.isEmpty {
                displayName = name
            } else if let c = matchedContact,
                      let formatted = CNContactFormatter.string(from: c, style: .fullName),
                      !formatted.isEmpty {
                displayName = formatted
            } else {
                continue
            }

            let imageData = matchedContact.flatMap { c in
                c.isKeyAvailable(CNContactImageDataKey) ? c.imageData : nil
            }

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

            profiles.append(FriendProfile(
                id: record.recordID.recordName,
                name: displayName,
                imageData: imageData,
                recentActivity: lastActiveAt,
                featuredItems: featuredItems,
                excitedForItems: excitedForItems,
                sharesWatchlist: sharesWatchlist,
                sharesWatched: sharesWatched,
                watchlistItems: watchlistItems,
                watchedItems: watchedItems
            ))
        }

        return profiles.sorted { ($0.recentActivity ?? .distantPast) > ($1.recentActivity ?? .distantPast) }
        #else
        return []
        #endif
    }

    // MARK: - Helpers

    private func myContactHashes() async -> ([String], [String]) {
        #if canImport(Contacts)
        guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else { return ([], []) }
        guard let me = try? CNContactStore().unifiedMeContactWithKeysToFetch([
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor
        ]) else { return ([], []) }
        let phones = me.phoneNumbers.map { sha256(normalizePhone($0.value.stringValue)) }.filter { !$0.isEmpty }
        let emails = me.emailAddresses.map { sha256(normalizeEmail($0.value as String)) }.filter { !$0.isEmpty }
        return (phones, emails)
        #else
        return ([], [])
        #endif
    }

    private func sha256(_ input: String) -> String {
        guard !input.isEmpty else { return "" }
        return SHA256.hash(data: Data(input.utf8)).compactMap { String(format: "%02x", $0) }.joined()
    }

    private func normalizePhone(_ phone: String) -> String { phone.filter(\.isNumber) }
    private func normalizeEmail(_ email: String) -> String { email.lowercased().trimmingCharacters(in: .whitespaces) }

    private func writeTemp(_ data: Data, name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vestigo-pub-\(name)-\(UUID().uuidString).json")
        try data.write(to: url, options: [.atomic])
        return url
    }
}
