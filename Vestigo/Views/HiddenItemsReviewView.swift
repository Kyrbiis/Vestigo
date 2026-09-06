import SwiftUI
import Foundation

struct HiddenItemsReviewView: View {
    @ObservedObject var model: VestigoModel

    private var entries: [(item: MediaItem, status: HiddenStatus)] {
        let neverShow = model.library.neverShowAgainItems.map { ($0, HiddenStatus.neverShow) }
        let notInterested = model.library.notInterestedItems
            .filter { !model.library.isNeverShowAgain($0.key) }
            .map { ($0, HiddenStatus.notInterested) }
        return (neverShow + notInterested)
            .sorted { lhs, rhs in
                lhs.0.title.localizedCaseInsensitiveCompare(rhs.0.title) == .orderedAscending
            }
    }

    var body: some View {
        ZStack {
            AppBackground(settings: model.settings)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if entries.isEmpty {
                        StatusBubble(
                            title: "No hidden items",
                            text: "Items marked as \"Never show\" or \"Not interested\" show up here."
                        )
                    } else {
                        ForEach(entries, id: \.item.key) { entry in
                            HiddenItemRow(
                                item: entry.item,
                                status: entry.status,
                                ratingText: model.ratingDisplayText(for: entry.item),
                                accentColor: model.settings.accentColor,
                                onOpen: { model.selectedItem = entry.item },
                                onChangeStatus: {
                                    switch entry.status {
                                    case .neverShow:
                                        model.toggleNotInterested(entry.item)
                                    case .notInterested:
                                        model.toggleNeverShowAgain(entry.item)
                                    }
                                },
                                onRestore: {
                                    switch entry.status {
                                    case .neverShow:
                                        model.toggleNeverShowAgain(entry.item)
                                    case .notInterested:
                                        model.toggleNotInterested(entry.item)
                                    }
                                }
                            )
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Hidden items")
        .navigationBarTitleDisplayMode(.inline)
    }

    enum HiddenStatus {
        case neverShow
        case notInterested

        var label: String {
            switch self {
            case .neverShow: return "Never show"
            case .notInterested: return "Not interested"
            }
        }

        var iconName: String {
            switch self {
            case .neverShow: return "eye.slash"
            case .notInterested: return "hand.thumbsdown"
            }
        }
    }
}

struct HiddenItemRow: View {
    let item: MediaItem
    let status: HiddenItemsReviewView.HiddenStatus
    let ratingText: String
    let accentColor: Color
    let onOpen: () -> Void
    let onChangeStatus: () -> Void
    let onRestore: () -> Void
    @Environment(\.imageRefreshToken) private var imageRefreshToken

    private var statusBinding: Binding<HiddenItemsReviewView.HiddenStatus> {
        Binding(
            get: { status },
            set: { newStatus in if newStatus != status { onChangeStatus() } }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onOpen) {
                HStack(alignment: .center, spacing: 12) {
                    posterThumbnail

                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.headline.bold())
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        Text(metadataLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        if !ratingText.isEmpty {
                            Text(ratingText)
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                Picker("Status", selection: statusBinding) {
                    Text("Not interested").tag(HiddenItemsReviewView.HiddenStatus.notInterested)
                    Text("Never show").tag(HiddenItemsReviewView.HiddenStatus.neverShow)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .liquidGlass(cornerRadius: 18)

                Button(action: onRestore) {
                    ZStack {
                        Circle()
                            .fill(accentColor)
                            .frame(width: 36, height: 36)
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Restore \(item.title)")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(cornerRadius: 22)
    }

    private var metadataLine: String {
        var parts: [String] = [item.kind.label]
        let yearText = item.releaseYearText
        if yearText != "TBA" {
            parts.append(yearText)
        }
        return parts.joined(separator: " • ")
    }

    private var posterThumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.08))

            if let url = item.posterURL {
                AsyncImage(url: url.refreshedImageURL(token: imageRefreshToken)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        Image(systemName: "film")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Image(systemName: "film")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 54, height: 78)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
