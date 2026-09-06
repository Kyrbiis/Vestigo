import SwiftUI

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
            LazyVStack(spacing: 12) {
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
