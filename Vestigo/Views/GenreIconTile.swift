import SwiftUI

// MARK: - GenreIconTile

struct GenreIconTile: View {
    let genre: GenreDefinition

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            genreImage

            LinearGradient(
                colors: [
                    .black.opacity(0.06),
                    .black.opacity(0.30),
                    .black.opacity(0.84)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Text(genre.name)
                .font(.system(size: 19, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .shadow(color: .black.opacity(0.80), radius: 8, y: 3)
                .padding(.horizontal, 12)
                .padding(.bottom, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 96)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.30), radius: 14, y: 9)
    }

    private var genreImage: some View {
        RemoteImageView(url: resolvedImageURL, fallback: AnyView(fallbackImage))
            .id(genre.name + "-" + (resolvedImageURL?.absoluteString ?? "fallback"))
            .frame(maxWidth: .infinity)
            .frame(height: 96)
            .clipped()
    }

    private var resolvedImageURL: URL? {
        switch genre.tmdbID {
        case 28:
            return URL(string: "https://image.tmdb.org/t/p/w780/yFihWxQcmqcaBR31QM6Y8gT6aYV.jpg")
        case 2000:
            return URL(string: "https://image.tmdb.org/t/p/w780/qJ2tW6WMUDux911r6m7haRef0WH.jpg")
        case 2010:
            return URL(string: "https://image.tmdb.org/t/p/w780/gEU2QniE6E77NI6lCU6MxlNBvIx.jpg")
        default:
            return genre.imageURLValue
        }
    }

    private var fallbackImage: some View {
        ZStack {
            fallbackBackdrop

            LinearGradient(
                colors: [.clear, .black.opacity(0.16), .black.opacity(0.48)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    @ViewBuilder private var fallbackBackdrop: some View {
        switch genre.name {
        case "00s":
            ZStack {
                LinearGradient(colors: [.blue.opacity(0.92), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle()
                    .fill(.cyan.opacity(0.34))
                    .frame(width: 140, height: 140)
                    .blur(radius: 12)
                    .offset(x: 55, y: -36)
                Image(systemName: "circle.grid.cross.fill")
                    .font(.system(size: 48, weight: .black))
                    .foregroundStyle(.white.opacity(0.28))
                    .offset(x: 42, y: -10)
            }
        case "10s":
            ZStack {
                LinearGradient(colors: [.indigo.opacity(0.92), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle()
                    .fill(.purple.opacity(0.36))
                    .frame(width: 140, height: 140)
                    .blur(radius: 14)
                    .offset(x: 50, y: -34)
                Image(systemName: "sparkles")
                    .font(.system(size: 48, weight: .black))
                    .foregroundStyle(.white.opacity(0.30))
                    .offset(x: 44, y: -12)
            }
        default:
            ZStack {
                genre.gradient
                LinearGradient(
                    colors: [.white.opacity(0.10), .clear, .black.opacity(0.18)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: fallbackSymbol)
                    .font(.system(size: 34, weight: .black))
                    .foregroundStyle(.white.opacity(0.36))
                    .offset(x: 32, y: -10)
            }
        }
    }

    private var fallbackSymbol: String {
        switch genre.name {
        case "Action": return "flame.fill"
        case "Sci-Fi": return "sparkles"
        case "Fantasy": return "wand.and.stars"
        case "Drama": return "theatermasks.fill"
        case "Horror": return "moon.fill"
        case "Animation": return "paintpalette.fill"
        case "Crime": return "magnifyingglass"
        case "Comedy": return "face.smiling.fill"
        case "Reality": return "star.fill"
        case "Talk": return "mic.fill"
        case "80s": return "clock.fill"
        case "90s": return "clock.fill"
        case "00s": return "clock.fill"
        case "10s": return "clock.fill"
        default: return "film.fill"
        }
    }
}
