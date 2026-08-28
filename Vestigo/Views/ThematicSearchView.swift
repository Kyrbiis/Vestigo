import SwiftUI


struct ThematicSearchView: View {
    @ObservedObject var model: VestigoModel

    @State private var query = ""
    @State private var results: [ThematicSearchResult] = []
    @State private var isLoading = false
    @State private var hasSearched = false
    @State private var errorMessage: String?
    @State private var selectedNestedItem: MediaItem?
    @State private var selectedFilter: MediaFilter = .both
    @FocusState private var inputFocused: Bool

    private var canSearch: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }

    private var movieResults: [ThematicSearchResult] { results.filter { $0.item.kind == .movie } }
    private var tvResults: [ThematicSearchResult]    { results.filter { $0.item.kind == .tv } }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                Text("Describe It")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)

                inputPanel
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)

            Divider().opacity(0.3)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 50)
                    } else if let error = errorMessage {
                        StatusBubble(title: "Search failed", text: error)
                    } else if hasSearched && results.isEmpty {
                        StatusBubble(title: "No matches found", text: "Try rewording your description or adding more detail.")
                    } else if hasSearched {
                        resultContent
                    } else {
                        recentSearchesSection
                    }
                }
                .padding(18)
                .padding(.bottom, 110)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Capsule()
                .fill(.white.opacity(0.46))
                .frame(width: 48, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background(.clear)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheetLiquidGlass(cornerRadius: 48)
        .ignoresSafeArea(edges: .bottom)
        .presentationBackground(.clear)
        .presentationCornerRadius(54)
        .sheet(item: $selectedNestedItem) { item in
            DetailView(item: item, model: model)
        }
        .onChange(of: query) { _, newValue in
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                hasSearched = false
                results = []
                errorMessage = nil
            }
        }
        .onAppear { inputFocused = true }
    }

    @ViewBuilder
    private var resultContent: some View {
        switch selectedFilter {
        case .both:
            // Interleaved by score — no section headers
            ForEach(results.sorted { $0.score > $1.score }) { result in
                ThematicResultRow(result: result, model: model) { selectedNestedItem = $0 }
            }

        case .movie:
            sectionBlock("Movies", results: movieResults)

        case .tv:
            sectionBlock("Series", results: tvResults)
        }
    }

    @ViewBuilder
    private var recentSearchesSection: some View {
        let recents = model.settings.describeItRecentSearches
        if !recents.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Recent searches")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    ForEach(recents, id: \.self) { search in
                        Button {
                            query = search
                            performSearch()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "clock")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                Text(search)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "arrow.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .liquidGlass(cornerRadius: 16)
                        }
                        .buttonStyle(.plain)
                        .swipeToDelete(cornerRadius: 16) { model.removeDescribeItRecentSearch(search) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sectionBlock(_ title: String, results: [ThematicSearchResult], topPadding: CGFloat = 0) -> some View {
        if !results.isEmpty {
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .padding(.leading, 2)
                .padding(.top, topPadding)
            ForEach(results) { result in
                ThematicResultRow(result: result, model: model) { selectedNestedItem = $0 }
            }
        }
    }

    private var inputPanel: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $query)
                    .focused($inputFocused)
                    .font(.body)
                    .frame(minHeight: 44, maxHeight: 148)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .scrollContentBackground(.hidden)
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") { inputFocused = false }
                        }
                    }

                if query.isEmpty {
                    Text("Describe a film or show…")
                        .foregroundStyle(.tertiary)
                        .font(.body)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Text("Clear")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(10)
                }
            }
            .liquidGlass(cornerRadius: 18)

            HStack(spacing: 10) {
                Picker("", selection: $selectedFilter) {
                    Text("Movies & TV").tag(MediaFilter.both)
                    Text("Movies").tag(MediaFilter.movie)
                    Text("TV Shows").tag(MediaFilter.tv)
                }
                .pickerStyle(.segmented)

                Button(action: performSearch) {
                    ZStack {
                        Circle()
                            .fill(canSearch ? Color.blue : Color.secondary.opacity(0.35))
                            .frame(width: 38, height: 38)
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .disabled(!canSearch)
            }
        }
    }

    private func detectMediaFilter(from text: String) -> MediaFilter? {
        let lower = text.lowercased()
        let movieWords = ["movie", "movies", "film", "films", "cinema"]
        let tvWords = ["show", "shows", "series", "tv show", "tv series", "television", "episode", "episodes", "season", "seasons"]
        let hasMovie = movieWords.contains { lower.contains($0) }
        let hasTV = tvWords.contains { lower.contains($0) }
        if hasMovie && !hasTV { return .movie }
        if hasTV && !hasMovie { return .tv }
        return nil
    }

    private func performSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let detected = detectMediaFilter(from: trimmed) {
            selectedFilter = detected
        }

        inputFocused = false

        let cacheKey = trimmed.lowercased()
        if let cached = model.describeItResultsCache[cacheKey] {
            results = cached
            hasSearched = true
            return
        }

        isLoading = true
        errorMessage = nil
        results = []

        Task {
            do {
                let fetched = try await model.thematicSearch(query: trimmed, filter: .both)
                results = fetched
                model.describeItResultsCache[cacheKey] = fetched
                model.saveDescribeItRecentSearch(trimmed) // also triggers saveLocalSoon
                hasSearched = true
            } catch {
                errorMessage = error.localizedDescription
                hasSearched = true
            }
            isLoading = false
        }
    }
}

private struct ThematicResultRow: View {
    let result: ThematicSearchResult
    @ObservedObject var model: VestigoModel
    let openItem: (MediaItem) -> Void

    var body: some View {
        Button {
            openItem(result.item)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                PosterView(item: result.item, width: 58, height: 84, isFavourite: model.library.isFavourite(result.item))

                VStack(alignment: .leading, spacing: 5) {
                    Text(result.item.title)
                        .font(.headline.bold())
                        .lineLimit(2)
                        .foregroundStyle(.primary)

                    Text(rowMetadata)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if !result.matchedFacets.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 5) {
                                ForEach(result.matchedFacets, id: \.self) { facet in
                                    Text(facet)
                                        .font(.caption2.bold())
                                        .foregroundStyle(.primary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(.white.opacity(0.12), in: Capsule())
                                        .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 0.5))
                                }
                            }
                        }
                        .padding(.top, 2)
                    }

                    Spacer(minLength: 0)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .liquidGlass(cornerRadius: 18)
        }
        .buttonStyle(.plain)
    }

    private var rowMetadata: String {
        var parts: [String] = [result.item.releaseDateReadable]
        let ratingText = model.ratingDisplayText(for: result.item)
        if !ratingText.isEmpty { parts.append(ratingText) }
        return parts.joined(separator: " • ")
    }
}
