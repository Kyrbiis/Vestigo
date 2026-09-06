import SwiftUI
import Foundation

struct RelatedMediaCarousel: View {
    let section: RelatedMediaSection

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.title)
                .sectionTitle()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(section.items) { item in
                        RelatedMediaCard(item: item)
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .scrollClipDisabled()
            .scrollIndicators(.hidden)
            .scrollViewTouchTuning(axis: .horizontal)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RelatedMediaCard: View {
    let item: RelatedMediaItem
    @State private var wikiThumb: URL?

    var body: some View {
        Link(destination: item.linkURL) {
            VStack(alignment: .leading, spacing: 6) {
                RelatedMediaImageView(url: item.imageURLValue ?? wikiThumb)

                Text(item.title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .frame(width: 132, alignment: .topLeading)

                if !item.description.isEmpty {
                    Text(item.description)
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(width: 132, alignment: .topLeading)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: 132, alignment: .topLeading)
        .task(id: item.id) {
            guard item.imageURLValue == nil else { return }
            wikiThumb = await Self.fetchWikipediaThumbnail(from: item.linkURL)
        }
    }

    private static func fetchWikipediaThumbnail(from articleURL: URL) async -> URL? {
        guard let host = articleURL.host, host.contains("wikipedia.org") else { return nil }
        let pathComponents = articleURL.pathComponents
        guard let wikiIndex = pathComponents.firstIndex(of: "wiki"),
              wikiIndex + 1 < pathComponents.count else { return nil }

        let title = pathComponents[wikiIndex + 1]
        guard !title.isEmpty,
              let summaryURL = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(title)") else { return nil }

        guard let (data, _) = try? await URLSession.shared.data(from: summaryURL) else { return nil }

        struct WikiSummary: Decodable {
            struct Thumbnail: Decodable { let source: String }
            let thumbnail: Thumbnail?
        }

        guard let summary = try? JSONDecoder().decode(WikiSummary.self, from: data),
              let sourceStr = summary.thumbnail?.source else { return nil }
        return URL(string: sourceStr)
    }
}

struct RelatedMediaImageView: View {
    let url: URL?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.white.opacity(0.10))

            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    Image(systemName: "book.closed")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 132, height: 176)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
    }
}

struct SoundtrackLinksView: View {
    let query: String
    @State private var availablePlatforms: [SoundtrackPlatform]?

    var body: some View {
        Group {
            if let availablePlatforms, !availablePlatforms.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Soundtrack")
                        .sectionTitle()

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                        ForEach(availablePlatforms) { platform in
                            if let url = platform.searchURL(for: query) {
                                Link(destination: url) {
                                    HStack(spacing: 10) {
                                        SoundtrackPlatformLogoView(platform: platform)

                                        Text(platform.title)
                                            .font(.subheadline.bold())
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.78)
                                            .foregroundStyle(.primary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                                    .liquidGlass(cornerRadius: 22)
                                    .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task(id: query) {
            availablePlatforms = await SoundtrackAvailabilityService.availablePlatforms(for: query)
        }
    }
}

struct SoundtrackPlatformLogoView: View {
    let platform: SoundtrackPlatform

    var body: some View {
        AsyncImage(url: platform.logoURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
            default:
                Text(platform.shortTitle)
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 26, height: 26)
    }
}
