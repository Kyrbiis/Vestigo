import SwiftUI
import Foundation
#if canImport(UIKit)
import UIKit
#endif

struct AboutInfoView: View {
    @AppStorage("Vestigo.devMode") private var devMode: Bool = false
    @State private var titleTapCount = 0
    @State private var showFeedbackFallback = false

    private var versionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String

        switch (version, build) {
        case let (.some(version), .some(build)) where !version.isEmpty && !build.isEmpty:
            return "Version \(version) (\(build))"
        case let (.some(version), _) where !version.isEmpty:
            return "Version \(version)"
        default:
            return "Version unavailable"
        }
    }

    var body: some View {
        VStack(alignment: .center, spacing: 16) {
            VStack(alignment: .center, spacing: 4) {
                Text("Vestigo")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)
                    .onTapGesture {
                        guard !devMode else { return }
                        titleTapCount += 1
                        if titleTapCount >= 7 {
                            devMode = true
                            titleTapCount = 0
                        }
                    }

                Text(versionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Created by Jojo Hyman")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            AboutLinkButton(
                title: "GitHub",
                systemImage: "chevron.left.forwardslash.chevron.right",
                url: URL(string: "https://github.com/Kyrbiis/Vestigo")!
            )

            Button {
                let url = URL(string: "mailto:vestigosupport@gmail.com")!
                #if canImport(UIKit)
                UIApplication.shared.open(url) { success in
                    if !success { showFeedbackFallback = true }
                }
                #endif
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "envelope")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Send Feedback")
                        .font(.caption.bold())
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            }
            .buttonStyle(.plain)
            .liquidGlass(cornerRadius: 17)
            .alert("Send Feedback", isPresented: $showFeedbackFallback) {
                Button("Copy Email") {
                    #if canImport(UIKit)
                    UIPasteboard.general.string = "vestigosupport@gmail.com"
                    #endif
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Email us at vestigosupport@gmail.com")
            }

            VStack(alignment: .center, spacing: 6) {
                Text("Your library and preferences are stored on-device and in iCloud where enabled.")
                Text("Vestigo was vibe coded: AI assisted with code implementation, while the product thinking, decisions, review, and non-coding work were all done by people.")
                Text("Vestigo is not affiliated with TMDB, IMDb, OMDb, TheTVDB, Watchmode, YouTube, Brandfetch, Wikimedia, or their parent companies.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 8)
    }
}

struct AboutLinkButton: View {
    let title: String
    let systemImage: String
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))

                Text(title)
                    .font(.caption.bold())
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .buttonStyle(.plain)
        .liquidGlass(cornerRadius: 17)
    }
}

struct AttributionFooter: View {
    @AppStorage("Vestigo.showCinemas") private var showCinemas = false

    private var providers: [AttributionProvider] {
        var list = AttributionProvider.all
        if showCinemas {
            let wikimediaIndex = list.firstIndex(where: { $0.id == "wikimedia" }) ?? list.endIndex
            list.insert(AttributionProvider.amc, at: wikimediaIndex)
        }
        return list
    }

    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            Text("Vestigo combines catalog, ratings, recommendations, availability, trailer, and open-knowledge data from the following services:")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .center, spacing: 14) {
                ForEach(providers) { provider in
                    Link(destination: provider.url) {
                        AttributionProviderRow(provider: provider)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }
}

struct AttributionProviderRow: View {
    let provider: AttributionProvider

    var body: some View {
        VStack(alignment: .center, spacing: provider.hasLogo ? 5 : 0) {
            AttributionLogoView(provider: provider)

            Text(provider.description)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 320)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct AttributionLogoView: View {
    let provider: AttributionProvider

    var body: some View {
        ZStack {
            if let logoText = provider.logoText {
                Text(logoText)
                    .font(.custom("HelveticaNeue-Thin", fixedSize: 30))
                    .fontWeight(.thin)
                    .foregroundStyle(Color(red: 0.42, green: 0.42, blue: 0.42))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else if let logoURL = provider.logoURL {
                AsyncImage(url: logoURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .padding(6)
                    default:
                        fallback
                    }
                }
            } else if let logoAssetName = provider.logoAssetName {
                Image(logoAssetName)
                    .resizable()
                    .scaledToFit()
                    .padding(2)
            } else {
                fallback
            }
        }
        .frame(width: provider.logoAssetName == nil ? 120 : 150, height: provider.hasLogo ? provider.logoHeight : 0)
        .opacity(provider.hasLogo ? 1 : 0)
        .accessibilityHidden(true)
    }

    private var fallback: some View {
        Text(provider.shortLabel)
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 4)
    }
}

struct AttributionProvider: Identifiable {
    let id: String
    let name: String
    let shortLabel: String
    let description: String
    let url: URL
    let logoURL: URL?
    let logoAssetName: String?
    let logoText: String?
    var logoHeight: CGFloat = 36

    var hasLogo: Bool {
        logoURL != nil || logoAssetName != nil || logoText != nil
    }

    static let all: [AttributionProvider] = [
        AttributionProvider(
            id: "tmdb",
            name: "TMDB",
            shortLabel: "TMDB",
            description: "This product uses the TMDB API but is not endorsed or certified by TMDB.",
            url: URL(string: "https://www.themoviedb.org/")!,
            logoURL: nil,
            logoAssetName: "TMDBLogo",
            logoText: nil
        ),
        AttributionProvider(
            id: "watchmode",
            name: "Watchmode",
            shortLabel: "WM",
            description: "Streaming availability and provider data are provided in part by Watchmode.",
            url: URL(string: "https://api.watchmode.com/")!,
            logoURL: nil,
            logoAssetName: "WatchmodeLogo",
            logoText: nil
        ),
        AttributionProvider(
            id: "thetvdb",
            name: "TheTVDB",
            shortLabel: "TVDB",
            description: "Series, season, episode, and franchise metadata are provided in part by TheTVDB.",
            url: URL(string: "https://thetvdb.com/")!,
            logoURL: URL(string: "https://www.thetvdb.com/images/attribution/logo1.png"),
            logoAssetName: nil,
            logoText: nil,
            logoHeight: 46
        ),
        AttributionProvider(
            id: "omdb",
            name: "OMDb",
            shortLabel: "OMDb",
            description: "This product uses the OMDb API but is not endorsed or certified by OMDb or IMDb. Ratings and movie data are provided in part by The Open Movie Database and IMDb.",
            url: URL(string: "https://www.omdbapi.com/")!,
            logoURL: nil,
            logoAssetName: nil,
            logoText: "OMDb API"
        ),
        /*
        TasteDive attribution is intentionally disabled because the app no longer calls
        TasteDive in the active recommendation path. If we re-enable TasteDive as a live
        data source later, restore this provider entry at the same time.

        AttributionProvider(
            id: "tastedive",
            name: "TasteDive",
            shortLabel: "TD",
            description: "Some similar-title candidate data is provided by the legacy TasteDive API.",
            url: URL(string: "https://tastedive.com/read/api")!,
            logoURL: nil,
            logoAssetName: "TasteDiveLogo",
            logoText: nil
        ),
        */
        AttributionProvider(
            id: "youtube",
            name: "YouTube",
            shortLabel: "YT",
            description: "Trailer playback uses embedded YouTube videos where available.",
            url: URL(string: "https://www.youtube.com/")!,
            logoURL: nil,
            logoAssetName: "YouTubeLogo",
            logoText: nil,
            logoHeight: 30
        ),
        AttributionProvider(
            id: "brandfetch",
            name: "Brandfetch",
            shortLabel: "BF",
            description: "Streaming service brand logos and assets are powered by Brandfetch.",
            url: URL(string: "https://brandfetch.com/")!,
            logoURL: nil,
            logoAssetName: "BrandfetchLogo",
            logoText: nil,
            logoHeight: 30
        ),
        AttributionProvider(
            id: "wikimedia",
            name: "Wikidata and Wikipedia",
            shortLabel: "W",
            description: "Original-media and knowledge links use Wikimedia projects and their content licenses.",
            url: URL(string: "https://www.wikidata.org/")!,
            logoURL: nil,
            logoAssetName: nil,
            logoText: nil
        )
    ]

    static let amc = AttributionProvider(
        id: "amc",
        name: "AMC Theatres",
        shortLabel: "AMC",
        description: "Cinema showtimes and theatre locations are provided by AMC Theatres.",
        url: URL(string: "https://www.amctheatres.com/")!,
        logoURL: nil,
        logoAssetName: "AMCLogo",
        logoText: nil,
        logoHeight: 28
    )
}
