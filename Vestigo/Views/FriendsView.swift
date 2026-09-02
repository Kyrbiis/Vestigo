import SwiftUI
import Foundation
#if canImport(UIKit)
import UIKit
import CoreImage.CIFilterBuiltins
#endif

// MARK: - Social Models

struct FriendProfile: Identifiable, Hashable {
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

    private var myInviteURL: String? {
        guard let name = model.myInviteRecordName else { return nil }
        return "vestigo://friend?id=\(name)"
    }

    var body: some View {
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
        }
        .task { await startFriendsLoadAsync() }
        .confirmationDialog("Add a Friend", isPresented: $showAddMenu) {
            Button("QR Code") { showQRCode = true }
            Button("Send Link") { showSendLink = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Share your Vestigo profile so friends can add you.")
        }
        .fullScreenCover(isPresented: $showQRCode) {
            if let url = myInviteURL {
                QRCodeOverlay(inviteURL: url, onDismiss: { showQRCode = false })
            }
        }
        .sheet(isPresented: $showSendLink) {
            #if canImport(UIKit)
            if let url = myInviteURL {
                let message = "Add me on Vestigo!\n\n\(url)\n\nDon't have Vestigo yet? https://testflight.apple.com/join/zbvP2WEx"
                ActivityView(activityItems: [message])
            } else {
                EmptyView()
            }
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
        await model.loadMyInviteRecordName()
        await model.publishPublicProfile()
        await model.loadFriends()
    }
}

// MARK: - QR Code Overlay

private struct QRCodeOverlay: View {
    let inviteURL: String
    let onDismiss: () -> Void

    @State private var savedBrightness: CGFloat = 0.5

    var body: some View {
        ZStack {
            Color.black.opacity(0.92)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 24) {
                Text("Scan to add me on Vestigo")
                    .font(.title3.bold())
                    .foregroundStyle(.white)

                #if canImport(UIKit)
                if let image = generateQRCode(from: inviteURL) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 270, height: 270)
                        .background(Color.white)
                        .cornerRadius(16)
                        .padding(4)
                }
                #endif

                Text("Tap anywhere to close")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(32)
        }
        .onAppear {
            #if canImport(UIKit)
            savedBrightness = UIScreen.main.brightness
            UIScreen.main.brightness = 1.0
            #endif
        }
        .onDisappear {
            #if canImport(UIKit)
            UIScreen.main.brightness = savedBrightness
            #endif
        }
    }

    #if canImport(UIKit)
    private func generateQRCode(from string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
    #endif
}

// MARK: - Me Section

private struct MeSectionView: View {
    @ObservedObject var model: VestigoModel
    @State private var showFeaturedPicker = false
    @State private var showExcitedForPicker = false
    @AppStorage("Vestigo.devMode") private var devMode: Bool = false

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
            .sorted { ($0.friend.recentActivity ?? .distantPast) > ($1.friend.recentActivity ?? .distantPast) }
    }

    var body: some View {
        VStack(spacing: 20) {
            if !model.settings.name.isEmpty {
                Text(model.settings.name)
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
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
                editIcon: "plus",
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
    }
}

// MARK: - Shared poster row used for Featured + Excited For

private struct SocialPosterRow: View {
    let title: String
    let items: [MediaItem]
    var editIcon: String = ""
    var onEdit: (() -> Void)? = nil
    var emptyMessage: String = ""
    var showRating: Bool = true
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
                            .foregroundStyle(.secondary)
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
                            Button { model.selectedItem = item } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    PosterView(
                                        item: item,
                                        width: 110,
                                        height: 160,
                                        isFavourite: model.library.isFavourite(item)
                                    )
                                    Text(item.title)
                                        .font(.caption.bold())
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                        .frame(width: 110, alignment: .leading)
                                    if showRating {
                                        if let rating = model.library.ratings[item.key] {
                                            HStack(spacing: 3) {
                                                Image(systemName: "star.fill")
                                                    .font(.system(size: 9))
                                                    .foregroundStyle(.yellow)
                                                Text(rating.formatted(.number.precision(.fractionLength(0...1))))
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        } else {
                                            Text("Not rated")
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

// MARK: - Featured Picker Sheet

private struct FeaturedPickerSheet: View {
    @ObservedObject var model: VestigoModel
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var searchText = ""

    private let maxItems = 6
    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    private var libraryItems: [MediaItem] {
        let all = (model.library.watchedItems + model.library.watchlistItems)
            .uniqued()
            .sorted {
                let aFav = model.library.isFavourite($0)
                let bFav = model.library.isFavourite($1)
                if aFav != bFav { return aFav }
                return $0.voteAverage > $1.voteAverage
            }
        if searchText.isEmpty { return all }
        let q = searchText.lowercased()
        return all.filter { $0.title.lowercased().contains(q) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text("Choose Featured")
                        .font(.title2.bold())
                    Spacer()
                    HStack(spacing: 16) {
                        Button("Cancel") { dismiss() }
                            .foregroundStyle(.secondary)
                        Button("Done") {
                            model.settings.socialFeaturedItemKeys = Array(selected)
                            model.saveSettings()
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
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
        .onAppear { selected = Set(model.settings.socialFeaturedItemKeys) }
    }
}

// MARK: - Excited For Picker Sheet

private struct ExcitedForPickerSheet: View {
    @ObservedObject var model: VestigoModel
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var searchText = ""
    @State private var remoteResults: [MediaItem] = []
    @State private var isSearchingRemote = false
    @State private var remoteTask: Task<Void, Never>? = nil

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    private var localItems: [MediaItem] {
        let today = Calendar.current.startOfDay(for: Date())
        let fromFeed = model.upcoming
        let fromLibrary = model.library.items.values.filter { item in
            guard let d = item.releaseDateValue else { return false }
            return d > today
        }
        let merged = (fromFeed + Array(fromLibrary)).uniqued()
            .sorted { ($0.releaseDateValue ?? .distantFuture) < ($1.releaseDateValue ?? .distantFuture) }
        guard !searchText.isEmpty else { return merged }
        let q = searchText.lowercased()
        return merged.filter { $0.title.lowercased().contains(q) }
    }

    private var displayItems: [MediaItem] {
        guard !searchText.isEmpty else { return localItems }
        let localIDs = Set(localItems.map { $0.key.stableID })
        let today = Calendar.current.startOfDay(for: Date())
        let remote = remoteResults.filter { item in
            guard !localIDs.contains(item.key.stableID) else { return false }
            if let d = item.releaseDateValue { return d > today }
            return true
        }
        return localItems + remote
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text("Excited For")
                        .font(.title2.bold())
                    Spacer()
                    HStack(spacing: 16) {
                        Button("Cancel") { dismiss() }
                            .foregroundStyle(.secondary)
                        Button("Done") {
                            model.settings.socialExcitedForKeys = Array(selected)
                            model.saveSettings()
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
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

                if selected.count > 0 {
                    Text("\(selected.count) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if displayItems.isEmpty && !isSearchingRemote {
                    StatusBubble(
                        title: searchText.isEmpty ? "No upcoming items" : "No results",
                        text: searchText.isEmpty ? "Upcoming releases will appear here when they're available." : "Try a different search term."
                    )
                } else {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(displayItems) { item in
                            let stableID = item.key.stableID
                            let isSelected = selected.contains(stableID)
                            Button {
                                if isSelected { selected.remove(stableID) } else { selected.insert(stableID) }
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
        .onAppear { selected = Set(model.settings.socialExcitedForKeys) }
        .onChange(of: searchText) { _, text in
            remoteTask?.cancel()
            guard !text.isEmpty else { remoteResults = []; return }
            remoteTask = Task {
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
                if localItems.count < 5 {
                    isSearchingRemote = true
                    remoteResults = await model.quickSearch(query: text)
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
                        .liquidGlass(cornerRadius: 22)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
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
    }

    private var scoredItems: [ScoredItem] {
        var counts: [String: Int] = [:]
        var itemMap: [String: MediaItem] = [:]
        var nameMap: [String: [String]] = [:]
        for friend in friends {
            let first = friend.name.components(separatedBy: " ").first ?? friend.name
            for item in friend.featuredItems {
                let sid = item.key.stableID
                counts[sid, default: 0] += 1
                itemMap[sid] = item
                nameMap[sid, default: []].append(first)
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
                return ScoredItem(item: item, overlap: counts[sid] ?? 1, friendNames: nameMap[sid] ?? [])
            }
    }

    var body: some View {
        if !scoredItems.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Friends' Favourites")
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
                                        .lineLimit(1)
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

// MARK: - Friend Activity Row

private struct FriendActivityRow: View {
    let friend: FriendProfile
    let item: MediaItem
    @ObservedObject var model: VestigoModel

    var body: some View {
        Button { model.selectedItem = item } label: {
            HStack(spacing: 12) {
                AvatarView(name: friend.name, imageData: friend.imageData, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    let first = friend.name.components(separatedBy: " ").first ?? friend.name
                    (Text(first).fontWeight(.semibold) + Text(" watched"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(item.title)
                        .font(.caption.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let activity = friend.recentActivity {
                        Text(activity.formatted(.relative(presentation: .named)))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                PosterView(item: item, width: 38, height: 56, isFavourite: false)
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
    @State private var dummyFilter: MediaFilter = .both
    @State private var showRemoveConfirm = false

    var body: some View {
        BaseScreen(title: friend.name, filter: $dummyFilter, settings: model.settings, onRefresh: nil) {
            VStack(spacing: 22) {
                AvatarView(name: friend.name, imageData: friend.imageData, size: 80)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)

                if !friend.featuredItems.isEmpty {
                    SocialPosterRow(title: "Featured", items: friend.featuredItems, showRating: false, model: model)
                }

                if !friend.excitedForItems.isEmpty {
                    SocialPosterRow(title: "Excited For", items: friend.excitedForItems, showRating: false, model: model)
                }

                VStack(spacing: 0) {
                    if friend.sharesWatchlist {
                        Button { onWatchlist() } label: {
                            HStack {
                                Label("View Watchlist", systemImage: "bookmark")
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 13)
                        }
                        .buttonStyle(.plain)
                    }

                    if friend.sharesWatchlist && friend.sharesWatched {
                        Divider().padding(.leading, 16)
                    }

                    if friend.sharesWatched {
                        Button { onWatched() } label: {
                            HStack {
                                Label("View Watched", systemImage: "checkmark.circle")
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 13)
                        }
                        .buttonStyle(.plain)
                    }

                    if !friend.sharesWatchlist && !friend.sharesWatched {
                        HStack(spacing: 8) {
                            Image(systemName: "eye.slash")
                                .foregroundStyle(.secondary)
                            Text("\(friend.name) isn't sharing their library.")
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
                .alert("Remove \(friend.name)?", isPresented: $showRemoveConfirm) {
                    Button("Remove", role: .destructive) { model.removeFriend(recordID: friend.id) }
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

    private var filteredItems: [MediaItem] {
        switch filter {
        case .movie: return friend.watchlistItems.filter { $0.kind == .movie }
        case .tv: return friend.watchlistItems.filter { $0.kind == .tv }
        case .both: return friend.watchlistItems
        }
    }

    var body: some View {
        BaseScreen(title: "\(friend.name)'s Watchlist", filter: $filter, settings: model.settings, onRefresh: nil) {
            VStack(spacing: 16) {
                FilterPills(filter: $filter, options: [.movie, .tv, .both]) {}
                if filteredItems.isEmpty {
                    StatusBubble(title: "Nothing here", text: "\(friend.name)'s watchlist is empty.")
                } else {
                    MediaGridOrList(items: filteredItems, hideWatchedForUpcoming: false, model: model, openItem: { item in
                        model.friendDetailContext = friend
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

    private var filteredItems: [MediaItem] {
        var items = friend.watchedItems
        switch filter {
        case .movie: items = items.filter { $0.kind == .movie }
        case .tv: items = items.filter { $0.kind == .tv }
        case .both: break
        }
        if hideAlreadySeen { items = items.filter { !model.library.isWatched($0.key) } }
        return items
    }

    var body: some View {
        BaseScreen(title: "\(friend.name)'s Watched", filter: $filter, settings: model.settings, onRefresh: nil) {
            VStack(spacing: 16) {
                FilterPills(filter: $filter, options: [.movie, .tv, .both]) {}
                Toggle("Hide items I've seen", isOn: $hideAlreadySeen)
                    .font(.subheadline)
                    .padding(.horizontal, 4)
                if filteredItems.isEmpty {
                    StatusBubble(title: "Nothing here", text: "\(friend.name) hasn't watched anything yet.")
                } else {
                    MediaGridOrList(items: filteredItems, hideWatchedForUpcoming: false, model: model, openItem: { item in
                        model.friendDetailContext = friend
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
            Circle().fill(.secondary.opacity(0.25))
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
