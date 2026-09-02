import SwiftUI
import AppIntents
#if os(iOS)
import UIKit

extension Notification.Name {
    static let vestigoShortcut = Notification.Name("vestigoShortcut")
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.shortcutItems = [
            UIApplicationShortcutItem(type: "openWatchlist", localizedTitle: "Watchlist", localizedSubtitle: nil, icon: UIApplicationShortcutIcon(systemImageName: "bookmark"), userInfo: nil),
            UIApplicationShortcutItem(type: "openSearch", localizedTitle: "Search", localizedSubtitle: nil, icon: UIApplicationShortcutIcon(systemImageName: "magnifyingglass"), userInfo: nil),
            UIApplicationShortcutItem(type: "openForYou", localizedTitle: "For You", localizedSubtitle: nil, icon: UIApplicationShortcutIcon(systemImageName: "sparkles"), userInfo: nil),
            UIApplicationShortcutItem(type: "openPickForMe", localizedTitle: "Pick For Me", localizedSubtitle: nil, icon: UIApplicationShortcutIcon(systemImageName: "dice"), userInfo: nil),
        ]
        return true
    }

    func application(_ application: UIApplication, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        NotificationCenter.default.post(name: .vestigoShortcut, object: shortcutItem.type)
        completionHandler(true)
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        .portrait
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        forcePortrait()
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        forcePortrait()
    }

    private func forcePortrait() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        let prefs = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: .portrait)
        scene.requestGeometryUpdate(prefs) { _ in }
        scene.windows.forEach { $0.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations() }
    }
}

struct VestigoAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ShowVestigoWatchlistIntent(),
            phrases: [
                "Show my \(.applicationName) watchlist",
                "Open my \(.applicationName) watchlist",
                "What's on my \(.applicationName) watchlist"
            ],
            shortTitle: "My Watchlist",
            systemImageName: "bookmark"
        )
        AppShortcut(
            intent: ShowVestigoWatchedIntent(),
            phrases: [
                "What have I watched in \(.applicationName)",
                "Show my \(.applicationName) watch history"
            ],
            shortTitle: "Watched History",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: ShowVestigoFavouritesIntent(),
            phrases: [
                "Show my \(.applicationName) favourites",
                "Show my \(.applicationName) favorites"
            ],
            shortTitle: "My Favourites",
            systemImageName: "heart"
        )
        AppShortcut(
            intent: GetUnwatchedVestigoWatchlistIntent(),
            phrases: [
                "What should I watch next in \(.applicationName)",
                "Show my unwatched \(.applicationName) watchlist",
                "What's unwatched on my \(.applicationName) watchlist"
            ],
            shortTitle: "Unwatched Watchlist",
            systemImageName: "bookmark.slash"
        )
        AppShortcut(
            intent: GetRecentlyWatchedInVestigoIntent(),
            phrases: [
                "What did I recently watch in \(.applicationName)",
                "Show my recent \(.applicationName) watches",
                "What have I been watching in \(.applicationName)"
            ],
            shortTitle: "Recently Watched",
            systemImageName: "clock"
        )
        AppShortcut(
            intent: CheckVestigoItemStatusIntent(),
            phrases: [
                "Have I watched something in \(.applicationName)",
                "Check if something is on my \(.applicationName) watchlist",
                "What did I rate something in \(.applicationName)"
            ],
            shortTitle: "Check Item Status",
            systemImageName: "questionmark.circle"
        )
        AppShortcut(
            intent: GetVestigoLibraryStatsIntent(),
            phrases: [
                "Show my \(.applicationName) stats",
                "How many movies have I watched in \(.applicationName)",
                "Give me my \(.applicationName) library summary"
            ],
            shortTitle: "Library Stats",
            systemImageName: "chart.bar"
        )
        AppShortcut(
            intent: GetVestigoCollectionIntent(),
            phrases: [
                "Show a \(.applicationName) collection",
                "Open a collection in \(.applicationName)"
            ],
            shortTitle: "Open Collection",
            systemImageName: "folder"
        )
        AppShortcut(
            intent: MarkWatchedInVestigoIntent(),
            phrases: [
                "Mark \(\.$item) as watched in \(.applicationName)",
                "I just watched \(\.$item) in \(.applicationName)",
                "Log \(\.$item) as watched in \(.applicationName)"
            ],
            shortTitle: "Mark as Watched",
            systemImageName: "eye"
        )
        AppShortcut(
            intent: AddToVestigoWatchlistIntent(),
            phrases: [
                "Add \(\.$item) to my \(.applicationName) watchlist",
                "Save \(\.$item) to \(.applicationName)"
            ],
            shortTitle: "Add to Watchlist",
            systemImageName: "bookmark.badge.plus"
        )
    }
}
#endif

@main
struct VestigoApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
                .autocorrectionDisabled()
        }
    }
}
