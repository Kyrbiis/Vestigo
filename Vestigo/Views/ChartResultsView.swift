import SwiftUI

// MARK: - Charts

struct ChartTile: View {
    let title: String
    let icon: String
    let colors: [Color]

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white.opacity(0.88))
            Text(title)
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
    }
}

struct ChartResultsView: View {
    let kind: MediaKind
    @ObservedObject var model: VestigoModel
    @State private var hasLoaded = false
    @Environment(\.imageRefreshToken) private var imageRefreshToken

    private var items: [MediaItem] {
        kind == .movie ? model.topRatedMovies : model.topRatedShows
    }

    var body: some View {
        BaseScreen(
            title: kind == .movie ? "Top Rated Movies" : "Top Rated TV Shows",
            filter: .constant(.both),
            settings: model.settings,
            onRefresh: { await model.loadTopRated(kind: kind) }
        ) {
            if items.isEmpty {
                LoadingBubble(title: "Building chart", text: "Fetching ratings…")
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(Array(items.prefix(100).enumerated()), id: \.element.key) { index, item in
                        ChartItemRow(rank: index + 1, item: item, model: model, imageRefreshToken: imageRefreshToken)
                    }
                }
            }
        }
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await model.loadTopRated(kind: kind)
        }
    }
}

struct ChartItemRow: View {
    let rank: Int
    let item: MediaItem
    @ObservedObject var model: VestigoModel
    let imageRefreshToken: Int

    private var posterURL: URL? {
        item.posterPath.flatMap { URL(string: "https://image.tmdb.org/t/p/w185\($0)") }
    }

    var body: some View {
        Button {
            model.selectedItem = item
        } label: {
            HStack(spacing: 14) {
                Text("\(rank)")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .trailing)
                    .monospacedDigit()

                AsyncImage(url: posterURL?.refreshedImageURL(token: imageRefreshToken)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(.white.opacity(0.1))
                    }
                }
                .frame(width: 44, height: 66)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    let ratingText = model.ratingDisplayText(for: item)
                    if !ratingText.isEmpty {
                        Text(ratingText)
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }

                    Text(item.releaseYearText)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
