import SwiftUI

// MARK: - Search

struct SearchView: View {
    @ObservedObject var model: VestigoModel
    @State private var showingThematicSearch = false
    @FocusState private var searchIsFocused: Bool
    @State private var searchTask: Task<Void, Never>? = nil

    var body: some View {
        BaseScreen(title: "Search", filter: .constant(model.searchFilter.mediaFilter ?? .movie), settings: model.settings, onRefresh: {
            await model.refreshSearch()
        }) {
            VStack(spacing: 18) {
                SearchBubble(text: $model.searchText, isFocused: $searchIsFocused) {
                    commitSearchInput()
                }
                .onChange(of: model.searchText) { _, _ in
                    searchTask?.cancel()
                    searchTask = Task {
                        try? await Task.sleep(for: .milliseconds(1000))
                        guard !Task.isCancelled else { return }
                        model.updateSearch()
                    }
                }
                .onChange(of: searchIsFocused) { _, newValue in
                    if !newValue {
                        commitSearchInput()
                    } else {
                        model.searchFieldIsFocused = true
                    }
                }
                .onChange(of: model.searchFieldIsFocused) { _, isFocused in
                    if !isFocused { searchIsFocused = false }
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
                    if searchIsFocused {
                        RecentlyViewedList(items: model.settings.recentlyViewedItems, model: model)
                    } else {
                    if ThematicSearchService.isAvailable {
                            Button {
                                searchIsFocused = false
                                model.searchFieldIsFocused = false
                                showingThematicSearch = true
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "sparkles")
                                        .font(.title3.bold())
                                        .foregroundStyle(.primary)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Don't know the name?")
                                            .font(.subheadline.bold())
                                            .foregroundStyle(.primary)
                                        Text("Describe it and we'll find it")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                }
                                .padding(14)
                                .liquidGlass(cornerRadius: 24)
                            }
                            .buttonStyle(.plain)
                            .sheet(isPresented: $showingThematicSearch) {
                                ThematicSearchView(model: model)
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
                    } // end else (not focused)
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
        searchTask?.cancel()
        searchTask = nil
        searchIsFocused = false
        model.searchFieldIsFocused = false
        model.searchText = model.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if model.searchText.isEmpty { model.searchPath.removeAll() }
        model.updateSearch()
    }

}

struct RecentlyViewedList: View {
    let items: [MediaItem]
    @ObservedObject var model: VestigoModel

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Recently Viewed")
                    .sectionTitle()
                VStack(spacing: 8) {
                    ForEach(items) { item in
                        Button { model.selectedItem = item } label: {
                            HStack(spacing: 12) {
                                PosterView(item: item, width: 36, height: 54, isFavourite: false)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(item.releaseYearText)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    let rating = model.ratingDisplayText(for: item)
                                    if !rating.isEmpty {
                                        Text(rating)
                                            .font(.caption2.bold())
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .liquidGlass(cornerRadius: 18)
                    }
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
