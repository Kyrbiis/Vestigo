import SwiftUI
import Foundation

struct EpisodeProgressView: View {
    let show: MediaItem
    @ObservedObject var model: VestigoModel
    let seasons: [SeasonInfo]
    let isLoading: Bool
    var friendMode: Bool? = nil
    @State private var expandedSeasonNumbers = Set<Int>()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Episodes")
                .sectionTitle()

            let usableSeasons = seasons.filter { $0.number > 0 }

            if isLoading {
                LoadingBubble(title: "Loading episodes", text: "Fetching season and episode data from TMDb.")
            } else if usableSeasons.isEmpty {
                StatusBubble(title: "No episode data", text: "TMDb did not return season or episode information for this series.")
            } else {
                VStack(spacing: 10) {
                    ForEach(usableSeasons) { season in
                        SeasonDropdownView(
                            show: show,
                            season: season,
                            isExpanded: expandedSeasonNumbers.contains(season.number),
                            model: model,
                            friendMode: friendMode
                        ) {
                            withAnimation(.smooth(duration: 0.22)) {
                                if expandedSeasonNumbers.contains(season.number) {
                                    expandedSeasonNumbers.remove(season.number)
                                } else {
                                    expandedSeasonNumbers.insert(season.number)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct SeasonDropdownView: View {
    let show: MediaItem
    let season: SeasonInfo
    let isExpanded: Bool
    @ObservedObject var model: VestigoModel
    var friendMode: Bool? = nil
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(season.name)
                            .font(.headline.bold())
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        Text(season.episodeCountAndRuntimeText)
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer()

                    if friendMode == nil && (!hasUnairedEpisodes || isSeasonWatched) {
                        Button(isSeasonWatched ? "Unwatch" : "Mark") {
                            model.markSeason(
                                show: show,
                                season: season.number,
                                episodeCount: max(season.episodeCount, season.episodes.count),
                                watched: !isSeasonWatched
                            )
                        }
                        .font(.caption.bold())
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .buttonStyle(.bordered)
                        .clipShape(Capsule())
                    }

                    Image(systemName: "chevron.down")
                        .font(.caption.bold())
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .padding(12)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .opacity(0.25)
                    .padding(.horizontal, 12)

                VStack(spacing: 8) {
                    ForEach(episodeRows) { episode in
                        EpisodeRowView(show: show, seasonNumber: season.number, episode: episode, model: model, friendMode: friendMode)
                    }
                }
                .padding(12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .liquidGlass(cornerRadius: 22)
        .appScrollTouchSafe()
    }

    private var isSeasonWatched: Bool {
        if let fm = friendMode { return fm }
        let rows = episodeRows
        guard !rows.isEmpty else { return false }
        return rows.allSatisfy {
            model.library.isEpisodeWatched(showKey: show.key, season: season.number, episode: $0.number)
        }
    }

    private var hasUnairedEpisodes: Bool {
        episodeRows.contains { $0.isUpcoming }
    }

    private var episodeRows: [EpisodeInfo] {
        if !season.episodes.isEmpty {
            return season.episodes
        }

        return (1...max(season.episodeCount, 1)).map { number in
            EpisodeInfo(number: number, title: "Episode \(number)", airDate: nil, runtime: nil, stillPath: nil)
        }
    }
}

struct EpisodeRowView: View {
    let show: MediaItem
    let seasonNumber: Int
    let episode: EpisodeInfo
    @ObservedObject var model: VestigoModel
    var friendMode: Bool? = nil

    var body: some View {
        Button {
            model.toggleEpisode(show: show, season: seasonNumber, episode: episode.number)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                EpisodeThumbnailView(url: episode.stillURL)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(episode.number). \(episode.title)")
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    if !episodeMetadataText.isEmpty {
                        Text(episodeMetadataText)
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: friendMode != nil
                    ? (friendMode! ? "checkmark.circle.fill" : "circle")
                    : (episode.isUpcoming ? "clock" : (isWatched ? "checkmark.circle.fill" : "circle")))
                    .font(.title3.bold())
                    .foregroundStyle(friendMode != nil ? AnyShapeStyle(Color.blue) : (episode.isUpcoming ? AnyShapeStyle(.tertiary) : (isWatched ? AnyShapeStyle(model.settings.accentColor) : AnyShapeStyle(.secondary))))
            }
            .padding(10)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(friendMode != nil || episode.isUpcoming)
    }

    private var isWatched: Bool {
        model.library.isEpisodeWatched(showKey: show.key, season: seasonNumber, episode: episode.number)
    }

    private var episodeMetadataText: String {
        var parts: [String] = []

        if let releaseDateText = episode.releaseDateText {
            parts.append(releaseDateText)
        }

        if let runtime = episode.runtime, runtime > 0 {
            parts.append("\(runtime) min")
        }

        return parts.joined(separator: " • ")
    }
}

struct EpisodeThumbnailView: View {
    let url: URL?
    @Environment(\.imageRefreshToken) private var imageRefreshToken

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.10))

            AsyncImage(url: url?.refreshedImageURL(token: imageRefreshToken)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    Image(systemName: "tv")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 82, height: 46)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
