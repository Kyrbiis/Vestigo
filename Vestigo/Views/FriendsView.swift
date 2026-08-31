import SwiftUI
import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(Contacts)
import Contacts
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
    @State private var contactsGranted = false
    @State private var friends: [FriendProfile] = []
    @State private var dummyFilter: MediaFilter = .both

    var body: some View {
        NavigationStack(path: $friendsPath) {
            BaseScreen(title: "Friends", filter: $dummyFilter, settings: model.settings, onRefresh: nil) {
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
                        FriendsListView(friends: friends, contactsGranted: contactsGranted) { friend in
                            friendsPath.append(.friendDetail(friend))
                        }
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
        .task { await requestContactsAccess() }
    }

    private func requestContactsAccess() async {
        #if canImport(Contacts)
        let store = CNContactStore()
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized:
            contactsGranted = true
        case .notDetermined:
            contactsGranted = (try? await store.requestAccess(for: .contacts)) ?? false
        default:
            contactsGranted = false
        }
        #endif
    }
}

// MARK: - Me Section

private struct MeSectionView: View {
    @ObservedObject var model: VestigoModel
    @State private var showFeaturedPicker = false
    @State private var showExcitedForPicker = false

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

    var body: some View {
        VStack(spacing: 20) {
            // Profile — no box, just avatar + name
            VStack(spacing: 10) {
                AvatarView(
                    name: model.settings.name.isEmpty ? "Me" : model.settings.name,
                    imageData: nil,
                    size: 80
                )
                if !model.settings.name.isEmpty {
                    Text(model.settings.name)
                        .font(.title3.bold())
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)

            // Featured
            SocialPosterRow(
                title: "Featured",
                items: featuredItems,
                editIcon: "pencil",
                onEdit: { showFeaturedPicker = true },
                emptyMessage: "Your top favourites appear here. Tap the pencil to customise.",
                showRating: true,
                model: model
            )

            // Excited For
            SocialPosterRow(
                title: "Excited For",
                items: excitedForItems,
                editIcon: "plus",
                onEdit: { showExcitedForPicker = true },
                emptyMessage: "Add upcoming releases you can't wait for.",
                showRating: false,
                model: model
            )

            // Sharing settings
            VStack(spacing: 0) {
                SharingRow(
                    label: "Don't share anything",
                    icon: "eye.slash",
                    isOn: $model.settings.socialDontShare
                ) {
                    if model.settings.socialDontShare {
                        model.settings.socialShareWatchlist = false
                        model.settings.socialShareWatched = false
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

            // Friends activity placeholder
            VStack(alignment: .leading, spacing: 8) {
                Text("Friends Activity")
                    .font(.headline.bold())
                    .padding(.horizontal, 2)
                StatusBubble(
                    title: "Nothing yet",
                    text: "When friends join Vestigo and share their activity, you'll see it here."
                )
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
                                                Text(String(format: "%.0f", rating))
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
                                    HStack(spacing: 3) {
                                        Image(systemName: "star.fill")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.yellow)
                                        Text(String(format: "%.0f", rating))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
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

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    private var upcomingItems: [MediaItem] {
        let today = Calendar.current.startOfDay(for: Date())
        let fromFeed = model.upcoming
        let fromLibrary = model.library.items.values.filter { item in
            guard let d = item.releaseDateValue else { return false }
            return d > today
        }
        let merged = (fromFeed + Array(fromLibrary)).uniqued()
            .sorted { ($0.releaseDateValue ?? .distantFuture) < ($1.releaseDateValue ?? .distantFuture) }
        if searchText.isEmpty { return merged }
        let q = searchText.lowercased()
        return merged.filter { $0.title.lowercased().contains(q) }
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
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search upcoming", text: $searchText)
                }
                .padding(12)
                .liquidGlass(cornerRadius: 20)

                if upcomingItems.isEmpty {
                    StatusBubble(
                        title: "No upcoming items",
                        text: "Upcoming releases will appear here when they're available."
                    )
                } else {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(upcomingItems) { item in
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
    }
}

// MARK: - Friends List

private struct FriendsListView: View {
    let friends: [FriendProfile]
    let contactsGranted: Bool
    let onSelect: (FriendProfile) -> Void

    var body: some View {
        VStack(spacing: 16) {
            if !contactsGranted {
                StatusBubble(
                    title: "Contacts access needed",
                    text: "Vestigo uses your contacts to find friends who also have the app. Grant access in Settings to get started."
                )
                Button {
                    #if canImport(UIKit)
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                    #endif
                } label: {
                    Text("Open Settings")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .liquidGlass(cornerRadius: 20)
                }
                .buttonStyle(.plain)
            } else if friends.isEmpty {
                StatusBubble(
                    title: "No friends on Vestigo yet",
                    text: "Invite your friends and they'll appear here once they join."
                )
            } else {
                ForEach(friends) { friend in
                    Button { onSelect(friend) } label: {
                        HStack(spacing: 14) {
                            AvatarView(name: friend.name, imageData: friend.imageData, size: 46)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(friend.name)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.primary)
                                if let activity = friend.recentActivity {
                                    Text("Active \(activity.formatted(.relative(presentation: .named)))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .liquidGlass(cornerRadius: 18)
                    }
                    .buttonStyle(.plain)
                }
            }

            InviteButton()
        }
    }
}

// MARK: - Invite Button

private struct InviteButton: View {
    @State private var showShareSheet = false

    var body: some View {
        Button { showShareSheet = true } label: {
            Label("Invite Friends", systemImage: "person.badge.plus")
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .liquidGlass(cornerRadius: 20)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showShareSheet) {
            #if canImport(UIKit)
            let text = "Hey, check out Vestigo – it's a great way to track movies and TV shows and see what your friends are watching!"
            let url = URL(string: "https://testflight.apple.com/join/zbvP2WEx")!
            ActivityView(activityItems: [text, url])
            #else
            EmptyView()
            #endif
        }
    }
}

// MARK: - Friend Detail Page

struct FriendDetailPage: View {
    let friend: FriendProfile
    @ObservedObject var model: VestigoModel
    let onWatchlist: () -> Void
    let onWatched: () -> Void
    @State private var dummyFilter: MediaFilter = .both

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
                    MediaGridOrList(items: filteredItems, hideWatchedForUpcoming: false, model: model)
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
                    MediaGridOrList(items: filteredItems, hideWatchedForUpcoming: false, model: model)
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
