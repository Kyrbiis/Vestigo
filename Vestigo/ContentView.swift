import SwiftUI
#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#endif
import Foundation
import Combine
import UniformTypeIdentifiers
#if canImport(CloudKit)
import CloudKit
#endif
#if canImport(EventKit)
import EventKit
#endif
#if canImport(UserNotifications)
import UserNotifications
#endif
#if canImport(WebKit)
import WebKit
#endif


// MARK: - App Entry

struct ContentView: View {
    @StateObject private var model = VestigoModel()
    @Namespace private var tabNamespace

    private var selectedTabBinding: Binding<AppTab> {
        Binding(
            get: { model.selectedTab },
            set: { model.selectTab($0) }
        )
    }

    var body: some View {
        TabView(selection: selectedTabBinding) {
            AppTabRoot(tab: .home, model: model)
                .tabItem {
                    Label(AppTab.home.title, systemImage: AppTab.home.icon)
                }
                .tag(AppTab.home)

            AppTabRoot(tab: .search, model: model)
                .tabItem {
                    Label(AppTab.search.title, systemImage: AppTab.search.icon)
                }
                .tag(AppTab.search)
            
            AppTabRoot(tab: .forYou, model: model)
                .tabItem {
                    Label(AppTab.forYou.title, systemImage: AppTab.forYou.icon)
                }
                .tag(AppTab.forYou)

            AppTabRoot(tab: .watchlist, model: model)
                .tabItem {
                    Label(AppTab.watchlist.title, systemImage: AppTab.watchlist.icon)
                }
                .tag(AppTab.watchlist)

            AppTabRoot(tab: .collections, model: model)
                .tabItem {
                    Label(AppTab.collections.title, systemImage: AppTab.collections.icon)
                }
                .tag(AppTab.collections)
        }
        .tint(model.settings.accentColor)
        #if os(iOS)
        .tabBarMinimizeBehavior(.onScrollDown)
        .background(
            TabBarRetapObserver(selectedTab: model.selectedTab) {
                model.reselectCurrentTab()
            }
        )
        #endif
        .preferredColorScheme(model.settings.appearance.preferredColorScheme)
        .environment(\.imageRefreshToken, model.imageRefreshToken)
        .environment(\.refreshImages, RefreshImagesAction {
            model.refreshImages()
        })
        .task { await model.bootstrap() }
        .sheet(item: $model.selectedItem) { item in
            DetailView(item: item, model: model)
        }
        .sheet(item: $model.selectedPerson) { person in
            PersonDetailView(person: person, model: model)
        }
        .sheet(isPresented: $model.showStreamingSetup) {
            StreamingServicesSetupSheet(model: model, isOnboarding: true)
        }
        .sheet(isPresented: $model.showNotificationOnboarding) {
            NotificationPreferencesSheet(model: model, isOnboarding: true)
        }
        .favouriteReplacementOverlay(model: model)
        .ratingPromptOverlay(model: model)
        .alert("Daily OMDb Limit Reached", isPresented: $model.showOMDbLimitAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your OMDb API key has made \(model.settings.omdbDailyRequestCount.formatted()) requests today, reaching its daily limit. IMDb and Rotten Tomato ratings will not load until midnight. You can view or change your key tier from the OMDb website.")
        }
    }
}

#if os(iOS)
private struct TabBarRetapObserver: UIViewControllerRepresentable {
    let selectedTab: AppTab
    let onRetap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onRetap: onRetap)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()

        DispatchQueue.main.async {
            context.coordinator.attach(from: controller, selectedIndex: selectedTab.sortIndex)
        }

        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.onRetap = onRetap

        DispatchQueue.main.async {
            context.coordinator.attach(from: uiViewController, selectedIndex: selectedTab.sortIndex)
        }
    }

    final class Coordinator: NSObject, UITabBarControllerDelegate {
        var onRetap: () -> Void
        private weak var tabBarController: UITabBarController?
        private var lastSelectedIndex: Int?

        init(onRetap: @escaping () -> Void) {
            self.onRetap = onRetap
        }

        func attach(from viewController: UIViewController, selectedIndex: Int) {
            guard let tabBarController = viewController.tabBarController else { return }

            if self.tabBarController !== tabBarController {
                self.tabBarController = tabBarController
                tabBarController.delegate = self
            }

            lastSelectedIndex = selectedIndex
        }

        func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
            let selectedIndex = tabBarController.selectedIndex

            if selectedIndex == lastSelectedIndex {
                onRetap()
            }

            lastSelectedIndex = selectedIndex
        }
    }
}
#endif

// MARK: - Root Navigation

private struct AppTabRoot: View {
    let tab: AppTab
    @ObservedObject var model: VestigoModel

    var body: some View {
        Group {
            switch tab {
            case .home:
                ZStack {
                    AppBackground(settings: model.settings)
                        .ignoresSafeArea()

                    NavigationStack(path: $model.homePath) {
                        HomeView(model: model)
                            .background(AppBackground(settings: model.settings).ignoresSafeArea())
                            .navigationDestination(for: SectionRoute.self) { route in
                                FullSectionView(route: route, model: model)
                                    .background(AppBackground(settings: model.settings).ignoresSafeArea())
                            }
                    }
                    .scrollContentBackground(.hidden)
                    #if os(iOS)
                    .toolbarBackground(.hidden, for: .navigationBar)
                    #endif
                    .background(Color.clear)
                }

            case .search:
                ZStack {
                    AppBackground(settings: model.settings)
                        .ignoresSafeArea()

                    NavigationStack(path: $model.searchPath) {
                        SearchView(model: model)
                            .background(AppBackground(settings: model.settings).ignoresSafeArea())
                            .navigationDestination(for: SearchRoute.self) { route in
                                switch route {
                                case .genre(let genreRoute):
                                    GenreResultsView(route: genreRoute, model: model)
                                        .background(AppBackground(settings: model.settings).ignoresSafeArea())
                                case .chart(let kind):
                                    ChartResultsView(kind: kind, model: model)
                                        .background(AppBackground(settings: model.settings).ignoresSafeArea())
                                }
                            }
                    }
                    .scrollContentBackground(.hidden)
                    #if os(iOS)
                    .toolbarBackground(.hidden, for: .navigationBar)
                    #endif
                    .background(Color.clear)
                }
                
            case .forYou:
                ForYouView(model: model)

            case .watchlist:
                WatchlistView(model: model)

            case .collections:
                CollectionsView(model: model)

            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }
}

#Preview {
    ContentView()
}
