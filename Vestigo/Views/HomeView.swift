import SwiftUI
import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Home

struct HomeView: View {
    @ObservedObject var model: VestigoModel
    @State private var omdbCalloutDismissed = false

    private var recentWatchedItem: MediaItem? {
        model.library.lastWatchedItem
    }

    private var favouriteItem: MediaItem? {
        model.library.favouriteItems(for: model.mediaFilter).first
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
        BaseScreen(
            title: "Vestigo",
            filter: $model.mediaFilter,
            settings: model.settings,
            headerAccessory: AnyView(
                Button {
                    model.homePath.append(.section(.settings))
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(width: 42, height: 42)
                        .liquidGlass(cornerRadius: 21)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
            ),
            onRefresh: {
                await model.refreshHome()
                await model.loadSmartRecommendations()
                model.refreshVisibleExternalRatings()
            }
        ) {
            VStack(spacing: 22) {
                if !omdbCalloutDismissed
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
                                omdbCalloutDismissed = true
                                model.homePath.append(.section(.settings))
                            } label: {
                                Text("Set Up")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(model.settings.accentColor, in: Capsule())
                                    .foregroundStyle(.white)
                            }
                            Button {
                                omdbCalloutDismissed = true
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

                if let error = model.errorText {
                    StatusBubble(title: "Load error", text: error)
                }

                FilterPills(filter: $model.mediaFilter, options: [.movie, .tv, .both]) {
                    Task { await model.loadHome() }
                }

                if !model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    EmptyView()
                } else {
                    ForEach(model.settings.homeCarouselOrder, id: \.self) { carousel in
                        if !model.settings.homeCarouselHidden.contains(carousel) {
                            homeCarouselView(for: carousel)
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if model.homePath.isEmpty {
                Button {
                    model.homePath.append(.pickForMe)
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
        .onChange(of: model.mediaFilter) { _, _ in Task { await model.loadHome() } }
        .onChange(of: model.pendingPickForMe) { _, isPending in
            if isPending {
                model.homePath.append(.pickForMe)
                model.pendingPickForMe = false
            }
        }
        .task { await model.loadSmartRecommendations() }
    }

    @ViewBuilder
    private func homeCarouselView(for carousel: HomeCarousel) -> some View {
        switch carousel {
        case .trending:
            MediaSection(title: carousel.title, items: model.trending, hideWatchedForUpcoming: false, model: model, openFull: {
                model.homePath.append(.section(.trending))
            })
        case .newReleases:
            MediaSection(title: carousel.title, items: model.newReleases, hideWatchedForUpcoming: false, model: model, openFull: {
                model.homePath.append(.section(.newReleases))
            })
        case .upcoming:
            if model.settings.showUpcomingReleases, !model.upcoming.isEmpty {
                MediaSection(title: carousel.title, items: model.upcoming, hideWatchedForUpcoming: true, model: model, openFull: {
                    model.homePath.append(.section(.upcoming))
                })
            }
        case .recommendations:
            ForEach(model.settings.forYouCarouselOrder, id: \.self) { fyCarousel in
                if !model.settings.forYouCarouselHidden.contains(fyCarousel) {
                    forYouCarouselView(for: fyCarousel)
                }
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
                    model.homePath.append(.forYouSection(ForYouSection(title: sectionTitle, items: sectionItems)))
                })
            }
        case .moreLikeLast:
            if let recentWatchedItem {
                let sectionItems = filteredForYou(model.moreLikeLastWatched)
                if !sectionItems.isEmpty {
                    let sectionTitle = "More like \(recentWatchedItem.title)"
                    MediaSection(title: sectionTitle, items: sectionItems, hideWatchedForUpcoming: false, model: model, openFull: {
                        model.homePath.append(.forYouSection(ForYouSection(title: sectionTitle, items: sectionItems)))
                    })
                }
            }
        case .moreLikeFavourite:
            if let favouriteItem {
                let sectionItems = filteredForYou(model.moreLikeFavourite)
                if !sectionItems.isEmpty {
                    let sectionTitle = "More like a favourite \(favouriteItem.kind.label.lowercased()): \(favouriteItem.title)"
                    MediaSection(title: sectionTitle, items: sectionItems, hideWatchedForUpcoming: false, model: model, openFull: {
                        model.homePath.append(.forYouSection(ForYouSection(title: sectionTitle, items: sectionItems)))
                    })
                }
            }
        case .watchlistPicks:
            if !watchlistPicks.isEmpty {
                let sectionTitle = "From your watchlist"
                let sectionItems = watchlistPicks
                MediaSection(title: sectionTitle, items: sectionItems, hideWatchedForUpcoming: false, model: model, openFull: {
                    model.homePath.append(.forYouSection(ForYouSection(title: sectionTitle, items: sectionItems)))
                })
            }
        case .seriesNext:
            let sectionItems = filteredForYou(model.seriesNext)
            if !sectionItems.isEmpty {
                let sectionTitle = "Continue with related series"
                MediaSection(title: sectionTitle, items: sectionItems, hideWatchedForUpcoming: false, model: model, openFull: {
                    model.homePath.append(.forYouSection(ForYouSection(title: sectionTitle, items: sectionItems)))
                })
            }
        }
    }

    private func filteredForYou(_ items: [MediaItem]) -> [MediaItem] {
        items.filter { item in
            if model.library.isWatched(item.key) { return false }
            if model.settings.hideUpcomingFromRecommended && item.isUpcoming { return false }
            switch model.mediaFilter {
            case .movie: return item.kind == .movie
            case .tv: return item.kind == .tv
            case .both: return true
            }
        }
    }
}

struct FullSectionView: View {
    let route: SectionRoute
    @ObservedObject var model: VestigoModel

    var items: [MediaItem] {
        switch route {
        case .trending: return model.trending
        case .popular: return model.popular
        case .newReleases: return model.newReleases
        case .upcoming: return model.upcoming
        case .settings: return []
        }
    }

    @ViewBuilder
    var body: some View {
        switch route {
        case .settings:
            SettingsView(model: model)
        default:
            BaseScreen(title: route.title, filter: $model.mediaFilter, settings: model.settings, onRefresh: {
                await model.refreshHome()
            }) {
                MediaGridOrList(items: items, hideWatchedForUpcoming: route == .upcoming, model: model)
            }
        }
    }
}
