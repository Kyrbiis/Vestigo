import Foundation
#if canImport(CloudKit)
import CloudKit

struct CloudLibrarySyncService {
    private let database = CKContainer.default().privateCloudDatabase
    private let recordID = CKRecord.ID(recordName: "vestigo-user-snapshot")
    private let recordType = "VestigoUserSnapshot"
    private let payloadKey = "payload"
    private let modifiedAtKey = "modifiedAt"

    func fetchSnapshot() async throws -> CloudLibrarySnapshot? {
        do {
            let record = try await database.record(for: recordID)
            guard let asset = record[payloadKey] as? CKAsset,
                  let fileURL = asset.fileURL else { return nil }
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(CloudLibrarySnapshot.self, from: data)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    func saveSnapshot(_ snapshot: CloudLibrarySnapshot) async throws {
        let record: CKRecord
        do {
            record = try await database.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: recordType, recordID: recordID)
        }
        let payloadURL = try temporaryPayloadURL(for: snapshot)
        record[payloadKey] = CKAsset(fileURL: payloadURL)
        record[modifiedAtKey] = snapshot.modifiedAt as CKRecordValue
        _ = try await database.save(record)
    }

    private func temporaryPayloadURL(for snapshot: CloudLibrarySnapshot) throws -> URL {
        let data = try JSONEncoder().encode(snapshot)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vestigo-cloud-snapshot-\(UUID().uuidString)")
            .appendingPathExtension("json")
        try data.write(to: url, options: [.atomic])
        return url
    }
}
#else
struct CloudLibrarySyncService {
    func fetchSnapshot() async throws -> CloudLibrarySnapshot? { nil }
    func saveSnapshot(_ snapshot: CloudLibrarySnapshot) async throws { }
}
#endif
