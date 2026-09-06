import SwiftUI
import Foundation

// MARK: - Star Rating Views

struct StarRatingView: View {
    @Binding var rating: Double
    var tint: Color = .yellow
    var isReadOnly: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(1...5, id: \.self) { index in
                Button { rating = nextRating(for: index) } label: {
                    Image(systemName: starName(index))
                        .font(.subheadline)
                        .foregroundStyle(tint)
                }
                .buttonStyle(.plain)
                .disabled(isReadOnly)
            }
            Text(rating.formatted(.number.precision(.fractionLength(1))))
                .font(.caption.bold())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .liquidGlass(cornerRadius: 22)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func starName(_ index: Int) -> String {
        let value = Double(index)
        if rating >= value { return "star.fill" }
        if rating >= value - 0.5 { return "star.leadinghalf.filled" }
        return "star"
    }

    private func nextRating(for index: Int) -> Double {
        let full = Double(index)
        if rating == full { return full - 0.5 }
        return full
    }
}

struct StarDisplay: View {
    let rating: Double
    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: rating >= Double(i) ? "star.fill" : (rating >= Double(i) - 0.5 ? "star.leadinghalf.filled" : "star"))
                    .font(.caption2)
                    .foregroundStyle(.yellow)
            }
        }
    }
}

// MARK: - Action Buttons

struct SmallActionButton: View {
    let title: String
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 9)
                .frame(width: 68, height: 28)
                .liquidGlass(cornerRadius: 14)
        }
        .buttonStyle(.plain)
    }
}

struct DetailActionButton: View {
    let title: String
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 150, height: 34)
                .liquidGlass(cornerRadius: 17)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Status / Loading Bubbles

struct StatusBubble: View {
    let title: String
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline.bold())
            Text(text).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .liquidGlass(cornerRadius: 22)
        .appScrollTouchSafe()
    }
}

struct LoadingBubble: View {
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ProgressView()
                .controlSize(.small)
                .tint(.primary)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline.bold())
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 72, alignment: .leading)
        .padding(14)
        .liquidGlass(cornerRadius: 22)
        .appScrollTouchSafe()
    }
}

// MARK: - ExternalLookupLink

struct ExternalLookupLink: View {
    let searchQuery: String
    let imdbURL: URL?
    let accentColor: Color
    let font: Font
    @Environment(\.openURL) private var openURL
    @State private var isDialogPresented = false

    var body: some View {
        Button {
            isDialogPresented = true
        } label: {
            Text("See more")
                .font(font.weight(.bold))
                .foregroundStyle(Color.blue)
        }
        .buttonStyle(.plain)
        .confirmationDialog("", isPresented: $isDialogPresented, titleVisibility: .visible) {
            if let imdbURL {
                Button("IMDb") {
                    openURL(imdbURL)
                }
            }
            Button("Search") {
                if let searchURL {
                    openURL(searchURL)
                }
            }
            Button("Cancel", role: .cancel) { }
        }
    }

    private var searchURL: URL? {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return URL(string: "https://www.google.com/search?q=\(encoded)")
    }
}
