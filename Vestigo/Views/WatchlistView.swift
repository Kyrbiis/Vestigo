import SwiftUI
import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(WebKit)
import WebKit
#endif
#if canImport(UserNotifications)
import UserNotifications
#endif

// MARK: - Watchlist

struct WatchlistView: View {
    @ObservedObject var model: VestigoModel
    @State private var showOnlyStreamable = false

    private func isAvailableNow(_ item: MediaItem) -> Bool {
        guard let options = model.providerCache[item.key] else { return true }
        let subscribed = model.settings.subscribedServiceNames
        return options.contains { option in
            let t = option.type.lowercased()
            return ["subscription", "sub", "free"].contains(t) && option.isSubscribed(in: subscribed)
        }
    }

    var body: some View {
        let hasProviders = !model.settings.subscribedServiceNames.isEmpty
        let sortedItems = model.library.watchlistItems.sorted(
            using: model.sortOption,
            ratings: model.library.ratings,
            externalRatings: model.externalRatingsCache,
            ratingSource: model.settings.preferredRatingSource,
            direction: model.sortDirection
        )
        let filteredItems = (showOnlyStreamable && hasProviders) ? sortedItems.filter(isAvailableNow) : sortedItems
        let unwatchedItems = filteredItems.filter { !model.library.isWatched($0.key) }
        let watchedItems = filteredItems.filter { model.library.isWatched($0.key) }

        BaseScreen(title: "Watchlist", filter: .constant(.both), settings: model.settings, onRefresh: {
            await model.loadExternalRatings(for: model.library.watchlistItems, limit: 120)
        }) {
            VStack(alignment: .leading, spacing: 14) {
                SortRow(direction: $model.sortDirection) {
                    SortPicker(sort: $model.sortOption, includeMyRating: false, ratingSource: model.settings.preferredRatingSource)
                }

                if hasProviders {
                    Toggle(isOn: $showOnlyStreamable) {
                        Label("Available on my services", systemImage: "play.circle")
                            .font(.subheadline)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .liquidGlass(cornerRadius: 16)
                    .onChange(of: showOnlyStreamable) { _, isOn in
                        if isOn { model.loadProvidersForWatchlistItems() }
                    }

                    if showOnlyStreamable {
                        Text("You can update your services anytime in Content Settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                    }
                }

                if sortedItems.isEmpty {
                    StatusBubble(title: "No saved items", text: "Saved movies and series will appear here.")
                } else if showOnlyStreamable && filteredItems.isEmpty {
                    StatusBubble(title: "Nothing available right now", text: "None of your watchlist items are on your current streaming services.")
                } else {
                    if !unwatchedItems.isEmpty {
                        Text("Unwatched")
                            .sectionTitle()

                        MediaGridOrList(items: unwatchedItems, hideWatchedForUpcoming: false, model: model, swipeContext: .watchlist)
                    }

                    if !watchedItems.isEmpty {
                        Text("Watched")
                            .sectionTitle()
                            .padding(.top, unwatchedItems.isEmpty ? 0 : 8)

                        MediaGridOrList(items: watchedItems, hideWatchedForUpcoming: false, model: model, swipeContext: .watchlist)
                    }
                }
            }
        }
        .onChange(of: model.watchlistResetToken) { _, _ in
            model.sortOption = .tmdbRating
        }
        .onAppear {
            if model.sortOption == .myRating {
                model.sortOption = .tmdbRating
            }
        }
    }
}
