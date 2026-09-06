import SwiftUI
import Foundation
import Combine

extension VestigoModel {

    func selectTab(_ tab: AppTab) {
        guard tab != selectedTab else {
            reselectCurrentTab()
            return
        }

        tabTransitionDirection = tab.sortIndex > selectedTab.sortIndex ? .forward : .backward
        selectedTab = tab

        if tab == .friends {
            Task { await loadFriends() }
        }
    }

    func reselectCurrentTab() {
        if selectedTab == .search && searchFieldIsFocused {
            searchFieldIsFocused = false
            return
        }
        if isAtRoot(selectedTab) {
            reloadRoot(for: selectedTab)
        } else {
            resetPath(for: selectedTab)
        }
    }

    func goBack() {
        if selectedPerson != nil {
            selectedPerson = nil
            return
        }

        if selectedItem != nil {
            selectedItem = nil
            return
        }

        switch selectedTab {
        case .home:
            if !homePath.isEmpty { homePath.removeLast() }
        case .search:
            if !searchPath.isEmpty { searchPath.removeLast() }
        case .watchlist, .collections, .friends:
            break
        }
    }

    func isAtRoot(_ tab: AppTab) -> Bool {
        switch tab {
        case .home:
            return homePath.isEmpty && selectedItem == nil && selectedPerson == nil
        case .search:
            return searchPath.isEmpty && selectedItem == nil && selectedPerson == nil
        case .watchlist, .collections, .friends:
            return selectedItem == nil && selectedPerson == nil
        }
    }

    func resetPath(for tab: AppTab) {
        selectedItem = nil
        selectedPerson = nil

        switch tab {
        case .home:
            homePath.removeAll()
        case .search:
            searchPath.removeAll()
        case .watchlist, .collections, .friends:
            break
        }
    }

    func reloadRoot(for tab: AppTab) {
        selectedItem = nil
        selectedPerson = nil

        switch tab {
        case .home:
            homePath.removeAll()
            mediaFilter = settings.defaultHomeFilter
            homeViewMode = .tile
            Task { await loadHome() }
            Task { await loadSmartRecommendations() }

        case .search:
            searchPath.removeAll()
            searchViewMode = .tile
            searchText = ""
            searchResults = []
            searchPeopleResults = []
            searchFieldIsFocused = false
            searchFiltersExpanded = false
            expandedSearchFilterSections.removeAll()
            selectedRuntimeFilters.removeAll()
            selectedDateFilters.removeAll()
            minimumTMDbRatingFilter = nil
            searchFilter = settings.defaultSearchFilter

        case .friends:
            friendsResetToken = UUID()

        case .watchlist:
            sortOption = .tmdbRating
            watchlistResetToken = UUID()
            objectWillChange.send()

        case .collections:
            collectionsResetToken = UUID()
            objectWillChange.send()
        }
    }

    func generateDynamicCollections(from item: MediaItem) {
        library.items[item.key] = item
        let seriesNames = DynamicCollections.inferredSeriesNames(for: item)
        let broadNames = DynamicCollections.broadCollections(for: item)
        for name in (seriesNames + broadNames) {
            if let index = library.collections.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                library.collections[index].itemKeys.insert(item.key)
            } else {
                var collection = MediaCollection(name: name, isDynamic: true)
                collection.itemKeys.insert(item.key)
                library.collections.append(collection)
            }
        }
    }

}
