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

// MARK: - Search

struct SearchView: View {
    @ObservedObject var model: VestigoModel
    @State private var searchHistory: [String] = []
    @FocusState private var searchIsFocused: Bool
    private let maxSearchHistoryCount = 8
    
    var body: some View {
        BaseScreen(title: "Search", filter: .constant(model.searchFilter.mediaFilter ?? .movie), settings: model.settings, onRefresh: {
            await model.refreshSearch()
        }) {
            VStack(spacing: 18) {
                SearchBubble(text: $model.searchText, isFocused: $searchIsFocused) {
                    commitSearchInput()
                }
                .onChange(of: model.searchText) { _, _ in model.updateSearch() }
                .onChange(of: searchIsFocused) { _, newValue in
                    if !newValue {
                        commitSearchInput()
                    } else {
                        model.searchFieldIsFocused = true
                    }
                }
                if !model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    SearchFilterPills(filter: $model.searchFilter) {
                        model.updateSearch()
                    }

                    if model.searchFilter != .people {
                        SearchFiltersPanel(model: model)
                    }
                }

                if model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if !searchHistory.isEmpty {
                        SearchHistoryList(entries: searchHistory) { entry in
                            model.searchText = entry
                            model.updateSearch()
                        } clearEntry: { entry in
                            searchHistory.removeAll { $0 == entry }
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Charts")
                            .sectionTitle()
                        VStack(spacing: 10) {
                            Button {
                                searchIsFocused = false
                                model.searchFieldIsFocused = false
                                model.searchPath.append(.chart(.movie))
                            } label: {
                                ChartTile(title: "Top Rated Movies", icon: "trophy.fill", colors: [Color(red: 0.55, green: 0.43, blue: 0.08), Color(red: 0.28, green: 0.20, blue: 0.04)])
                            }
                            .buttonStyle(.plain)
                            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                            Button {
                                searchIsFocused = false
                                model.searchFieldIsFocused = false
                                model.searchPath.append(.chart(.tv))
                            } label: {
                                ChartTile(title: "Top Rated TV", icon: "trophy.fill", colors: [Color(red: 0.12, green: 0.35, blue: 0.55), Color(red: 0.06, green: 0.16, blue: 0.30)])
                            }
                            .buttonStyle(.plain)
                            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Genres")
                            .sectionTitle()
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                            ForEach(GenreDefinition.all) { genre in
                                Button {
                                    searchIsFocused = false
                                    model.searchFieldIsFocused = false
                                    model.searchPath.append(.genre(GenreRoute(genre: genre)))
                                } label: {
                                    GenreIconTile(genre: genre)
                                }
                                .buttonStyle(.plain)
                                .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            }
                        }
                    }
                } else {
                    if model.searchFilter == .people {
                        PeopleSearchResults(people: model.searchPeopleResults, model: model)
                    } else {
                        MediaGridOrList(items: model.filteredSearchResults, hideWatchedForUpcoming: false, model: model)
                    }
                }
            }
        }
    }
    
    private func commitSearchInput() {
        searchIsFocused = false
        model.searchFieldIsFocused = false
        model.searchText = model.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        saveCurrentSearchToHistory()
        model.updateSearch()
    }
    
    private func saveCurrentSearchToHistory() {
        let trimmed = model.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        searchHistory.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        searchHistory.insert(trimmed, at: 0)

        if searchHistory.count > maxSearchHistoryCount {
            searchHistory = Array(searchHistory.prefix(maxSearchHistoryCount))
        }
    }

}

struct SearchHistoryList: View {
    let entries: [String]
    let selectEntry: (String) -> Void
    let clearEntry: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent searches")
                .sectionTitle()

            VStack(spacing: 8) {
                ForEach(entries, id: \.self) { entry in
                    HStack(spacing: 10) {
                        Button {
                            selectEntry(entry)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.caption.bold())
                                Text(entry)
                                    .font(.subheadline.bold())
                                    .lineLimit(1)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Button {
                            clearEntry(entry)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 42)
                    .liquidGlass(cornerRadius: 18)
                }
            }
        }
    }
}

struct SearchFilterPills: View {
    @Binding var filter: SearchFilter
    let onChange: () -> Void

    var body: some View {
        Picker("Search type", selection: $filter) {
            ForEach(SearchFilter.allCases) { item in
                Text(item.title).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .liquidGlass(cornerRadius: 18)
        .onChange(of: filter) { _, _ in
            onChange()
        }
    }
}

struct GenreSortPicker: View {
    @Binding var sort: GenreSort
    let onChange: () -> Void

    var body: some View {
        Picker("Sort", selection: $sort) {
            ForEach(GenreSort.allCases) { item in
                Text(item.title).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .liquidGlass(cornerRadius: 18)
        .onChange(of: sort) { _, _ in
            onChange()
        }
    }
}

struct SearchFiltersPanel: View {
    @ObservedObject var model: VestigoModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                    model.searchFiltersExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Label(filterButtonTitle, systemImage: "line.3.horizontal.decrease.circle")
                        .font(.caption.bold())

                    Spacer(minLength: 0)

                    if model.searchFiltersExpanded {
                        Button {
                            model.clearSearchFilters()
                        } label: {
                            Text("Clear all")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                    }

                    Image(systemName: "chevron.down")
                        .font(.caption.bold())
                        .rotationEffect(.degrees(model.searchFiltersExpanded ? 180 : 0))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .frame(height: 34)
            }
            .buttonStyle(.plain)
            .focusable(false)

            if model.searchFiltersExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    runtimeSection
                    ratingSection
                    dateSection
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(3)
        .liquidGlass(cornerRadius: 18)
    }

    private var filterButtonTitle: String {
        let count = model.activeSearchFilterCount
        return count == 0 ? "Filters" : "Filters (\(count))"
    }

    private var runtimeSection: some View {
        SearchFilterDisclosureSection(
            section: .runtime,
            expandedSections: $model.expandedSearchFilterSections,
            summary: runtimeSummary
        ) {
            SearchChipWrap {
                ForEach(SearchRuntimeFilter.allCases) { filter in
                    SearchFilterChip(
                        title: filter.title,
                        isSelected: model.selectedRuntimeFilters.contains(filter)
                    ) {
                        if model.selectedRuntimeFilters.contains(filter) {
                            model.selectedRuntimeFilters.remove(filter)
                        } else {
                            model.selectedRuntimeFilters.insert(filter)
                        }

                        model.refreshRuntimeFilteredSearchIfNeeded()
                    }
                }
            }
        }
    }

    private var ratingSection: some View {
        SearchFilterDisclosureSection(
            section: .rating,
            expandedSections: $model.expandedSearchFilterSections,
            summary: ratingSummary
        ) {
            SearchChipWrap {
                ForEach(SearchRatingFilter.allCases) { filter in
                    SearchFilterChip(
                        title: filter.title,
                        isSelected: model.minimumTMDbRatingFilter == filter
                    ) {
                        if model.minimumTMDbRatingFilter == filter {
                            model.minimumTMDbRatingFilter = nil
                        } else {
                            model.minimumTMDbRatingFilter = filter
                        }
                    }
                }
            }
        }
    }

    private var dateSection: some View {
        SearchFilterDisclosureSection(
            section: .date,
            expandedSections: $model.expandedSearchFilterSections,
            summary: dateSummary
        ) {
            SearchChipWrap {
                ForEach(SearchDateFilter.allCases) { filter in
                    SearchFilterChip(
                        title: filter.title,
                        isSelected: model.selectedDateFilters.contains(filter)
                    ) {
                        if model.selectedDateFilters.contains(filter) {
                            model.selectedDateFilters.remove(filter)
                        } else {
                            model.selectedDateFilters.insert(filter)
                        }
                    }
                }
            }
        }
    }

    private var runtimeSummary: String? {
        guard !model.selectedRuntimeFilters.isEmpty else { return nil }

        return SearchRuntimeFilter.allCases
            .filter { model.selectedRuntimeFilters.contains($0) }
            .map(\.title)
            .joined(separator: ", ")
    }

    private var ratingSummary: String? {
        model.minimumTMDbRatingFilter?.title
    }

    private var dateSummary: String? {
        guard !model.selectedDateFilters.isEmpty else { return nil }

        return SearchDateFilter.allCases
            .filter { model.selectedDateFilters.contains($0) }
            .map(\.title)
            .joined(separator: ", ")
    }
}

struct SearchFilterDisclosureSection<Content: View>: View {
    let section: SearchFilterSection
    @Binding var expandedSections: Set<SearchFilterSection>
    let summary: String?
    @ViewBuilder let content: Content

    private var isExpanded: Bool {
        expandedSections.contains(section)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    if isExpanded {
                        expandedSections.remove(section)
                    } else {
                        expandedSections.insert(section)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(summary == nil ? section.title : "\(section.title) • \(summary!)")
                        .font(.caption.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.down")
                        .font(.caption.bold())
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(.white.opacity(summary == nil ? 0.08 : 0.14), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            }
            .buttonStyle(.plain)
            .focusable(false)

            if isExpanded {
                content
                    .padding(.horizontal, 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(8)
        .liquidGlass(cornerRadius: 22)
    }
}

struct SearchChipWrap<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 8)], alignment: .leading, spacing: 8) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SearchFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(.white.opacity(isSelected ? 0.20 : 0.08), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(isSelected ? 0.24 : 0.10), lineWidth: 1)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}

struct MixedSearchResults: View {
    let mediaItems: [MediaItem]
    let people: [PersonSummary]
    @ObservedObject var model: VestigoModel

    private var mediaChunks: [[MediaItem]] {
        stride(from: 0, to: mediaItems.count, by: 2).map { start in
            Array(mediaItems[start..<min(start + 2, mediaItems.count)])
        }
    }

    var body: some View {
        if mediaItems.isEmpty && people.isEmpty {
            StatusBubble(title: "No results", text: "No movies, series, or people matched this search.")
        } else {
            VStack(spacing: 16) {
                ForEach(Array(mediaChunks.enumerated()), id: \.offset) { index, chunk in
                    MediaGridOrList(items: chunk, hideWatchedForUpcoming: false, model: model)

                    let personStart = index * 2
                    let personEnd = min(personStart + 2, people.count)

                    if personStart < personEnd {
                        VStack(spacing: 12) {
                            ForEach(Array(people[personStart..<personEnd])) { person in
                                PersonSearchResultRow(person: person, model: model, expanded: true)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                if mediaChunks.isEmpty {
                    VStack(spacing: 12) {
                        ForEach(people.prefix(8)) { person in
                            PersonSearchResultRow(person: person, model: model, expanded: true)
                        }
                    }
                    .padding(.vertical, 4)
                } else if people.count > mediaChunks.count * 2 {
                    VStack(spacing: 12) {
                        ForEach(Array(people.dropFirst(mediaChunks.count * 2).prefix(4))) { person in
                            PersonSearchResultRow(person: person, model: model, expanded: true)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

struct PeopleSearchResults: View {
    let people: [PersonSummary]
    @ObservedObject var model: VestigoModel

    var body: some View {
        if people.isEmpty {
            StatusBubble(title: "No people found", text: "No actors, directors, producers, or other credited people matched this search.")
        } else {
            VStack(spacing: 12) {
                ForEach(people) { person in
                    Button {
                        model.selectedPerson = person
                    } label: {
                        HStack(spacing: 12) {
                            PersonImageView(person: person, width: 58, height: 76)

                            VStack(alignment: .leading, spacing: 5) {
                                Text(person.name)
                                    .font(.headline.bold())
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)

                                Text(person.role.isEmpty ? "Known for" : person.role)
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .liquidGlass(cornerRadius: 22)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct GenreResultsView: View {
    let route: GenreRoute
    @ObservedObject var model: VestigoModel
    @State private var genreFilter: MediaFilter = .both
    @State private var genreSort: GenreSort = .tmdbRating
    @State private var genreSortDirection: SortDirection = .descending

    private var cacheKey: String {
        model.genreCacheKey(genreID: route.genre.tmdbID, filter: genreFilter, sort: genreSort)
    }

    private var displayedItems: [MediaItem] {
        let items = model.genreResults[cacheKey] ?? []
        return genreSortDirection == .ascending ? Array(items.reversed()) : items
    }

    var body: some View {
        BaseScreen(title: route.genre.name, filter: $genreFilter, settings: model.settings, onRefresh: {
            await model.loadGenre(route.genre, filter: genreFilter, sort: genreSort, forceRefresh: true)
        }) {
            VStack(spacing: 14) {
                FilterPills(filter: $genreFilter, options: [.movie, .tv, .both]) {
                    Task { await model.loadGenre(route.genre, filter: genreFilter, sort: genreSort) }
                }

                SortRow(direction: $genreSortDirection) {
                    GenreSortPicker(sort: $genreSort) {
                        Task { await model.loadGenre(route.genre, filter: genreFilter, sort: genreSort) }
                    }
                }

                MediaGridOrList(
                    items: displayedItems,
                    hideWatchedForUpcoming: false,
                    model: model
                )
            }
        }
        .task {
            genreSort = model.settings.defaultCategorySort
            await model.loadGenre(route.genre, filter: genreFilter, sort: genreSort)
        }
        .onChange(of: genreFilter) { _, newValue in
            Task { await model.loadGenre(route.genre, filter: newValue, sort: genreSort) }
        }
        .onChange(of: genreSort) { _, newValue in
            Task { await model.loadGenre(route.genre, filter: genreFilter, sort: newValue) }
        }
    }
}

// MARK: - Charts

private struct ChartTile: View {
    let title: String
    let icon: String
    let colors: [Color]

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white.opacity(0.88))
            Text(title)
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
    }
}

struct ChartResultsView: View {
    let kind: MediaKind
    @ObservedObject var model: VestigoModel
    @State private var hasLoaded = false
    @Environment(\.imageRefreshToken) private var imageRefreshToken

    private var items: [MediaItem] {
        kind == .movie ? model.topRatedMovies : model.topRatedShows
    }

    var body: some View {
        BaseScreen(
            title: kind == .movie ? "Top Rated Movies" : "Top Rated TV Shows",
            filter: .constant(.both),
            settings: model.settings,
            onRefresh: { await model.loadTopRated(kind: kind) }
        ) {
            if items.isEmpty {
                LoadingBubble(title: "Building chart", text: "Fetching ratings…")
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(Array(items.prefix(100).enumerated()), id: \.element.key) { index, item in
                        ChartItemRow(rank: index + 1, item: item, model: model, imageRefreshToken: imageRefreshToken)
                    }
                }
            }
        }
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await model.loadTopRated(kind: kind)
        }
    }
}

private struct ChartItemRow: View {
    let rank: Int
    let item: MediaItem
    @ObservedObject var model: VestigoModel
    let imageRefreshToken: Int

    private var posterURL: URL? {
        item.posterPath.flatMap { URL(string: "https://image.tmdb.org/t/p/w185\($0)") }
    }

    var body: some View {
        Button {
            model.selectedItem = item
        } label: {
            HStack(spacing: 14) {
                Text("\(rank)")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .trailing)
                    .monospacedDigit()

                AsyncImage(url: posterURL?.refreshedImageURL(token: imageRefreshToken)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(.white.opacity(0.1))
                    }
                }
                .frame(width: 44, height: 66)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    let ratingText = model.ratingDisplayText(for: item)
                    if !ratingText.isEmpty {
                        Text(ratingText)
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }

                    Text(item.releaseYearText)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
