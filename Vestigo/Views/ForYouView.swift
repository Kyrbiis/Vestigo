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

// MARK: - For You

struct ForYouView: View {
    @ObservedObject var model: VestigoModel
    @State private var forYouFilter: MediaFilter = .both
    @State private var forYouPath: [ForYouRoute] = []
    @State private var omdbCalloutVisible = true

    private var recentWatchedItem: MediaItem? {
        model.library.lastWatchedItem
    }

    private var favouriteItem: MediaItem? {
        model.library.favouriteItems(for: forYouFilter).first
    }

    private var watchlistPicks: [MediaItem] {
        filteredForYou(model.library.watchlistItems)
            .sorted(
                using: .tmdbRating,
                ratings: model.library.ratings,
                externalRatings: model.externalRatingsCache,
                ratingSource: model.settings.preferredRatingSource
            )
    }

    var body: some View {
        NavigationStack(path: $forYouPath) {
            BaseScreen(title: "For You", filter: $forYouFilter, settings: model.settings, onRefresh: {
                await model.loadSmartRecommendations()
                model.refreshVisibleExternalRatings()
            }) {
                VStack(spacing: 22) {
                    FilterPills(filter: $forYouFilter, options: [.movie, .tv, .both]) {}

                    if omdbCalloutVisible
                        && model.settings.preferredRatingSource == .imdb
                        && model.settings.omdbPrimaryKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        HStack(spacing: 12) {
                            Image(systemName: "key.fill")
                                .font(.title3)
                                .foregroundStyle(model.settings.accentColor)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Add your OMDb key for IMDb ratings")
                                    .font(.subheadline.bold())
                                Text("Without a key, scores fall back to TMDb.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            VStack(spacing: 6) {
                                Button {
                                    omdbCalloutVisible = false
                                    model.selectedTab = .home
                                    model.homePath.append(.settings)
                                } label: {
                                    Text("Set Up")
                                        .font(.caption.bold())
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(model.settings.accentColor, in: Capsule())
                                        .foregroundStyle(.white)
                                }
                                Button {
                                    omdbCalloutVisible = false
                                } label: {
                                    Text("Dismiss")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(14)
                        .liquidGlass(cornerRadius: 24)
                    }

                    if model.library.watchedItems.count < 3 {
                        StatusBubble(
                            title: "Not enough watch history yet",
                            text: "Mark at least 3 movies or series as watched to improve personalized recommendations. Ratings make this page more useful."
                        )
                    }

                    ForEach(model.settings.forYouCarouselOrder, id: \.self) { carousel in
                        if !model.settings.forYouCarouselHidden.contains(carousel) {
                            forYouCarouselView(for: carousel)
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if forYouPath.isEmpty {
                    Button {
                        forYouPath.append(.pickForMe)
                    } label: {
                        Label("Pick for me", systemImage: "sparkles")
                            .font(.headline.bold())
                            .padding(.horizontal, 16)
                            .frame(height: 46)
                            .liquidGlass(cornerRadius: 23)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 10)
                }
            }
            .navigationDestination(for: ForYouRoute.self) { route in
                switch route {
                case .section(let section):
                    FullMediaListView(title: section.title, items: section.items, model: model)
                case .pickForMe:
                    PickForMeView(model: model, startingFilter: forYouFilter)
                }
            }
            .task {
                await model.loadSmartRecommendations()
            }
            .onChange(of: model.forYouResetToken) { _, _ in
                forYouFilter = .both
                forYouPath.removeAll()
            }
        }
    }

    private func filteredForYou(_ items: [MediaItem]) -> [MediaItem] {
        items.filter { item in
            if model.library.isWatched(item.key) {
                return false
            }

            if model.settings.hideUpcomingFromRecommended && item.isUpcoming {
                return false
            }

            switch forYouFilter {
            case .movie:
                return item.kind == .movie
            case .tv:
                return item.kind == .tv
            case .both:
                return true
            }
        }
    }

    @ViewBuilder
    private func forYouCarouselView(for carousel: ForYouCarousel) -> some View {
        switch carousel {
        case .forYou:
            let sectionItems = filteredForYou(model.recommendations)
            if !sectionItems.isEmpty {
                let sectionTitle = "For you"
                MediaSection(title: sectionTitle, items: sectionItems, hideWatchedForUpcoming: false, model: model, openFull: {
                    forYouPath.append(.section(ForYouSection(title: sectionTitle, items: sectionItems)))
                })
            }
        case .moreLikeLast:
            if let recentWatchedItem {
                let sectionItems = filteredForYou(model.moreLikeLastWatched)
                if !sectionItems.isEmpty {
                    let sectionTitle = "More like \(recentWatchedItem.title)"
                    MediaSection(title: sectionTitle, items: sectionItems, hideWatchedForUpcoming: false, model: model, openFull: {
                        forYouPath.append(.section(ForYouSection(title: sectionTitle, items: sectionItems)))
                    })
                }
            }
        case .moreLikeFavourite:
            if let favouriteItem {
                let sectionItems = filteredForYou(model.moreLikeFavourite)
                if !sectionItems.isEmpty {
                    let sectionTitle = "More like a favourite \(favouriteItem.kind.label.lowercased()): \(favouriteItem.title)"
                    MediaSection(title: sectionTitle, items: sectionItems, hideWatchedForUpcoming: false, model: model, openFull: {
                        forYouPath.append(.section(ForYouSection(title: sectionTitle, items: sectionItems)))
                    })
                }
            }
        case .watchlistPicks:
            if !watchlistPicks.isEmpty {
                let sectionTitle = "From your watchlist"
                let sectionItems = watchlistPicks
                MediaSection(title: sectionTitle, items: sectionItems, hideWatchedForUpcoming: false, model: model, openFull: {
                    forYouPath.append(.section(ForYouSection(title: sectionTitle, items: sectionItems)))
                })
            }
        case .seriesNext:
            let sectionItems = filteredForYou(model.seriesNext)
            if !sectionItems.isEmpty {
                let sectionTitle = "Continue with related series"
                MediaSection(title: sectionTitle, items: sectionItems, hideWatchedForUpcoming: false, model: model, openFull: {
                    forYouPath.append(.section(ForYouSection(title: sectionTitle, items: sectionItems)))
                })
            }
        }
    }
}
