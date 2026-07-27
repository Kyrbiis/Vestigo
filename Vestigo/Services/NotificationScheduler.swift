import Foundation
import UserNotifications
#if canImport(BackgroundTasks) && os(iOS)
import BackgroundTasks
#endif

// MARK: - Dry-run simulation types

struct NotifSimResult: Identifiable {
    let id = UUID()
    let itemTitle: String
    let mediaKind: MediaKind
    let scenario: String
    let outcome: NotifSimOutcome
    let isArtificial: Bool

    var shouldHaveHappened: Bool { outcome == .fires }
    var wouldHaveHappenedWithAllEnabled: Bool {
        switch outcome {
        case .fires, .firesIfKindEnabled, .firesIfGlobalEnabled: return true
        default: return false
        }
    }
}

enum NotifSimOutcome: Equatable {
    case fires
    case firesIfKindEnabled(NotificationKind)
    case firesIfGlobalEnabled
    case noBaseline
    case alreadySent

    var label: String {
        switch self {
        case .fires:                        return "Would fire"
        case .firesIfKindEnabled(let k):    return "Need '\(k.title)' on"
        case .firesIfGlobalEnabled:         return "Notifications off"
        case .noBaseline:                   return "No baseline"
        case .alreadySent:                  return "Already sent"
        }
    }

    var symbolName: String {
        switch self {
        case .fires:                return "bell.fill"
        case .firesIfKindEnabled:   return "bell.slash"
        case .firesIfGlobalEnabled: return "bell.slash"
        case .noBaseline:           return "questionmark.circle"
        case .alreadySent:          return "checkmark.circle"
        }
    }
}

@MainActor
final class NotificationScheduler {
    static let shared = NotificationScheduler()
    private init() {}

    nonisolated static let taskID = "com.jojovestigo.notifications.check"

    // MARK: - Per-user staggering offset

    // Generated once on first run, stored permanently. Spreads the user base across
    // the full 3600-second hour window so server load is distributed evenly.
    nonisolated private static var persistentUserOffset: TimeInterval {
        let key = "Vestigo.notif.userCheckOffset"
        let stored = UserDefaults.standard.double(forKey: key)
        if stored > 0 { return stored }
        let offset = Double.random(in: 0..<3600)
        UserDefaults.standard.set(offset, forKey: key)
        return offset
    }

    // MARK: - Deduplication store

    private var notifiedIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "Vestigo.notif.notifiedIDs") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "Vestigo.notif.notifiedIDs") }
    }

    // MARK: - Background task registration

    nonisolated static func registerBackgroundTask() {
        #if canImport(BackgroundTasks) && os(iOS)
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            refreshTask.expirationHandler = { refreshTask.setTaskCompleted(success: false) }
            Task { @MainActor in
                let library = Storage.load(UserLibrary.self, key: "Vestigo.library") ?? UserLibrary()
                let prefs = Storage.loadNotificationPreferences() ?? NotificationPreferences()
                await NotificationScheduler.shared.performBackgroundFetch(library: library, preferences: prefs)
                NotificationScheduler.shared.scheduleNextBackgroundCheck()
                refreshTask.setTaskCompleted(success: true)
            }
        }
        #endif
    }

    func scheduleNextBackgroundCheck() {
        #if canImport(BackgroundTasks) && os(iOS)
        let request = BGAppRefreshTaskRequest(identifier: Self.taskID)
        // Each user has a consistent slot within the hour cycle based on their persistent offset.
        // This spreads the user base across the full hour so servers see steady load, not spikes.
        let userOffset = Self.persistentUserOffset // [0, 3600)
        let now = Date().timeIntervalSinceReferenceDate
        let secsIntoHour = now.truncatingRemainder(dividingBy: 3600)
        let secsUntilSlot = userOffset > secsIntoHour
            ? userOffset - secsIntoHour
            : 3600 - secsIntoHour + userOffset
        // Enforce at least 30 minutes before the next check to avoid rapid re-firing.
        let delay = secsUntilSlot < 1800 ? secsUntilSlot + 3600 : secsUntilSlot
        let jitter = Double.random(in: -30...30)
        request.earliestBeginDate = Date(timeIntervalSinceNow: delay + jitter)
        try? BGTaskScheduler.shared.submit(request)
        #endif
    }

    // MARK: - Background data fetch

    func performBackgroundFetch(library: UserLibrary, preferences: NotificationPreferences) async {
        guard preferences.isEnabled else { return }
        let tmdb = TMDbService()

        if preferences.enabledKinds.contains(.watchedSeriesSeason) {
            // Check up to 8 recently-watched TV shows for new seasons
            let watchedTV = Array(library.watchedItems.filter { $0.kind == .tv }.prefix(8))
            await withTaskGroup(of: Void.self) { group in
                for item in watchedTV {
                    group.addTask {
                        guard let count = try? await tmdb.seasonCount(forTVShowID: item.id) else { return }
                        await MainActor.run {
                            NotificationScheduler.shared.checkNewSeasonCount(
                                for: item, seasonCount: count, preferences: preferences
                            )
                        }
                    }
                }
            }
        }

        if preferences.enabledKinds.contains(.newTrailer) {
            // Check up to 8 watchlisted items for new trailers
            let watchlisted = Array(library.watchlistItems.prefix(8))
            await withTaskGroup(of: Void.self) { group in
                for item in watchlisted {
                    group.addTask {
                        guard let count = try? await tmdb.trailerCount(for: item) else { return }
                        await MainActor.run {
                            NotificationScheduler.shared.checkNewTrailerCount(
                                for: item, trailerCount: count, preferences: preferences
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Watchlist release notifications

    func scheduleWatchlistNotifications(for items: [MediaItem], preferences: NotificationPreferences) {
        guard preferences.isEnabled, preferences.enabledKinds.contains(.watchlistRelease) else { return }
        let center = UNUserNotificationCenter.current()
        let leadTimes = preferences.watchlistLeadTimes.isEmpty ? [NotificationLeadTime.onReleaseDay] : preferences.watchlistLeadTimes

        for item in items {
            guard let releaseDate = item.releaseDateValue else { continue }

            for leadTime in leadTimes {
                guard let fireDate = Calendar.current.date(byAdding: .day, value: leadTime.daysOffset, to: releaseDate),
                      fireDate > Date() else { continue }

                let title: String
                let body: String
                switch leadTime {
                case .onReleaseDay:
                    title = "\(item.title) is out today!"
                    body = "The \(item.kind == .movie ? "movie" : "show") you saved is now available."
                case .oneDay:
                    title = "\(item.title) releases tomorrow"
                    body = "It drops on \(item.releaseDateReadable) — plan your watch!"
                default:
                    title = "\(item.title) releases in \(leadTime.relativeText) on \(item.releaseDateReadable)"
                    body = "Save the date and plan your watch!"
                }

                scheduleCalendar(
                    id: "wlRelease-\(leadTime.rawValue)-\(item.key.stableID)",
                    title: title,
                    body: body,
                    on: fireDate,
                    hour: leadTime == .onReleaseDay ? 9 : 10,
                    deepLink: "vestigo://\(item.kind.rawValue)/\(item.id)",
                    center: center
                )
            }
        }
    }

    func cancelWatchlistNotifications(for item: MediaItem) {
        let ids = NotificationLeadTime.allCases.map { "wlRelease-\($0.rawValue)-\(item.key.stableID)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    func cancelAllPendingNotifications(for item: MediaItem) {
        cancelWatchlistNotifications(for: item)
        let stableID = item.key.stableID
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let ids = requests.filter { $0.identifier.contains(stableID) }.map(\.identifier)
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    // MARK: - New season (watched TV shows)

    func checkNewSeason(for item: MediaItem, seasons: [SeasonInfo], preferences: NotificationPreferences) {
        guard preferences.isEnabled, preferences.enabledKinds.contains(.watchedSeriesSeason) else { return }
        guard item.kind == .tv else { return }

        let countKey = "Vestigo.notif.seasons.\(item.key.stableID)"
        let knownCount = UserDefaults.standard.integer(forKey: countKey)
        let currentCount = seasons.filter { $0.number > 0 }.count

        defer { if currentCount > 0 { UserDefaults.standard.set(currentCount, forKey: countKey) } }
        guard knownCount > 0, currentCount > knownCount else { return }

        let latest = seasons.filter { $0.number > 0 }.sorted { $0.number > $1.number }.first
        let seasonLabel = latest?.name ?? "Season \(currentCount)"
        let notifID = "newSeason-\(item.key.stableID)-s\(currentCount)"
        guard !notifiedIDs.contains(notifID) else { return }

        fireNow(
            id: notifID,
            title: "\(item.title): \(seasonLabel) is out",
            body: "A new season of a show you watched has arrived.",
            deepLink: "vestigo://\(item.kind.rawValue)/\(item.id)"
        )
        notifiedIDs.insert(notifID)
    }

    // Background variant — uses raw season count when full SeasonInfo isn't available.
    private func checkNewSeasonCount(for item: MediaItem, seasonCount: Int, preferences: NotificationPreferences) {
        guard preferences.isEnabled, preferences.enabledKinds.contains(.watchedSeriesSeason) else { return }
        guard item.kind == .tv, seasonCount > 0 else { return }

        let countKey = "Vestigo.notif.seasons.\(item.key.stableID)"
        let knownCount = UserDefaults.standard.integer(forKey: countKey)

        defer { UserDefaults.standard.set(seasonCount, forKey: countKey) }
        guard knownCount > 0, seasonCount > knownCount else { return }

        let notifID = "newSeason-\(item.key.stableID)-s\(seasonCount)"
        guard !notifiedIDs.contains(notifID) else { return }

        fireNow(
            id: notifID,
            title: "\(item.title): Season \(seasonCount) is out",
            body: "A new season of a show you watched has arrived.",
            deepLink: "vestigo://\(item.kind.rawValue)/\(item.id)"
        )
        notifiedIDs.insert(notifID)
    }

    // MARK: - New trailer (watchlisted items)

    func checkNewTrailer(for item: MediaItem, trailerCount: Int, preferences: NotificationPreferences) {
        guard preferences.isEnabled, preferences.enabledKinds.contains(.newTrailer) else { return }
        guard trailerCount > 0 else { return }

        let countKey = "Vestigo.notif.trailers.\(item.key.stableID)"
        let knownCount = UserDefaults.standard.integer(forKey: countKey)

        defer { UserDefaults.standard.set(trailerCount, forKey: countKey) }
        guard knownCount > 0, trailerCount > knownCount else { return }

        let notifID = "newTrailer-\(item.key.stableID)-t\(trailerCount)"
        guard !notifiedIDs.contains(notifID) else { return }

        fireNow(
            id: notifID,
            title: "New trailer: \(item.title)",
            body: "A new trailer dropped for something on your watchlist.",
            deepLink: "vestigo://\(item.kind.rawValue)/\(item.id)"
        )
        notifiedIDs.insert(notifID)
    }

    // Background variant — same logic, just named differently to distinguish call sites.
    private func checkNewTrailerCount(for item: MediaItem, trailerCount: Int, preferences: NotificationPreferences) {
        checkNewTrailer(for: item, trailerCount: trailerCount, preferences: preferences)
    }

    // MARK: - Provider change (watchlisted released items)

    func checkProviderChange(for item: MediaItem, providers: [StreamingOption], preferences: NotificationPreferences, subscribedServiceNames: Set<String> = []) {
        guard preferences.isEnabled, preferences.enabledKinds.contains(.watchAvailability) else { return }
        guard !item.isUpcoming else { return }

        let setKey = "Vestigo.notif.providers.\(item.key.stableID)"
        let currentNames = Set(providers.map(\.serviceName))
        let knownNames = Set(UserDefaults.standard.stringArray(forKey: setKey) ?? [])

        defer { if !currentNames.isEmpty { UserDefaults.standard.set(Array(currentNames), forKey: setKey) } }
        var newNames = currentNames.subtracting(knownNames)
        guard !knownNames.isEmpty, !newNames.isEmpty else { return }

        // If the user has selected specific subscribed services, filter to only those.
        if preferences.notifyOnlyForSubscribedServices && !subscribedServiceNames.isEmpty {
            newNames = newNames.filter { newName in
                subscribedServiceNames.contains { sub in
                    let a = newName.lowercased(); let b = sub.lowercased()
                    return a.contains(b) || b.contains(a)
                }
            }
            guard !newNames.isEmpty else { return }
        }

        let providerLabel = newNames.sorted().first ?? "a new service"
        let notifID = "newProvider-\(item.key.stableID)-\(newNames.sorted().joined(separator: "-"))"
        guard !notifiedIDs.contains(notifID) else { return }

        fireNow(
            id: notifID,
            title: "\(item.title) is now on \(providerLabel)",
            body: "Your saved \(item.kind == .movie ? "movie" : "show") is now available to watch.",
            deepLink: "vestigo://\(item.kind.rawValue)/\(item.id)"
        )
        notifiedIDs.insert(notifID)
    }

    // MARK: - Similar upcoming

    func scheduleIfSimilarUpcoming(_ item: MediaItem, preferences: NotificationPreferences) {
        guard preferences.isEnabled, preferences.enabledKinds.contains(.similarUpcoming) else { return }
        guard let releaseDate = item.releaseDateValue, releaseDate > Date() else { return }

        let notifID = "similarUpcoming-\(item.key.stableID)"
        guard !notifiedIDs.contains(notifID) else { return }

        let daysUntil = Calendar.current.dateComponents([.day], from: Date(), to: releaseDate).day ?? 0
        let relLabel: String
        switch daysUntil {
        case 0: relLabel = "today"
        case 1: relLabel = "tomorrow"
        case 2...6: relLabel = "in \(daysUntil) days"
        case 7...13: relLabel = "in 1 week"
        default: relLabel = "on \(item.releaseDateReadable)"
        }

        scheduleCalendar(
            id: notifID,
            title: "You might love \(item.title)",
            body: "Based on your taste — releases \(relLabel) on \(item.releaseDateReadable).",
            on: releaseDate, hour: 10,
            deepLink: "vestigo://\(item.kind.rawValue)/\(item.id)",
            center: UNUserNotificationCenter.current()
        )
        notifiedIDs.insert(notifID)
    }

    // MARK: - Franchise installment

    func notifyFranchiseInstallment(_ item: MediaItem, preferences: NotificationPreferences) {
        guard preferences.isEnabled, preferences.enabledKinds.contains(.franchiseInstallment) else { return }

        let notifID = "franchise-\(item.key.stableID)"
        guard !notifiedIDs.contains(notifID) else { return }

        if item.isUpcoming, let releaseDate = item.releaseDateValue {
            let daysUntil = Calendar.current.dateComponents([.day], from: Date(), to: releaseDate).day ?? 0
            let relLabel: String
            switch daysUntil {
            case 0: relLabel = "today"
            case 1: relLabel = "tomorrow"
            case 2...6: relLabel = "in \(daysUntil) days"
            default: relLabel = "on \(item.releaseDateReadable)"
            }
            scheduleCalendar(
                id: notifID,
                title: "New from a franchise you follow",
                body: "\(item.title) releases \(relLabel).",
                on: releaseDate, hour: 9,
                deepLink: "vestigo://\(item.kind.rawValue)/\(item.id)",
                center: UNUserNotificationCenter.current()
            )
        } else {
            fireNow(
                id: notifID,
                title: "New from a franchise you follow",
                body: "\(item.title) is now available.",
                deepLink: "vestigo://\(item.kind.rawValue)/\(item.id)"
            )
        }
        notifiedIDs.insert(notifID)
    }

    // MARK: - Dry-run simulation

    // Scans the real library and evaluates what would happen if each reactive event fired right now.
    // Read-only — does not modify UserDefaults or schedule any notifications.
    func dryRunLibraryScenarios(library: UserLibrary, preferences: NotificationPreferences) -> [NotifSimResult] {
        var results: [NotifSimResult] = []
        let dedup = notifiedIDs

        // New season: watched TV shows
        for item in library.watchedItems.filter({ $0.kind == .tv }) {
            let countKey = "Vestigo.notif.seasons.\(item.key.stableID)"
            let knownCount = UserDefaults.standard.integer(forKey: countKey)
            let simCount = max(knownCount + 1, 1)
            let notifID = "newSeason-\(item.key.stableID)-s\(simCount)"
            let baselineLabel = knownCount > 0 ? "\(knownCount)→\(simCount) seasons" : "0→1 seasons"
            results.append(NotifSimResult(
                itemTitle: item.title, mediaKind: .tv,
                scenario: "New season (\(baselineLabel))",
                outcome: simOutcome(kind: .watchedSeriesSeason, hasBaseline: knownCount > 0, notifID: notifID, dedup: dedup, prefs: preferences),
                isArtificial: false
            ))
        }

        // New trailer: watchlisted items
        for item in library.watchlistItems {
            let countKey = "Vestigo.notif.trailers.\(item.key.stableID)"
            let knownCount = UserDefaults.standard.integer(forKey: countKey)
            let simCount = max(knownCount + 1, 1)
            let notifID = "newTrailer-\(item.key.stableID)-t\(simCount)"
            let baselineLabel = knownCount > 0 ? "\(knownCount)→\(simCount) trailers" : "0→1 trailers"
            results.append(NotifSimResult(
                itemTitle: item.title, mediaKind: item.kind,
                scenario: "New trailer (\(baselineLabel))",
                outcome: simOutcome(kind: .newTrailer, hasBaseline: knownCount > 0, notifID: notifID, dedup: dedup, prefs: preferences),
                isArtificial: false
            ))
        }

        // New streaming provider: watchlisted released items
        for item in library.watchlistItems.filter({ !$0.isUpcoming }) {
            let setKey = "Vestigo.notif.providers.\(item.key.stableID)"
            let knownNames = Set(UserDefaults.standard.stringArray(forKey: setKey) ?? [])
            let hasBaseline = !knownNames.isEmpty
            let simProvider = knownNames.contains("Netflix") ? "Apple TV+" : "Netflix"
            let notifID = "newProvider-\(item.key.stableID)-\(simProvider)"
            results.append(NotifSimResult(
                itemTitle: item.title, mediaKind: item.kind,
                scenario: "Provider added ('\(simProvider)')",
                outcome: simOutcome(kind: .watchAvailability, hasBaseline: hasBaseline && !knownNames.contains(simProvider), notifID: notifID, dedup: dedup, prefs: preferences),
                isArtificial: false
            ))
        }

        return results
    }

    // Returns a fixed set of artificial scenarios covering every possible outcome.
    // The "fires" scenarios always use fully-enabled preferences as a fixture so the pure
    // logic is verified independently of the user's real settings.
    // The "kind disabled" and "global off" scenarios inject controlled broken prefs to
    // demonstrate what each blocked state looks like.
    func dryRunArtificialScenarios(preferences: NotificationPreferences) -> [NotifSimResult] {
        let dedup = notifiedIDs
        // A fixture with everything on — used for the "would fire" logic tests.
        let allOn = NotificationPreferences(
            isEnabled: true,
            enabledKinds: Set(NotificationKind.allCases),
            watchlistLeadTimes: preferences.watchlistLeadTimes,
            hasSeenPrompt: true,
            deviceToken: preferences.deviceToken
        )
        return [
            // ── .fires ──────────────────────────────────────────────────────────
            // These always use allOn prefs so they show green regardless of real settings.
            // They test that the core detection logic works when all guards pass.
            NotifSimResult(
                itemTitle: "Drama Series",
                mediaKind: .tv,
                scenario: "New season: stored 3 seasons → event fires for season 4",
                outcome: simOutcome(kind: .watchedSeriesSeason, hasBaseline: true, notifID: "art-fires-\(UUID())", dedup: dedup, prefs: allOn),
                isArtificial: true
            ),
            NotifSimResult(
                itemTitle: "Action Sequel",
                mediaKind: .movie,
                scenario: "New trailer: stored 2 trailers → event fires for trailer 3",
                outcome: simOutcome(kind: .newTrailer, hasBaseline: true, notifID: "art-fires2-\(UUID())", dedup: dedup, prefs: allOn),
                isArtificial: true
            ),
            NotifSimResult(
                itemTitle: "Indie Film",
                mediaKind: .movie,
                scenario: "Provider added: stored Prime Video only → Netflix added",
                outcome: simOutcome(kind: .watchAvailability, hasBaseline: true, notifID: "art-fires3-\(UUID())", dedup: dedup, prefs: allOn),
                isArtificial: true
            ),

            // ── .noBaseline ─────────────────────────────────────────────────────
            // Item's detail page was never visited — no count stored to compare against.
            NotifSimResult(
                itemTitle: "Upcoming Blockbuster",
                mediaKind: .movie,
                scenario: "New trailer: no stored count (detail never opened) → event: trailer 1 published",
                outcome: simOutcome(kind: .newTrailer, hasBaseline: false, notifID: "art-nobase-\(UUID())", dedup: dedup, prefs: allOn),
                isArtificial: true
            ),
            NotifSimResult(
                itemTitle: "Sci-Fi Series",
                mediaKind: .tv,
                scenario: "New season: no stored count (detail never opened) → event: season 2 added",
                outcome: simOutcome(kind: .watchedSeriesSeason, hasBaseline: false, notifID: "art-nobase2-\(UUID())", dedup: dedup, prefs: allOn),
                isArtificial: true
            ),

            // ── .alreadySent ────────────────────────────────────────────────────
            // Same event already fired — deduplication blocks a repeat.
            NotifSimResult(
                itemTitle: "Thriller Series",
                mediaKind: .tv,
                scenario: "New season: baseline set, season 3 event already fired → dedup blocks repeat",
                outcome: .alreadySent,
                isArtificial: true
            ),

            // ── .firesIfKindEnabled ─────────────────────────────────────────────
            // Injects prefs with this specific kind forced off, regardless of real settings.
            NotifSimResult(
                itemTitle: "Crime Drama",
                mediaKind: .tv,
                scenario: "New season: baseline set → blocked because 'New watched-show seasons' toggle is OFF",
                outcome: simOutcome(
                    kind: .watchedSeriesSeason, hasBaseline: true,
                    notifID: "art-kind-\(UUID())", dedup: dedup,
                    prefs: NotificationPreferences(isEnabled: true, enabledKinds: Set(NotificationKind.allCases).subtracting([.watchedSeriesSeason]), watchlistLeadTimes: preferences.watchlistLeadTimes, hasSeenPrompt: true, deviceToken: preferences.deviceToken)
                ),
                isArtificial: true
            ),

            // ── .firesIfGlobalEnabled ───────────────────────────────────────────
            // Injects prefs with global switch forced off.
            NotifSimResult(
                itemTitle: "Fantasy Epic",
                mediaKind: .movie,
                scenario: "New trailer: baseline set → blocked because master notifications toggle is OFF",
                outcome: simOutcome(
                    kind: .newTrailer, hasBaseline: true,
                    notifID: "art-global-\(UUID())", dedup: dedup,
                    prefs: NotificationPreferences(isEnabled: false, enabledKinds: Set(NotificationKind.allCases), watchlistLeadTimes: preferences.watchlistLeadTimes, hasSeenPrompt: true, deviceToken: preferences.deviceToken)
                ),
                isArtificial: true
            ),
        ]
    }

    private func simOutcome(kind: NotificationKind, hasBaseline: Bool, notifID: String, dedup: Set<String>, prefs: NotificationPreferences) -> NotifSimOutcome {
        guard hasBaseline else { return .noBaseline }
        guard !dedup.contains(notifID) else { return .alreadySent }
        guard prefs.isEnabled else { return .firesIfGlobalEnabled }
        guard prefs.enabledKinds.contains(kind) else { return .firesIfKindEnabled(kind) }
        return .fires
    }

    // MARK: - Dev tools

    func fireTestNotification(for kind: NotificationKind) {
        let body: String
        switch kind {
        case .watchlistRelease:
            body = "Inception releases in 3 days on \(Date(timeIntervalSinceNow: 259200).formatted(.dateTime.month(.abbreviated).day()))."
        case .watchedSeriesSeason:
            body = "A new season of a show you watched has arrived."
        case .newTrailer:
            body = "A new trailer dropped for something on your watchlist."
        case .watchAvailability:
            body = "A saved title is now available on a new streaming service."
        case .similarUpcoming:
            body = "An upcoming release strongly matches your taste."
        case .franchiseInstallment:
            body = "A new installment from a franchise you follow is available."
        }
        fireNow(
            id: "devTest-\(kind.rawValue)-\(UUID().uuidString)",
            title: "[Test] \(kind.title)",
            body: body,
            deepLink: "vestigo://movie/0"
        )
    }

    func resetDeduplicationStore() {
        notifiedIDs = []
        let defaults = UserDefaults.standard
        defaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix("Vestigo.notif.") && $0 != "Vestigo.notif.notifiedIDs" && $0 != "Vestigo.notif.userCheckOffset" }
            .forEach { defaults.removeObject(forKey: $0) }
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    // MARK: - Private helpers

    private func scheduleCalendar(id: String, title: String, body: String, on date: Date, hour: Int, deepLink: String, center: UNUserNotificationCenter) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["deepLink": deepLink]

        var comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        comps.hour = hour
        comps.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    private func fireNow(id: String, title: String, body: String, deepLink: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["deepLink": deepLink]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
