import SwiftUI

// MARK: - CollectionRow

struct CollectionRow: View {
    let collection: MediaCollection
    let count: Int
    let iconItem: MediaItem?

    private var collectionIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.10))

            if let iconItem {
                PosterView(item: iconItem, width: 48, height: 48, isFavourite: false)
                    .id(iconItem.key.stableID)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                Image(systemName: collection.isDynamic ? "square.grid.2x2" : "folder")
                    .font(.title3.bold())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    var body: some View {
        HStack(spacing: 12) {
            collectionIcon

            VStack(alignment: .leading, spacing: 4) {
                Text(collection.name).font(.headline)
                Text(collection.isDynamic ? "Dynamic collection • \(count) items" : "Custom collection • \(count) items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .liquidGlass(cornerRadius: 22)
        .appScrollTouchSafe()
    }
}
