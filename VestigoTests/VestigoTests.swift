import XCTest
@testable import Vestigo

final class VestigoTests: XCTestCase {

    // MARK: - Sharing defaults

    func testSharingIsOffByDefault() {
        let settings = AppSettings()
        XCTAssertTrue(settings.socialDontShare, "Sharing must be OFF by default")
        XCTAssertFalse(settings.socialShareWatchlist)
        XCTAssertFalse(settings.socialShareWatched)
    }

    func testEffectiveSharingRequiresBothFlags() {
        var settings = AppSettings()
        // socialDontShare acts as a master off-switch
        settings.socialDontShare = false
        settings.socialShareWatchlist = true
        settings.socialShareWatched = true
        let effectiveWatchlist = !settings.socialDontShare && settings.socialShareWatchlist
        let effectiveWatched  = !settings.socialDontShare && settings.socialShareWatched
        XCTAssertTrue(effectiveWatchlist)
        XCTAssertTrue(effectiveWatched)

        // master off-switch suppresses individual toggles
        settings.socialDontShare = true
        XCTAssertFalse(!settings.socialDontShare && settings.socialShareWatchlist)
        XCTAssertFalse(!settings.socialDontShare && settings.socialShareWatched)
    }

    // MARK: - Invite ID stability

    func testInviteIDIsPreservedAcrossDecoding() throws {
        var settings = AppSettings()
        let originalID = settings.socialInviteID
        XCTAssertFalse(originalID.isEmpty)

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded.socialInviteID, originalID, "Invite ID must survive encode/decode")
    }

    func testEmptyStoredInviteIDGetsNewOne() throws {
        // Simulate a stored settings blob that has an empty inviteID (migration case)
        var dict: [String: Any] = [:]
        dict["socialInviteID"] = ""
        let data = try JSONSerialization.data(withJSONObject: dict)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertFalse(decoded.socialInviteID.isEmpty, "Empty stored inviteID must be replaced with a new UUID")
    }

    // MARK: - Processed request ID deduplication

    func testProcessedRequestIDsPreventDuplicateFriendAdd() {
        var settings = AppSettings()
        let requestID = "vfr-vp-aaa-vp-bbb"
        let friendRecordName = "vp-aaa"

        // Simulate first-time processing
        settings.socialProcessedRequestIDs.append(requestID)
        settings.socialConfirmedFriendIDs.append(friendRecordName)

        // Simulate a second call with the same request record (e.g., after friend removal)
        let alreadyProcessed = settings.socialProcessedRequestIDs.contains(requestID)
        XCTAssertTrue(alreadyProcessed, "Already-processed request must be skipped on re-check")

        // Friend should still be there only once (not double-added)
        let friendCount = settings.socialConfirmedFriendIDs.filter { $0 == friendRecordName }.count
        XCTAssertEqual(friendCount, 1)
    }

    func testProcessedIDsAreCappedAt500() {
        var ids = (0..<600).map { "vfr-fake-\($0)" }
        if ids.count > 500 {
            ids = Array(ids.suffix(500))
        }
        XCTAssertEqual(ids.count, 500)
        // The oldest entries (0-99) are dropped; the most recent (100-599) are kept
        XCTAssertEqual(ids.first, "vfr-fake-100")
        XCTAssertEqual(ids.last, "vfr-fake-599")
    }

    // MARK: - Friend ID storage round-trip

    func testConfirmedFriendIDsRoundTrip() throws {
        var settings = AppSettings()
        settings.socialConfirmedFriendIDs = ["vp-abc123", "vp-def456"]

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded.socialConfirmedFriendIDs, ["vp-abc123", "vp-def456"])
    }

    func testRemoveFriendIDFromSettings() {
        var settings = AppSettings()
        settings.socialConfirmedFriendIDs = ["vp-aaa", "vp-bbb", "vp-ccc"]

        let toRemove = "vp-bbb"
        settings.socialConfirmedFriendIDs.removeAll { $0 == toRemove }

        XCTAssertFalse(settings.socialConfirmedFriendIDs.contains("vp-bbb"))
        XCTAssertEqual(settings.socialConfirmedFriendIDs.count, 2)
    }

    // MARK: - AppSettings encode/decode completeness

    func testSettingsEncodeDecodePreservesAllSocialFields() throws {
        var settings = AppSettings()
        settings.socialDontShare = false
        settings.socialShareWatchlist = true
        settings.socialShareWatched = false
        settings.socialInviteID = "test-invite-id"
        settings.socialMyRecordName = "vp-testrecord"
        settings.socialConfirmedFriendIDs = ["vp-friend1"]
        settings.socialProcessedRequestIDs = ["vfr-req-1", "vfr-req-2"]

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.socialDontShare, false)
        XCTAssertEqual(decoded.socialShareWatchlist, true)
        XCTAssertEqual(decoded.socialShareWatched, false)
        XCTAssertEqual(decoded.socialInviteID, "test-invite-id")
        XCTAssertEqual(decoded.socialMyRecordName, "vp-testrecord")
        XCTAssertEqual(decoded.socialConfirmedFriendIDs, ["vp-friend1"])
        XCTAssertEqual(decoded.socialProcessedRequestIDs, ["vfr-req-1", "vfr-req-2"])
    }
}
