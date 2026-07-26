import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
struct ThematicSearchView: View {
    @ObservedObject var model: VestigoModel
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var filter: MediaFilter = .both
    @State private var results: [ThematicSearchResult] = []
    @State private var isLoading = false
    @State private var hasSearched = false
    @State private var errorMessage: String?
    @FocusState private var inputFocused: Bool

    private var canSearch: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                inputPanel
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 14)

                Divider()
                    .opacity(0.4)

                ScrollView {
                    LazyVStack(spacing: 10) {
                        if isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.top, 50)
                        } else if let error = errorMessage {
                            StatusBubble(title: "Search failed", text: error)
                                .padding(.top, 20)
                        } else if hasSearched && results.isEmpty {
                            StatusBubble(title: "No matches found", text: "Try rewording your description or adding more detail.")
                                .padding(.top, 20)
                        } else {
                            ForEach(results) { result in
                                ThematicResultRow(result: result, model: model)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("Describe It")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { inputFocused = true }
    }

    private var inputPanel: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $query)
                    .focused($inputFocused)
                    .font(.body)
                    .frame(minHeight: 76, maxHeight: 148)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .scrollContentBackground(.hidden)

                if query.isEmpty {
                    Text("Describe a film or show…\ne.g. the sprinter who competed at the 1936 Olympics")
                        .foregroundStyle(.tertiary)
                        .font(.body)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
            }
            .liquidGlass(cornerRadius: 18)

            HStack(spacing: 10) {
                Picker("Type", selection: $filter) {
                    Text("Both").tag(MediaFilter.both)
                    Text("Movies").tag(MediaFilter.movie)
                    Text("TV").tag(MediaFilter.tv)
                }
                .pickerStyle(.segmented)

                Button(action: performSearch) {
                    ZStack {
                        Circle()
                            .fill(canSearch ? Color.primary : Color.secondary.opacity(0.35))
                            .frame(width: 38, height: 38)
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(canSearch ? Color(uiColor: .systemBackground) : .secondary)
                    }
                }
                .disabled(!canSearch)
            }

            if hasSearched {
                Button {
                    inputFocused = true
                } label: {
                    Label("Amend search", systemImage: "pencil")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .liquidGlass(cornerRadius: 18)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func performSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        inputFocused = false
        isLoading = true
        errorMessage = nil
        results = []
        Task {
            do {
                results = try await model.thematicSearch(query: trimmed, filter: filter)
                hasSearched = true
            } catch {
                errorMessage = error.localizedDescription
                hasSearched = true
            }
            isLoading = false
        }
    }
}

@available(iOS 26.0, macOS 26.0, *)
private struct ThematicResultRow: View {
    let result: ThematicSearchResult
    @ObservedObject var model: VestigoModel

    var body: some View {
        Button {
            model.selectedItem = result.item
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
