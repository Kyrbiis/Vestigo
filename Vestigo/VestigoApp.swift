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

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        .portrait
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
