//
//  VestigoApp.swift
//  Vestigo
//
//  Created by Jojo Hyman on 5/10/26.
//

import SwiftUI
#if os(iOS)
import UIKit
import UserNotifications
import BackgroundTasks

final class AppDelegate: NSObject, UIApplicationDelegate {
    // Stores a deep link URL from cold-launch notification taps, before SwiftUI's onReceive is ready.
    static var pendingDeepLinkURL: URL?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        NotificationScheduler.registerBackgroundTask()
        return true
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

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        NotificationCenter.default.post(name: .vestigoDidRegisterForRemoteNotifications, object: token)
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let deepLink = response.notification.request.content.userInfo["deepLink"] as? String,
              let url = URL(string: deepLink) else {
            return
        }

        // Store for cold-launch case (before SwiftUI onReceive is registered).
        AppDelegate.pendingDeepLinkURL = url
        NotificationCenter.default.post(name: .vestigoDidOpenNotificationDeepLink, object: url)
    }
}
#endif

extension Notification.Name {
    static let vestigoDidRegisterForRemoteNotifications = Notification.Name("vestigoDidRegisterForRemoteNotifications")
    static let vestigoDidOpenNotificationDeepLink = Notification.Name("vestigoDidOpenNotificationDeepLink")
}

@main
struct VestigoApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
