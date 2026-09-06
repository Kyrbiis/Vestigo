import SwiftUI
import Foundation
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Me Section

struct MeSectionView: View {
    @ObservedObject var model: VestigoModel
    @State private var showFeaturedPicker = false
    @State private var showExcitedForPicker = false
    @AppStorage("Vestigo.devMode") private var devMode: Bool = false
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var showCameraPicker = false
    @State private var showLibraryPicker = false
    @State private var showFilePicker = false
    @State private var nameEdit: String = ""

    private var featuredItems: [MediaItem] {
        if model.settings.socialFeaturedItemKeys.isEmpty {
            return Array(
                model.library.items.values
                    .filter { model.library.isFavourite($0) }
                    .sorted { $0.voteAverage > $1.voteAverage }
                    .prefix(6)
            )
        }
        return model.settings.socialFeaturedItemKeys.compactMap { stableID in
            model.library.items.values.first { $0.key.stableID == stableID }
        }
    }

    private var excitedForItems: [MediaItem] {
        let today = Calendar.current.startOfDay(for: Date())
        return model.settings.socialExcitedForKeys.compactMap { stableID -> MediaItem? in
            model.library.items.values.first { $0.key.stableID == stableID }
                ?? model.upcoming.first { $0.key.stableID == stableID }
                ?? model.settings.socialExcitedForItemCache.first { $0.key.stableID == stableID }
        }.filter { item in
            guard let releaseDate = item.releaseDateValue else { return true }
            return releaseDate > today
        }
    }

    private struct ActivityEntry: Identifiable {
        var id: String { "\(friend.id)-\(item.key.stableID)" }
        let friend: FriendProfile
        let item: MediaItem
    }

    private var recentFriendsActivity: [ActivityEntry] {
        model.friends
            .filter { $0.sharesWatched && !$0.watchedItems.isEmpty }
            .compactMap { friend in
                guard let item = friend.watchedItems.first else { return nil }
                return ActivityEntry(friend: friend, item: item)
            }
            .sorted { a, b in
                let aDate = a.friend.watchedDates[a.item.key.stableID] ?? a.friend.recentActivity ?? .distantPast
                let bDate = b.friend.watchedDates[b.item.key.stableID] ?? b.friend.recentActivity ?? .distantPast
                return aDate > bDate
            }
    }

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Menu {
                    Button { showCameraPicker = true } label: {
                        Label("Take Photo", systemImage: "camera")
                    }
                    Button { showLibraryPicker = true } label: {
                        Label("Choose Photo", systemImage: "photo.on.rectangle")
                    }
                    Button { showFilePicker = true } label: {
                        Label("Choose File", systemImage: "folder")
                    }
                    if model.userAvatarData != nil {
                        Button(role: .destructive) { model.clearUserAvatar() } label: {
                            Label("Remove Photo", systemImage: "trash")
                        }
                    }
                } label: {
                    AvatarView(name: model.settings.name.isEmpty ? "Me" : model.settings.name,
                               imageData: model.userAvatarData, size: 96)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 4) {
                    TextField("Set your name…", text: $nameEdit)
                        .font(.title3.bold())
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 4)
                        .onSubmit {
                            model.settings.name = nameEdit
                            model.saveSettings()
                            Task { await model.publishPublicProfile() }
                        }
                        .onChange(of: nameEdit) { _, newValue in
                            model.settings.name = newValue
                            model.saveSettings()
                        }

                    if nameEdit.isEmpty {
                        Text("You won't appear to others until you set a name.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .onAppear { nameEdit = model.settings.name }
            }

            SocialPosterRow(
                title: "Featured",
                items: featuredItems,
                editIcon: "pencil",
                onEdit: { showFeaturedPicker = true },
                emptyMessage: "Your top favourites appear here. Tap the pencil to customise.",
                showRating: true,
                model: model
            )

            SocialPosterRow(
                title: "Excited For",
                items: excitedForItems,
                editIcon: "pencil",
                onEdit: { showExcitedForPicker = true },
                emptyMessage: "Add upcoming releases you can't wait for.",
                showRating: false,
                model: model
            )

            VStack(spacing: 0) {
                SharingRow(
                    label: "Don't share anything",
                    icon: "eye.slash",
                    isOn: $model.settings.socialDontShare
                ) {
                    if model.settings.socialDontShare {
                        model.settings.socialShareWatchlist = false
                        model.settings.socialShareWatched = false
                    } else {
                        model.settings.socialShareWatchlist = true
                        model.settings.socialShareWatched = true
                    }
                    model.saveSettings()
                }

                if !model.settings.socialDontShare {
                    Divider().padding(.leading, 52)
                    SharingRow(label: "Share watchlist", icon: "bookmark", isOn: $model.settings.socialShareWatchlist) {
                        model.saveSettings()
                    }
                    Divider().padding(.leading, 52)
                    SharingRow(label: "Share watched items", icon: "checkmark.circle", isOn: $model.settings.socialShareWatched) {
                        model.saveSettings()
                    }
                }
            }
            .liquidGlass(cornerRadius: 20)

            VStack(alignment: .leading, spacing: 8) {
                Text("Friends Activity")
                    .font(.headline.bold())
                    .padding(.horizontal, 2)
                if recentFriendsActivity.isEmpty {
                    StatusBubble(
                        title: "Nothing yet",
                        text: "When friends share their watched history, you'll see their recent watches here."
                    )
                } else {
                    ForEach(Array(recentFriendsActivity.prefix(5))) { entry in
                        FriendActivityRow(friend: entry.friend, item: entry.item, model: model)
                    }
                }
            }

            if devMode && !model.publishDiagnostic.isEmpty {
                Text(model.publishDiagnostic)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 4)
            }
        }
        .sheet(isPresented: $showFeaturedPicker) {
            FeaturedPickerSheet(model: model)
        }
        .sheet(isPresented: $showExcitedForPicker) {
            ExcitedForPickerSheet(model: model)
        }
        .fullScreenCover(isPresented: $showCameraPicker) {
            #if canImport(UIKit)
            CameraImagePicker { image in
                model.saveUserAvatar(image: image)
            }
            .ignoresSafeArea()
            #endif
        }
        .photosPicker(isPresented: $showLibraryPicker, selection: $selectedPhotoItem, matching: .images)
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result {
                if url.startAccessingSecurityScopedResource() {
                    defer { url.stopAccessingSecurityScopedResource() }
                    #if canImport(UIKit)
                    if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                        model.saveUserAvatar(image: image)
                    }
                    #endif
                }
            }
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    #if canImport(UIKit)
                    if let image = UIImage(data: data) {
                        model.saveUserAvatar(image: image)
                    }
                    #endif
                }
                selectedPhotoItem = nil
            }
        }
    }
}
