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

    var sortedItems: [MediaItem] {
        model.library.watchlistItems.sorted(
            using: model.sortOption,
            ratings: model.library.ratings,
            externalRatings: model.externalRatingsCache,
            ratingSource: model.settings.preferredRatingSource,
            direction: model.sortDirection
        )
    }

    var unwatchedItems: [MediaItem] {
        sortedItems.filter { !model.library.isWatched($0.key) }
    }

    var watchedItems: [MediaItem] {
        sortedItems.filter { model.library.isWatched($0.key) }
    }

    var body: some View {
        BaseScreen(title: "Watchlist", filter: .constant(.both), settings: model.settings, onRefresh: {
            await model.loadExternalRatings(for: model.library.watchlistItems, limit: 120)
        }) {
            VStack(alignment: .leading, spacing: 14) {
                SortRow(direction: $model.sortDirection) {
                    SortPicker(sort: $model.sortOption, includeMyRating: false, ratingSource: model.settings.preferredRatingSource)
                }

                if sortedItems.isEmpty {
                    StatusBubble(title: "No saved items", text: "Saved movies and series will appear here.")
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

