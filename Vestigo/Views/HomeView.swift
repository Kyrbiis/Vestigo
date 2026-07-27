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

// MARK: - Home

struct HomeView: View {
    @ObservedObject var model: VestigoModel
    
    var body: some View {
        BaseScreen(
            title: "Vestigo",
            filter: $model.mediaFilter,
            settings: model.settings,
            headerAccessory: AnyView(
                Button {
                    model.homePath.append(.settings)
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
                model.refreshVisibleExternalRatings()
            }
        ) {
            VStack(spacing: 22) {
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
        .onChange(of: model.mediaFilter) { _, _ in Task { await model.loadHome() } }
    }

    @ViewBuilder
    private func homeCarouselView(for carousel: HomeCarousel) -> some View {
        switch carousel {
        case .trending:
            MediaSection(title: carousel.title, items: model.trending, hideWatchedForUpcoming: false, model: model, openFull: {
                model.homePath.append(.trending)
            })
        case .newReleases:
            MediaSection(title: carousel.title, items: model.newReleases, hideWatchedForUpcoming: false, model: model, openFull: {
                model.homePath.append(.newReleases)
            })
        case .upcoming:
            if model.settings.showUpcomingReleases, !model.upcoming.isEmpty {
                MediaSection(title: carousel.title, items: model.upcoming, hideWatchedForUpcoming: true, model: model, openFull: {
                    model.homePath.append(.upcoming)
                })
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
