import SwiftUI
import Foundation

// MARK: - Shared Poster Row (Featured + Excited For)

struct SocialPosterRow: View {
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
                                        .lineLimit(2, reservesSpace: true)
                                        .frame(width: 110, alignment: .topLeading)
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

// MARK: - Sharing Row

struct SharingRow: View {
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
