import SwiftUI
import Foundation

// CollectionDetailMode enum for CollectionDetailView
enum CollectionDetailMode: String, CaseIterable, Identifiable, Hashable {
    case myList
    case recommended

    var id: String { rawValue }

    var title: String {
        switch self {
        case .myList:
            return "My list"
        case .recommended:
            return "Recommended"
        }
    }
}

struct CollectionDetailView: View {
    let collectionID: UUID
    @ObservedObject var model: VestigoModel
    @State private var sort: SortOption = .tmdbRating
    @State private var sortDirection: SortDirection = .descending
    @State private var mode: CollectionDetailMode = .myList
    @State private var isEditing = false
    @State private var selectedKeys = Set<MediaKey>()
    @State private var showRenameAlert = false
    @State private var renameText = ""

    private var collection: MediaCollection? {
        model.library.collections.first { $0.id == collectionID }
    }

    private var items: [MediaItem] {
        guard let collection else { return [] }
        return collection.itemKeys.compactMap { model.library.items[$0] }.sorted(
            using: sort,
            ratings: model.library.ratings,
            externalRatings: model.externalRatingsCache,
            ratingSource: model.settings.preferredRatingSource,
            direction: sortDirection
        )
    }

    private var recommendedItems: [MediaItem] {
        guard let collection else { return [] }
        let existingKeys = Set(collection.itemKeys)

        return (model.collectionRecommendations[collectionID] ?? [])
            .filter { item in
                !existingKeys.contains(item.key)
                && !model.library.isWatched(item.key)
                && (!model.settings.hideUpcomingFromCollectionRecommendations || !item.isUpcoming)
            }
            .sorted(
                using: sort,
                ratings: model.library.ratings,
                externalRatings: model.externalRatingsCache,
                ratingSource: model.settings.preferredRatingSource,
                direction: sortDirection
            )
    }

    private func removeSelected() {
        for key in selectedKeys {
            if let item = model.library.items[key] {
                model.removeFromCollection(item, collectionID: collectionID)
            }
        }
        selectedKeys.removeAll()
        isEditing = false
    }

    var body: some View {
        BaseScreen(
            title: collection?.name ?? "Collection",
            filter: .constant(.both),
            settings: model.settings,
            headerAccessory: AnyView(
                HStack(spacing: 8) {
                    if isEditing {
                        Button {
                            renameText = collection?.name ?? ""
                            showRenameAlert = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.body)
                                .foregroundStyle(.primary)
                                .frame(width: 42, height: 42)
                                .liquidGlass(cornerRadius: 21)
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        if isEditing {
                            isEditing = false
                            selectedKeys.removeAll()
                        } else {
                            isEditing = true
                        }
                    } label: {
                        Text(isEditing ? "Cancel" : "Edit")
                            .font(.body)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 14)
                            .frame(height: 42)
                            .liquidGlass(cornerRadius: 21)
                    }
                    .buttonStyle(.plain)
                }
            ),
            onRefresh: {
                await model.loadCollectionRecommendations(for: collectionID)
                await model.loadExternalRatings(for: items + recommendedItems, limit: 120)
            }
        ) {
            VStack(spacing: 14) {
                SortRow(direction: $sortDirection) {
                    SortPicker(sort: $sort, includeMyRating: mode != .recommended, ratingSource: model.settings.preferredRatingSource)
                        .onChange(of: mode) { _, newMode in
                            if newMode == .recommended && sort == .myRating {
                                sort = .tmdbRating
                            }
                        }
                }

                CollectionDetailModePicker(mode: $mode)

                if mode == .myList {
                    if isEditing {
                        CollectionEditGrid(items: items, selectedKeys: $selectedKeys)
                    } else {
                        MediaGridOrList(items: items, hideWatchedForUpcoming: false, model: model, swipeContext: .collection(collectionID))
                    }
                } else if recommendedItems.isEmpty {
                    StatusBubble(
                        title: "No collection recommendations",
                        text: "Recommendations for this collection will appear here when related unwatched movies or series are found."
                    )
                } else {
                    MediaGridOrList(items: recommendedItems, hideWatchedForUpcoming: false, model: model)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isEditing {
                Button(action: removeSelected) {
                    Text(selectedKeys.isEmpty ? "Remove selected" : "Remove \(selectedKeys.count) selected")
                        .font(.body.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 14)
                        .background(selectedKeys.isEmpty ? Color.gray.opacity(0.7) : Color.red, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(selectedKeys.isEmpty)
                .padding(.bottom, 12)
                .animation(.easeInOut(duration: 0.2), value: selectedKeys.isEmpty)
            }
        }
        .task(id: collectionID) {
            await model.loadCollectionRecommendations(for: collectionID)
        }
        .onChange(of: mode) { _, newValue in
            if newValue == .recommended {
                Task { await model.loadCollectionRecommendations(for: collectionID) }
            }
        }
        .onChange(of: model.library.watched) { _, _ in
            if mode == .recommended {
                Task { await model.loadCollectionRecommendations(for: collectionID) }
            }
        }
        .alert("Rename Collection", isPresented: $showRenameAlert) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                model.renameCollection(id: collectionID, name: renameText)
                renameText = ""
            }
            Button("Cancel", role: .cancel) { renameText = "" }
        }
    }
}

private struct CollectionEditGrid: View {
    let items: [MediaItem]
    @Binding var selectedKeys: Set<MediaKey>

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(items) { item in
                let isSelected = selectedKeys.contains(item.key)
                Button {
                    if isSelected { selectedKeys.remove(item.key) }
                    else { selectedKeys.insert(item.key) }
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Color.clear
                            .aspectRatio(2/3, contentMode: .fit)
                            .overlay {
                                GeometryReader { geo in
                                    PosterView(
                                        item: item,
                                        width: geo.size.width,
                                        height: geo.size.height,
                                        isFavourite: false
                                    )
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay {
                                if isSelected {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(.blue, lineWidth: 3)
                                }
                            }

                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(isSelected ? .blue : .white)
                            .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 1)
                            .padding(5)
                    }
                    .animation(.easeInOut(duration: 0.15), value: isSelected)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct CollectionDetailModePicker: View {
    @Binding var mode: CollectionDetailMode

    var body: some View {
        Picker("Collection view", selection: $mode) {
            Text(CollectionDetailMode.myList.title).tag(CollectionDetailMode.myList)
            Text(CollectionDetailMode.recommended.title).tag(CollectionDetailMode.recommended)
        }
        .pickerStyle(.segmented)
        .liquidGlass(cornerRadius: 18)
    }
}
