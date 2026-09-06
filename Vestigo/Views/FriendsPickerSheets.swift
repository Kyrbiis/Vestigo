import SwiftUI
import Foundation

// MARK: - Picker Support Enums

enum PickerSource { case watched, watchlist, both }
enum PickerKind { case movies, series, both }

// MARK: - Featured Picker Sheet

struct FeaturedPickerSheet: View {
    @ObservedObject var model: VestigoModel
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var searchText = ""
    @State private var sourceFilter: PickerSource = .both
    @State private var kindFilter: PickerKind = .both
    @State private var sortedItems: [MediaItem] = []

    private let maxItems = 6
    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    private func recomputeSortedItems() {
        let sourceItems: [MediaItem]
        switch sourceFilter {
        case .watched:   sourceItems = model.library.watchedItems
        case .watchlist: sourceItems = model.library.watchlistItems
        case .both:      sourceItems = model.library.watchedItems + model.library.watchlistItems
        }
        sortedItems = sourceItems
            .uniqued()
            .filter { item in
                switch kindFilter {
                case .movies: return item.key.kind == .movie
                case .series: return item.key.kind == .tv
                case .both:   return true
                }
            }
            .sorted {
                let aSel = selected.contains($0.key.stableID)
                let bSel = selected.contains($1.key.stableID)
                if aSel != bSel { return aSel }
                let aFav = model.library.isFavourite($0)
                let bFav = model.library.isFavourite($1)
                if aFav != bFav { return aFav }
                return $0.voteAverage > $1.voteAverage
            }
    }

    private var libraryItems: [MediaItem] {
        if searchText.isEmpty { return sortedItems }
        let q = searchText.lowercased()
        return sortedItems.filter { $0.title.lowercased().contains(q) }
    }

    private func save() {
        model.settings.socialFeaturedItemKeys = Array(selected)
        model.saveSettings()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text("Choose Featured")
                        .font(.title2.bold())
                    Spacer()
                    Button("Done") {
                        save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search library", text: $searchText)
                }
                .padding(12)
                .liquidGlass(cornerRadius: 20)

                HStack {
                    Text("\(selected.count)/\(maxItems) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset to Favourites") {
                        model.settings.socialFeaturedItemKeys = []
                        model.saveSettings()
                        dismiss()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Picker("Source", selection: $sourceFilter) {
                    Text("Watched").tag(PickerSource.watched)
                    Text("Watchlist").tag(PickerSource.watchlist)
                    Text("Both").tag(PickerSource.both)
                }
                .pickerStyle(.segmented)

                Picker("Type", selection: $kindFilter) {
                    Text("Movies").tag(PickerKind.movies)
                    Text("Series").tag(PickerKind.series)
                    Text("Both").tag(PickerKind.both)
                }
                .pickerStyle(.segmented)

                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(libraryItems) { item in
                        let stableID = item.key.stableID
                        let isSelected = selected.contains(stableID)
                        Button {
                            if isSelected {
                                selected.remove(stableID)
                            } else if selected.count < maxItems {
                                selected.insert(stableID)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                ZStack(alignment: .topTrailing) {
                                    PosterView(item: item, width: 100, height: 150, isFavourite: model.library.isFavourite(item))
                                        .opacity(isSelected ? 1 : 0.55)
                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.title3.bold())
                                            .foregroundStyle(.white)
                                            .background(.black.opacity(0.55), in: Circle())
                                            .padding(6)
                                    }
                                }
                                Text(item.title)
                                    .font(.caption.bold())
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if model.library.isWatched(item.key) {
                                    if let rating = model.library.ratings[item.key] {
                                        Text("\(rating.formatted(.number.precision(.fractionLength(0...1)))) stars")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("Watched, unrated")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                } else {
                                    Text("On watchlist")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!isSelected && selected.count >= maxItems)
                    }
                }
            }
            .padding(18)
            .padding(.bottom, 110)
        }
        .scrollClipDisabled()
        .scrollDismissesKeyboard(.immediately)
        .scrollIndicators(.hidden)
        .scrollViewTouchTuning()
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
        .onAppear {
            selected = Set(model.settings.socialFeaturedItemKeys)
            recomputeSortedItems()
        }
        .onDisappear { save() }
        .onChange(of: sourceFilter) { _, _ in recomputeSortedItems() }
        .onChange(of: kindFilter) { _, _ in recomputeSortedItems() }
    }
}

// MARK: - Excited For Picker Sheet

struct ExcitedForPickerSheet: View {
    @ObservedObject var model: VestigoModel
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var searchText = ""
    @State private var baseItems: [MediaItem] = []
    @State private var isSearchingRemote = false
    @State private var remoteTask: Task<Void, Never>? = nil
    @State private var kindFilter: PickerKind = .both

    private let maxItems = 6
    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    private func save() {
        model.settings.socialExcitedForKeys = Array(selected)
        let selectedItems = baseItems.filter { selected.contains($0.key.stableID) }
        var cache = model.settings.socialExcitedForItemCache
        for item in selectedItems {
            cache.removeAll { $0.key == item.key }
            cache.append(item)
        }
        model.settings.socialExcitedForItemCache = cache
        model.saveSettings()
    }

    private func applyKind(_ items: [MediaItem]) -> [MediaItem] {
        switch kindFilter {
        case .movies: return items.filter { $0.key.kind == .movie }
        case .series: return items.filter { $0.key.kind == .tv }
        case .both:   return items
        }
    }

    private func buildBaseItems() {
        let today = Calendar.current.startOfDay(for: Date())
        let fromFeed = model.upcoming
        let fromLibrary = model.library.items.values.filter { item in
            guard let d = item.releaseDateValue else { return false }
            return d > today
        }
        let cacheItems = model.settings.socialExcitedForItemCache
        baseItems = (fromFeed + Array(fromLibrary) + cacheItems)
            .uniqued()
            .filter { item in
                if let d = item.releaseDateValue { return d > today }
                return true
            }
            .sorted {
                let aSel = selected.contains($0.key.stableID)
                let bSel = selected.contains($1.key.stableID)
                if aSel != bSel { return aSel }
                return ($0.releaseDateValue ?? .distantFuture) < ($1.releaseDateValue ?? .distantFuture)
            }
    }

    private var displayItems: [MediaItem] {
        let kindFiltered = applyKind(baseItems)
        if searchText.isEmpty { return kindFiltered }
        let q = searchText.lowercased()
        return kindFiltered.filter { $0.title.lowercased().contains(q) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text("Excited For")
                        .font(.title2.bold())
                    Spacer()
                    Button("Done") {
                        save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }

                HStack(spacing: 8) {
                    if isSearchingRemote {
                        ProgressView().scaleEffect(0.75)
                    } else {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    }
                    TextField("Search upcoming & library", text: $searchText)
                }
                .padding(12)
                .liquidGlass(cornerRadius: 20)

                Text("\(selected.count)/\(maxItems) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Type", selection: $kindFilter) {
                    Text("Movies").tag(PickerKind.movies)
                    Text("Series").tag(PickerKind.series)
                    Text("Both").tag(PickerKind.both)
                }
                .pickerStyle(.segmented)

                if displayItems.isEmpty {
                    if isSearchingRemote {
                        LoadingBubble(title: "Searching", text: "Looking up upcoming releases…")
                    } else {
                        StatusBubble(
                            title: searchText.isEmpty ? "No upcoming items" : "No results",
                            text: searchText.isEmpty ? "Upcoming releases will appear here when they're available." : "Try a different search term."
                        )
                    }
                } else {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(displayItems) { item in
                            let stableID = item.key.stableID
                            let isSelected = selected.contains(stableID)
                            Button {
                                if isSelected { selected.remove(stableID) } else if selected.count < maxItems { selected.insert(stableID) }
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    ZStack(alignment: .topTrailing) {
                                        PosterView(item: item, width: 100, height: 150, isFavourite: false)
                                            .opacity(isSelected ? 1 : 0.55)
                                        if isSelected {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.title3.bold())
                                                .foregroundStyle(.white)
                                                .background(.black.opacity(0.55), in: Circle())
                                                .padding(6)
                                        }
                                    }
                                    Text(item.title)
                                        .font(.caption.bold())
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    if let date = item.releaseDateValue {
                                        Text(date.formatted(date: .abbreviated, time: .omitted))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("TBA")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(18)
            .padding(.bottom, 110)
        }
        .scrollClipDisabled()
        .scrollDismissesKeyboard(.immediately)
        .scrollIndicators(.hidden)
        .scrollViewTouchTuning()
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
        .onAppear {
            selected = Set(model.settings.socialExcitedForKeys)
            buildBaseItems()
        }
        .onDisappear { save() }
        .onChange(of: searchText) { _, text in
            remoteTask?.cancel()
            guard !text.isEmpty else { return }
            remoteTask = Task {
                try? await Task.sleep(nanoseconds: 600_000_000)
                guard !Task.isCancelled else { return }
                let q = text.lowercased()
                let localCount = applyKind(baseItems).filter { $0.title.lowercased().contains(q) }.count
                if localCount < 5 {
                    isSearchingRemote = true
                    let found = await model.quickSearch(query: text)
                    model.cacheUpcomingItems(from: found)
                    let today = Calendar.current.startOfDay(for: Date())
                    for item in found {
                        guard !baseItems.contains(where: { $0.key == item.key }) else { continue }
                        if let d = item.releaseDateValue { guard d > today else { continue } }
                        baseItems.append(item)
                    }
                    isSearchingRemote = false
                }
            }
        }
    }
}
