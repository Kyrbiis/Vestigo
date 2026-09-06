import SwiftUI
import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Poster & Person Images

struct PosterView: View {
    let item: MediaItem
    let width: CGFloat
    let height: CGFloat
    var isFavourite = false
    var favouriteColor: Color = .yellow
    @Environment(\.imageRefreshToken) private var imageRefreshToken

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: width * 0.18, style: .continuous)
                .fill(item.genreGradient)
            CachedAsyncImage(url: item.posterURL(displayWidth: width)?.refreshedImageURL(token: imageRefreshToken)) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: item.kind == .movie ? "film" : "tv")
                    .font(.system(size: width * 0.25, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
            }
            LinearGradient(colors: [.clear, .black.opacity(0.42)], startPoint: .center, endPoint: .bottom)

            if isFavourite {
                Image(systemName: "star.fill")
                    .font(.system(size: max(11, width * 0.095), weight: .black))
                    .foregroundStyle(favouriteColor)
                    .padding(max(5, width * 0.045))
                    .background(.black.opacity(0.64), in: Circle())
                    .padding(max(5, width * 0.045))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .zIndex(20)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: width * 0.18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: width * 0.18, style: .continuous)
                .stroke(.white.opacity(0.22), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.36), radius: 20, x: 0, y: 12)
        .shadow(color: .white.opacity(0.08), radius: 8, x: -3, y: -3)
    }
}

struct PersonImageView: View {
    let person: PersonSummary
    let width: CGFloat
    let height: CGFloat
    @Environment(\.imageRefreshToken) private var imageRefreshToken

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: width * 0.18, style: .continuous)
                .fill(.white.opacity(0.12))

            CachedAsyncImage(url: person.profileURL?.refreshedImageURL(token: imageRefreshToken)) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "person.fill")
                    .font(.system(size: width * 0.32, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: width * 0.18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: width * 0.18, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.24), radius: 14, y: 8)
    }
}

// MARK: - PersonSearchResultRow

struct PersonSearchResultRow: View {
    let person: PersonSummary
    @ObservedObject var model: VestigoModel
    var expanded: Bool = false

    var body: some View {
        Button {
            model.selectedPerson = person
        } label: {
            HStack(spacing: expanded ? 16 : 12) {
                PersonImageView(person: person, width: expanded ? 78 : 58, height: expanded ? 96 : 76)

                VStack(alignment: .leading, spacing: expanded ? 7 : 5) {
                    Text(person.name)
                        .font(expanded ? .title3.bold() : .headline.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    if let detail = model.personDetails[person.id], let metadata = detail.compactMetadataText {
                        Text(metadata).font(.caption.bold()).foregroundStyle(.secondary).lineLimit(1)
                    } else {
                        Text(person.role.isEmpty ? "Known for" : person.role)
                            .font(.caption.bold()).foregroundStyle(.secondary).lineLimit(1)
                    }

                    if expanded, let detail = model.personDetails[person.id], let summary = detail.tinyBiography {
                        Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    } else if expanded, let preview = person.extraPreviewText {
                        Text(preview).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary)
            }
            .padding(.horizontal, expanded ? 16 : 12)
            .padding(.vertical, expanded ? 16 : 12)
            .liquidGlass(cornerRadius: expanded ? 26 : 22)
        }
        .buttonStyle(.plain)
        .task { await model.loadPersonDetailIfNeeded(person) }
    }
}
