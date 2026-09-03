import SwiftUI
import Foundation
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Social Models

struct FriendProfile: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let imageData: Data?
    var recentActivity: Date?
    var featuredItems: [MediaItem] = []
    var excitedForItems: [MediaItem] = []
    var sharesWatchlist: Bool = false
    var sharesWatched: Bool = false
    var watchlistItems: [MediaItem] = []
    var watchedItems: [MediaItem] = []
    var ratings: [MediaKey: Double] = [:]
    var favouriteKeys: Set<String> = []
    var watchedDates: [String: Date] = [:]

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: FriendProfile, rhs: FriendProfile) -> Bool { lhs.id == rhs.id }
}

enum FriendsRoute: Hashable {
    case friendDetail(FriendProfile)
    case friendWatchlist(FriendProfile)
    case friendWatched(FriendProfile)
}

private enum FriendsTab { case me, friends }

// MARK: - FriendsView

struct FriendsView: View {
    @ObservedObject var model: VestigoModel
    @State private var selectedTab: FriendsTab = .me
    @State private var friendsPath: [FriendsRoute] = []
    @State private var dummyFilter: MediaFilter = .both
    @State private var loadTask: Task<Void, Never>? = nil
    @State private var showAddMenu = false
    @State private var showQRCode = false
    @State private var showSendLink = false
    @State private var isPreparingInvite = false
    @AppStorage("Vestigo.devMode") private var devMode: Bool = false

    private var myInviteURL: String { model.myInviteURL }

    var body: some View {
        ZStack {
            NavigationStack(path: $friendsPath) {
                BaseScreen(title: "Friends", filter: $dummyFilter, settings: model.settings, headerAccessory: AnyView(
                    Button { showAddMenu = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.primary)
                            .frame(width: 42, height: 42)
                            .liquidGlass(cornerRadius: 21)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add friends")
                ), onRefresh: { startFriendsLoad() }) {
                    VStack(spacing: 22) {
                        Picker("", selection: $selectedTab) {
                            Text("Me").tag(FriendsTab.me)
                            Text("Friends").tag(FriendsTab.friends)
                        }
                        .pickerStyle(.segmented)
                        .liquidGlass(cornerRadius: 18)

                        if selectedTab == .me {
                            MeSectionView(model: model)
                        } else {
                            FriendsListView(
                                friends: model.friends,
                                model: model,
                                isLoading: model.friendsLoading,
                                diagnostic: model.friendsDiagnostic,
                                onSelect: { friend in friendsPath.append(.friendDetail(friend)) }
                            )
                        }

                        if devMode && !model.linkLog.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Link Log")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button("Clear") { model.linkLog.removeAll() }
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                ForEach(model.linkLog, id: \.self) { entry in
                                    Text(entry)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(12)
                            .liquidGlass(cornerRadius: 20)
                        }
                    }
                }
                .navigationDestination(for: FriendsRoute.self) { route in
                    switch route {
                    case .friendDetail(let friend):
                        FriendDetailPage(friend: friend, model: model, onWatchlist: {
                            friendsPath.append(.friendWatchlist(friend))
                        }, onWatched: {
                            friendsPath.append(.friendWatched(friend))
                        })
                    case .friendWatchlist(let friend):
                        FriendWatchlistPage(friend: friend, model: model)
                    case .friendWatched(let friend):
                        FriendWatchedPage(friend: friend, model: model)
                    }
                }
                .onChange(of: model.friendsResetToken) { _, _ in
                    friendsPath.removeAll()
                    selectedTab = .me
                }
                .onChange(of: model.pendingFriendAdd) { _, newValue in
                    if newValue != nil { selectedTab = .friends }
                }
                .onAppear {
                    // Handle the case where pendingFriendAdd was set before this view appeared
                    if model.pendingFriendAdd != nil { selectedTab = .friends }
                }
            }

            if showQRCode {
                QRCodeOverlay(inviteURL: myInviteURL, onDismiss: { showQRCode = false })
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
            }

            if isPreparingInvite {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .transition(.opacity)
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(1.6)
                    .transition(.opacity)
            }
        }
        .task { await startFriendsLoadAsync() }
        .alert("Add a Friend", isPresented: $showAddMenu) {
            Button("QR Code") {
                Task {
                    try? await Task.sleep(nanoseconds: 300_000_000) // let alert finish dismissing
                    withAnimation(.easeInOut(duration: 0.22)) { isPreparingInvite = true }
                    await model.publishPublicProfile()
                    withAnimation(.easeInOut(duration: 0.22)) { isPreparingInvite = false }
                    showQRCode = true
                }
            }
            Button("Send Link") {
                Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    withAnimation(.easeInOut(duration: 0.22)) { isPreparingInvite = true }
                    await model.publishPublicProfile()
                    withAnimation(.easeInOut(duration: 0.22)) { isPreparingInvite = false }
                    showSendLink = true
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Share your Vestigo profile so friends can add you.")
        }
        .sheet(isPresented: $showSendLink) {
            #if canImport(UIKit)
            let shareItems: [Any] = URL(string: myInviteURL).map { [$0 as Any] } ?? [myInviteURL as Any]
            ActivityView(activityItems: shareItems)
            #else
            EmptyView()
            #endif
        }
    }

    private func startFriendsLoad() {
        loadTask?.cancel()
        loadTask = Task { await startFriendsLoadAsync() }
    }

    private func startFriendsLoadAsync() async {
        async let publish: Void = model.publishPublicProfile()
        async let requests: Void = model.checkIncomingFriendRequests()
        _ = await (publish, requests)
        await model.loadFriends()
    }
}

// MARK: - QR Code Overlay

private struct QRCodeOverlay: View {
    let inviteURL: String
    let onDismiss: () -> Void

    @State private var savedBrightness: CGFloat = 0.5
    @State private var qrImage: UIImage? = nil

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 20) {
                Text("Scan to add me on Vestigo")
                    .font(.title3.bold())
                    .foregroundStyle(.primary)

                if let image = qrImage {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 260, height: 260)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.secondary.opacity(0.2))
                        .frame(width: 260, height: 260)
                        .overlay(ProgressView())
                }

                Text("Tap anywhere to close")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(32)
            .liquidGlass(cornerRadius: 32)
            .padding(24)
        }
        .onAppear {
            #if canImport(UIKit)
            savedBrightness = UIScreen.main.brightness
            UIScreen.main.brightness = 1.0
            #endif
            generateQR()
        }
        .onDisappear {
            #if canImport(UIKit)
            UIScreen.main.brightness = savedBrightness
            #endif
        }
    }

    private func generateQR() {
        #if canImport(UIKit)
        DispatchQueue.global(qos: .userInitiated).async {
            guard let data = inviteURL.data(using: .utf8) else { return }
            let filter = CIFilter(name: "CIQRCodeGenerator")
            filter?.setValue(data, forKey: "inputMessage")
            filter?.setValue("M", forKey: "inputCorrectionLevel")
            guard let output = filter?.outputImage else { return }
            let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
            let context = CIContext()
            guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return }
            let image = UIImage(cgImage: cgImage)
            DispatchQueue.main.async { qrImage = image }
        }
        #endif
    }
}

// MARK: - Me Section

private struct MeSectionView: View {
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

// MARK: - Camera picker

#if canImport(UIKit)
private struct CameraImagePicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (UIImage) -> Void
        init(onImage: @escaping (UIImage) -> Void) { self.onImage = onImage }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            picker.dismiss(animated: true)
            let image = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage
            if let image { onImage(image) }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
#endif

// MARK: - Shared poster row used for Featured + Excited For

private struct SocialPosterRow: View {
    let title: String
    let items: [MediaItem]
    var editIcon: String = ""
    var onEdit: (() -> Void)? = nil
    var emptyMessage: String = ""
    var showRating: Bool = true
    var friendContext: FriendProfile? = nil
    @ObservedObject var model: VestigoModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline.bold())
                Spacer()
                if !editIcon.isEmpty, let onEdit {
                    Button { onEdit() } label: {
                        Image(systemName: editIcon)
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)
                    }
                }
            }
            .padding(.horizontal, 2)

            if items.isEmpty {
                if !emptyMessage.isEmpty {
                    Text(emptyMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 2)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(items) { item in
                            let isFriendFav = friendContext?.favouriteKeys.contains(item.key.stableID) ?? false
                            let isMyFav = model.library.isFavourite(item)
                            Button {
                                if let friendContext { model.friendDetailContext = friendContext }
                                model.selectedItem = item
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    PosterView(
                                        item: item,
                                        width: 110,
                                        height: 160,
                                        isFavourite: isFriendFav || isMyFav,
                                        favouriteColor: (isFriendFav && !isMyFav) ? .blue : .yellow
                                    )
                                    Text(item.title)
                                        .font(.caption.bold())
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                        .frame(width: 110, alignment: .leading)
                                    if showRating {
                                        if let rating = model.library.ratings[item.key], rating > 0 {
                                            HStack(spacing: 3) {
                                                Image(systemName: "star.fill")
                                                    .font(.system(size: 9))
                                                    .foregroundStyle(.white)
                                                Text(rating.formatted(.number.precision(.fractionLength(0...1))))
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        } else {
                                            Text(model.library.isWatched(item.key) ? "Unrated" : "Watchlist")
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                        }
                                    } else {
                                        if let date = item.releaseDateValue {
                                            Text(date.formatted(date: .abbreviated, time: .omitted))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .scrollClipDisabled()
            }
        }
    }
}

private struct SharingRow: View {
    let label: String
    let icon: String
    @Binding var isOn: Bool
    let onChange: () -> Void

    var body: some View {
        HStack {
            Label(label, systemImage: icon)
                .font(.subheadline)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .onChange(of: isOn) { _, _ in onChange() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}

private enum PickerSource { case watched, watchlist, both }
private enum PickerKind { case movies, series, both }

// MARK: - Featured Picker Sheet

private struct FeaturedPickerSheet: View {
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
                                if let rating = model.library.ratings[item.key] {
                                    Text("\(rating.formatted(.number.precision(.fractionLength(0...1)))) stars")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Not rated")
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

private struct ExcitedForPickerSheet: View {
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

// MARK: - Friends List

private struct FriendsListView: View {
    let friends: [FriendProfile]
    @ObservedObject var model: VestigoModel
    var isLoading: Bool = false
    var diagnostic: String = ""
    let onSelect: (FriendProfile) -> Void
    @AppStorage("Vestigo.devMode") private var devMode: Bool = false
    @State private var friendToRemove: FriendProfile? = nil

    var body: some View {
        VStack(spacing: 16) {
            if isLoading && friends.isEmpty {
                StatusBubble(
                    title: "Loading friends…",
                    text: "Fetching profiles for your added friends."
                )
            } else if friends.isEmpty {
                StatusBubble(
                    title: "No friends added yet",
                    text: "Tap the + button to share your QR code or send a link so friends can add you."
                )
                if devMode && !diagnostic.isEmpty {
                    Text(diagnostic)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 4)
                }
            } else {
                FriendFavouritesSection(friends: friends, model: model)
                FriendExcitedForSection(friends: friends, model: model)

                ForEach(friends) { friend in
                    Button { onSelect(friend) } label: {
                        HStack(spacing: 14) {
                            AvatarView(name: friend.name, imageData: friend.imageData, size: 54)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(friend.name)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.primary)
                                if let activity = friend.recentActivity {
                                    Text("Active \(activity.formatted(.relative(presentation: .named)))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if let lastItem = friend.watchedItems.first {
                                    HStack(spacing: 4) {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundStyle(.tertiary)
                                        Text(lastItem.title)
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .liquidGlass(cornerRadius: 30)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            friendToRemove = friend
                        } label: {
                            Label("Remove Friend", systemImage: "person.badge.minus")
                        }
                    }
                }
            }
        }
        .alert("Remove \(friendToRemove?.name ?? "")?", isPresented: Binding(
            get: { friendToRemove != nil },
            set: { if !$0 { friendToRemove = nil } }
        )) {
            Button("Remove", role: .destructive) {
                if let f = friendToRemove { model.removeFriend(recordID: f.id) }
                friendToRemove = nil
            }
            Button("Cancel", role: .cancel) { friendToRemove = nil }
        } message: {
            Text("They will be removed from your friends list.")
        }
    }
}

// MARK: - Friend Favourites Carousel

private struct FriendFavouritesSection: View {
    let friends: [FriendProfile]
    @ObservedObject var model: VestigoModel

    private struct ScoredItem: Identifiable {
        var id: String { item.key.stableID }
        let item: MediaItem
        let overlap: Int
        let friendNames: [String]
        let firstFriend: FriendProfile?
    }

    private var scoredItems: [ScoredItem] {
        var counts: [String: Int] = [:]
        var itemMap: [String: MediaItem] = [:]
        var nameMap: [String: [String]] = [:]
        var firstFriendMap: [String: FriendProfile] = [:]
        for friend in friends {
            let first = friend.name.components(separatedBy: " ").first ?? friend.name
            let favKeys = friend.favouriteKeys
            var friendFavItems: [MediaItem]
            if favKeys.isEmpty {
                friendFavItems = friend.featuredItems
            } else {
                friendFavItems = friend.featuredItems.filter { favKeys.contains($0.key.stableID) }
                if friend.sharesWatched {
                    let existingIDs = Set(friendFavItems.map { $0.key.stableID })
                    let watchedFavs = friend.watchedItems.filter {
                        favKeys.contains($0.key.stableID) && !existingIDs.contains($0.key.stableID)
                    }
                    friendFavItems += watchedFavs
                }
            }
            for item in friendFavItems {
                let sid = item.key.stableID
                counts[sid, default: 0] += 1
                itemMap[sid] = item
                if firstFriendMap[sid] == nil { firstFriendMap[sid] = friend }
                if let rating = friend.ratings[item.key], rating > 0 {
                    let r = rating.formatted(.number.precision(.fractionLength(0...1)))
                    nameMap[sid, default: []].append("\(first) · \(r)")
                } else {
                    nameMap[sid, default: []].append(first)
                }
            }
        }
        return Array(itemMap.values)
            .sorted { a, b in
                let ao = counts[a.key.stableID] ?? 1, bo = counts[b.key.stableID] ?? 1
                if ao != bo { return ao > bo }
                let au = !model.library.isWatched(a.key), bu = !model.library.isWatched(b.key)
                if au != bu { return au }
                return a.voteAverage > b.voteAverage
            }
            .map { item in
                let sid = item.key.stableID
                return ScoredItem(item: item, overlap: counts[sid] ?? 1, friendNames: nameMap[sid] ?? [], firstFriend: firstFriendMap[sid])
            }
    }

    var body: some View {
        if !scoredItems.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Friend Favourites")
                    .font(.headline.bold())
                    .padding(.horizontal, 2)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(Array(scoredItems.prefix(15))) { scored in
                            Button {
                                model.friendDetailContext = scored.firstFriend
                                model.selectedItem = scored.item
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    PosterView(
                                        item: scored.item,
                                        width: 100,
                                        height: 150,
                                        isFavourite: true,
                                        favouriteColor: model.library.isFavourite(scored.item) ? .yellow : .blue
                                    )
                                    Text(scored.item.title)
                                        .font(.caption.bold())
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                        .frame(width: 100, alignment: .leading)
                                    Text(scored.friendNames.prefix(2).joined(separator: ", "))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .frame(width: 100, alignment: .leading)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .scrollClipDisabled()
            }
        }
    }
}

// MARK: - Friend Excited For Carousel

private struct FriendExcitedForSection: View {
    let friends: [FriendProfile]
    @ObservedObject var model: VestigoModel

    private struct ScoredItem: Identifiable {
        var id: String { item.key.stableID }
        let item: MediaItem
        let overlap: Int
        let friendLabels: [String]
    }

    private var scoredItems: [ScoredItem] {
        var counts: [String: Int] = [:]
        var itemMap: [String: MediaItem] = [:]
        var labelMap: [String: [String]] = [:]
        for friend in friends {
            let first = friend.name.components(separatedBy: " ").first ?? friend.name
            for item in friend.excitedForItems {
                let sid = item.key.stableID
                counts[sid, default: 0] += 1
                itemMap[sid] = item
                if let date = item.releaseDateValue {
                    let dateStr = date.formatted(.dateTime.day().month(.defaultDigits).year(.twoDigits))
                    labelMap[sid, default: []].append("\(first) · \(dateStr)")
                } else {
                    labelMap[sid, default: []].append(first)
                }
            }
        }
        return Array(itemMap.values)
            .sorted { a, b in
                let ao = counts[a.key.stableID] ?? 1, bo = counts[b.key.stableID] ?? 1
                if ao != bo { return ao > bo }
                let ad = a.releaseDateValue ?? .distantFuture
                let bd = b.releaseDateValue ?? .distantFuture
                return ad < bd
            }
            .map { item in
                let sid = item.key.stableID
                return ScoredItem(item: item, overlap: counts[sid] ?? 1, friendLabels: labelMap[sid] ?? [])
            }
    }

    var body: some View {
        if !scoredItems.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Friends are excited for")
                    .font(.headline.bold())
                    .padding(.horizontal, 2)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(Array(scoredItems.prefix(15))) { scored in
                            Button { model.selectedItem = scored.item } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    PosterView(
                                        item: scored.item,
                                        width: 100,
                                        height: 150,
                                        isFavourite: model.library.isFavourite(scored.item)
                                    )
                                    Text(scored.item.title)
                                        .font(.caption.bold())
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                        .frame(width: 100, alignment: .leading)
                                    Text(scored.friendLabels.prefix(2).joined(separator: ", "))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .frame(width: 100, alignment: .leading)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .scrollClipDisabled()
            }
        }
    }
}

// MARK: - Friend Activity Row

private struct FriendActivityRow: View {
    let friend: FriendProfile
    let item: MediaItem
    @ObservedObject var model: VestigoModel

    var body: some View {
        Button { model.selectedItem = item } label: {
            HStack(spacing: 12) {
                AvatarView(name: friend.name, imageData: friend.imageData, size: 54)
                VStack(alignment: .leading, spacing: 2) {
                    let first = friend.name.components(separatedBy: " ").first ?? friend.name
                    Text("\(first) watched")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(item.title)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    let watchDate = friend.watchedDates[item.key.stableID] ?? friend.recentActivity
                    if let date = watchDate {
                        Text(date.formatted(.relative(presentation: .named)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                PosterView(item: item, width: 42, height: 62, isFavourite: false)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .liquidGlass(cornerRadius: 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Friend Detail Page

struct FriendDetailPage: View {
    let friend: FriendProfile
    @ObservedObject var model: VestigoModel
    let onWatchlist: () -> Void
    let onWatched: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var dummyFilter: MediaFilter = .both
    @State private var showRemoveConfirm = false
    @State private var liveData: FriendProfile? = nil

    private var current: FriendProfile { liveData ?? friend }

    private func refresh() {
        Task {
            if let updated = await model.refreshFriend(recordID: friend.id) { liveData = updated }
        }
    }

    var body: some View {
        BaseScreen(title: "", filter: $dummyFilter, settings: model.settings, onRefresh: { refresh() }) {
            VStack(spacing: 22) {
                VStack(spacing: 12) {
                    AvatarView(name: current.name, imageData: current.imageData, size: 110)
                    VStack(spacing: 4) {
                        Text(current.name)
                            .font(.title.bold())
                            .minimumScaleFactor(0.6)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                        if let activity = current.recentActivity {
                            Text("Active \(activity.formatted(.relative(presentation: .named)))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 4)

                if !current.featuredItems.isEmpty {
                    SocialPosterRow(title: "Featured", items: current.featuredItems, showRating: false, friendContext: current, model: model)
                }

                if !current.excitedForItems.isEmpty {
                    SocialPosterRow(title: "Excited For", items: current.excitedForItems, showRating: false, friendContext: current, model: model)
                }

                VStack(spacing: 0) {
                    if current.sharesWatchlist {
                        Button { onWatchlist() } label: {
                            HStack {
                                Label("View Watchlist (\(current.watchlistItems.count))", systemImage: "bookmark")
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 13)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    if current.sharesWatchlist && current.sharesWatched {
                        Divider().padding(.leading, 16)
                    }

                    if current.sharesWatched {
                        Button { onWatched() } label: {
                            HStack {
                                Label("View Watched (\(current.watchedItems.count))", systemImage: "checkmark.circle")
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 13)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    if !current.sharesWatchlist && !current.sharesWatched {
                        HStack(spacing: 8) {
                            Image(systemName: "eye.slash")
                                .foregroundStyle(.secondary)
                            Text("\(current.name) isn't sharing their library.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                    }
                }
                .liquidGlass(cornerRadius: 20)

                Button(role: .destructive) {
                    showRemoveConfirm = true
                } label: {
                    Label("Remove Friend", systemImage: "person.badge.minus")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .liquidGlass(cornerRadius: 20)
                }
                .buttonStyle(.plain)
                .alert("Remove \(current.name)?", isPresented: $showRemoveConfirm) {
                    Button("Remove", role: .destructive) {
                        model.removeFriend(recordID: friend.id)
                        dismiss()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("You'll no longer see their profile. They won't be notified.")
                }
            }
        }
    }
}

// MARK: - Friend Watchlist / Watched Pages

struct FriendWatchlistPage: View {
    let friend: FriendProfile
    @ObservedObject var model: VestigoModel
    @State private var filter: MediaFilter = .both
    @State private var liveData: FriendProfile? = nil

    private var current: FriendProfile { liveData ?? friend }

    private func refresh() {
        Task {
            if let updated = await model.refreshFriend(recordID: friend.id) { liveData = updated }
        }
    }

    private var filteredItems: [MediaItem] {
        switch filter {
        case .movie: return current.watchlistItems.filter { $0.kind == .movie }
        case .tv: return current.watchlistItems.filter { $0.kind == .tv }
        case .both: return current.watchlistItems
        }
    }

    var body: some View {
        BaseScreen(title: "\(current.name)'s Watchlist", filter: $filter, settings: model.settings, onRefresh: { refresh() }) {
            VStack(spacing: 16) {
                HStack(spacing: 8) {
                    FilterPills(filter: $filter, options: [.movie, .tv, .both]) {}
                    Text("\(filteredItems.count)")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .padding(.horizontal, 7)
                        .frame(maxHeight: .infinity)
                        .liquidGlass(cornerRadius: 100)
                }
                if filteredItems.isEmpty {
                    StatusBubble(title: "Nothing here", text: "\(current.name)'s watchlist is empty.")
                } else {
                    MediaGridOrList(items: filteredItems, hideWatchedForUpcoming: false, model: model, openItem: { item in
                        model.friendDetailContext = current
                        model.selectedItem = item
                    })
                }
            }
        }
    }
}

struct FriendWatchedPage: View {
    let friend: FriendProfile
    @ObservedObject var model: VestigoModel
    @State private var filter: MediaFilter = .both
    @State private var hideAlreadySeen = false
    @State private var liveData: FriendProfile? = nil

    private var current: FriendProfile { liveData ?? friend }

    private func refresh() {
        Task {
            if let updated = await model.refreshFriend(recordID: friend.id) { liveData = updated }
        }
    }

    private var filteredItems: [MediaItem] {
        var items = current.watchedItems
        switch filter {
        case .movie: items = items.filter { $0.kind == .movie }
        case .tv: items = items.filter { $0.kind == .tv }
        case .both: break
        }
        if hideAlreadySeen { items = items.filter { !model.library.isWatched($0.key) } }
        return items
    }

    var body: some View {
        BaseScreen(title: "\(current.name)'s Watched", filter: $filter, settings: model.settings, onRefresh: { refresh() }) {
            VStack(spacing: 16) {
                HStack(spacing: 8) {
                    FilterPills(filter: $filter, options: [.movie, .tv, .both]) {}
                    Text("\(filteredItems.count)")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .padding(.horizontal, 7)
                        .frame(maxHeight: .infinity)
                        .liquidGlass(cornerRadius: 100)
                }
                Toggle("Hide items I've seen", isOn: $hideAlreadySeen)
                    .font(.subheadline)
                    .padding(.horizontal, 4)
                if filteredItems.isEmpty {
                    StatusBubble(title: "Nothing here", text: "\(current.name) hasn't watched anything yet.")
                } else {
                    MediaGridOrList(items: filteredItems, hideWatchedForUpcoming: false, model: model, openItem: { item in
                        model.friendDetailContext = current
                        model.selectedItem = item
                    })
                }
            }
        }
    }
}

// MARK: - Shared UI Helpers

struct AvatarView: View {
    let name: String
    let imageData: Data?
    let size: CGFloat

    private var initials: String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1)) + String(parts[1].prefix(1))
        }
        return String(name.prefix(2)).uppercased()
    }

    var body: some View {
        Group {
            #if canImport(UIKit)
            if let data = imageData, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                initialsView
            }
            #else
            initialsView
            #endif
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initialsView: some View {
        ZStack {
            Circle().fill(.white.opacity(0.18))
            Text(initials)
                .font(.system(size: size * 0.35, weight: .semibold))
                .foregroundStyle(.primary)
        }
    }
}

#if canImport(UIKit)
struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
