import SwiftUI
import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(WebKit)
import WebKit
#endif
#if canImport(UserNotifications)
import UserNotifications
#endif

// MARK: - Reusable Media UI

struct BaseScreen<Content: View>: View {
    let title: String
    @Binding var filter: MediaFilter
    let settings: AppSettings
    let headerAccessory: AnyView
    let contentTopPadding: CGFloat
    let onRefresh: (() async -> Void)?
    @ViewBuilder let content: Content
    @Environment(\.refreshImages) private var refreshImages
    
    init(
        title: String,
        filter: Binding<MediaFilter>,
        settings: AppSettings,
        headerAccessory: AnyView = AnyView(EmptyView()),
        contentTopPadding: CGFloat = 0,
        onRefresh: (() async -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self._filter = filter
        self.settings = settings
        self.headerAccessory = headerAccessory
        self.contentTopPadding = contentTopPadding
        self.onRefresh = onRefresh
        self.content = content()
    }
    
    var body: some View {
        ZStack {
            AppBackground(settings: settings)
                .ignoresSafeArea()
            
            scrollContent
        }
    }

    @ViewBuilder private var scrollContent: some View {
        if let onRefresh {
            baseScroll
                .refreshable {
                    refreshImages()
                    await onRefresh()
                }
        } else {
            baseScroll
        }
    }

    @ViewBuilder private var baseScroll: some View {
        let scroll = ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                if onRefresh != nil {
                    Color.clear
                        .frame(height: 1)
                }

                HStack(alignment: .center, spacing: 12) {
                    Text(title)
                        .font(.largeTitle.bold())
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    headerAccessory
                }

                content
            }
            .padding(.top, contentTopPadding)
            .padding(16)
            .padding(.bottom, 94)
            .containerRelativeFrame(.horizontal, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .scrollClipDisabled(false)
        .scrollBounceBehavior(onRefresh == nil ? .basedOnSize : .always, axes: .vertical)
        .scrollDismissesKeyboard(.immediately)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)

        if onRefresh == nil {
            scroll.scrollViewTouchTuning(axis: .vertical)
        } else {
            scroll
        }
    }
}

struct MediaSection: View {
    let title: String
    let items: [MediaItem]
    let hideWatchedForUpcoming: Bool
    @ObservedObject var model: VestigoModel
    var oneLineOnly = true
    var openItem: ((MediaItem) -> Void)? = nil
    var openFull: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let openFull {
                Button {
                    openFull()
                } label: {
                    HStack(spacing: 8) {
                        Text(title)
                            .sectionTitle()

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Text(title)
                    .sectionTitle()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            if items.isEmpty {
                if model.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    StatusBubble(title: "Nothing here yet", text: "This section will fill after more data loads or after you rate more watched items.")
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(items.prefix(oneLineOnly ? 12 : items.count)) { item in
                            MediaTile(item: item, hideWatched: hideWatchedForUpcoming, model: model, openItem: openItem)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .scrollClipDisabled()
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MediaGridOrList: View {
    let items: [MediaItem]
    let hideWatchedForUpcoming: Bool
    @ObservedObject var model: VestigoModel
    var swipeContext: SwipeContext = .none
    var mode: ViewMode = .tile
    
    var body: some View {
        content
    }
    
    @ViewBuilder private var content: some View {
        if items.isEmpty {
            emptyState
        } else if mode == .list {
            listContent
        } else {
            gridContent
        }
    }
    
    private var emptyState: some View {
        StatusBubble(title: "No results", text: "Nothing matched the current filter.")
    }
    
    private var listContent: some View {
        MediaList(items: items, model: model)
    }
    
    private var gridContent: some View {
        LazyVGrid(columns: gridColumns, spacing: 18) {
            ForEach(items) { item in
                MediaTile(item: item, hideWatched: hideWatchedForUpcoming, model: model, swipeContext: swipeContext)
            }
        }
    }
    
    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 148), spacing: 14)]
    }
}

struct MediaItemContextMenuActions: View {
    let item: MediaItem
    let hideWatched: Bool
    @ObservedObject var model: VestigoModel
    var swipeContext: SwipeContext = .none
    let showCollections: () -> Void
    
    var body: some View {
        Button {
            showCollections()
        } label: {
            Label("Add to collection", systemImage: "folder.badge.plus")
        }
        
        Button {
            model.toggleWatchlist(item)
        } label: {
            Label(
                model.library.isInWatchlist(item.key) ? "Remove saved" : "Save",
                systemImage: model.library.isInWatchlist(item.key) ? "bookmark.slash" : "bookmark"
            )
        }
        
        if !hideWatched && !item.isUpcoming {
            Button {
                model.toggleWatched(item)
            } label: {
                Label(
                    model.library.isWatched(item.key) ? "Mark unwatched" : "Mark watched",
                    systemImage: model.library.isWatched(item.key) ? "checkmark.circle.fill" : "checkmark.circle"
                )
            }
        }
        
        if model.library.isWatched(item.key) {
            Button {
                model.requestToggleFavourite(item)
            } label: {
                Label(
                    model.library.isFavourite(item) ? "Remove favourite" : "Mark favourite",
                    systemImage: model.library.isFavourite(item) ? "star.slash" : "star"
                )
            }
        }

        Button {
            model.toggleNotInterested(item)
        } label: {
            Label(
                model.library.isNotInterested(item.key) ? "Remove not interested" : "Not interested",
                systemImage: model.library.isNotInterested(item.key) ? "hand.thumbsup" : "hand.thumbsdown"
            )
        }

        Button(role: model.library.isNeverShowAgain(item.key) ? nil : .destructive) {
            model.toggleNeverShowAgain(item)
        } label: {
            Label(
                model.library.isNeverShowAgain(item.key) ? "Show in recommendations again" : "Never show this again",
                systemImage: model.library.isNeverShowAgain(item.key) ? "eye" : "eye.slash"
            )
        }

        if case .collection(let id) = swipeContext {
            Button(role: .destructive) {
                model.removeFromCollection(item, collectionID: id)
            } label: {
                Label("Remove from collection", systemImage: "trash")
            }
        }
    }
}

struct MediaTile: View {
    let item: MediaItem
    let hideWatched: Bool
    @ObservedObject var model: VestigoModel
    var openItem: ((MediaItem) -> Void)? = nil
    var swipeContext: SwipeContext = .none
    @State private var showCollections = false

    var body: some View {
        tileCore
    }

    private var tileCore: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { openTileItem() } label: {
                PosterView(item: item, width: 148, height: 214, isFavourite: model.library.isFavourite(item))
            }
            .buttonStyle(.plain)

            .contextMenu {
                MediaItemContextMenuActions(item: item, hideWatched: hideWatched, model: model, swipeContext: swipeContext) {
                    showCollections = true
                }
            }
            .sheet(isPresented: $showCollections) {
                AddToCollectionSheet(item: item, model: model)
            }

            Text(item.title)
                .font(.subheadline.bold())
                .lineLimit(2)
                .frame(width: 148, alignment: .topLeading)
                .frame(minHeight: 36, alignment: .topLeading)

            Text(tileMetadataText)
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
                .frame(width: 148, alignment: .leading)

            HStack(spacing: 7) {
                TileIconButton(systemName: model.library.isInWatchlist(item.key) ? "bookmark.fill" : "bookmark") {
                    model.toggleWatchlist(item)
                }

                if !hideWatched && !item.isUpcoming {
                    TileIconButton(systemName: model.library.isWatched(item.key) ? "checkmark.circle.fill" : "checkmark.circle") {
                        model.toggleWatched(item)
                    }
                }
            }
            .frame(width: 148, alignment: .leading)
            .frame(minHeight: 30, alignment: .leading)
        }
        .frame(width: 148, alignment: .topLeading)
        .task(id: item.key) {
            await model.loadExternalRatings(item)
        }
    }
    
    private func openTileItem() {
        if let openItem {
            openItem(item)
        } else {
            model.selectedItem = item
        }
    }

    private var tileMetadataText: String {
        let ratingText = model.ratingDisplayText(for: item)
        if ratingText.isEmpty {
            return item.releaseDateReadable
        }
        return "\(item.releaseDateReadable) • \(ratingText)"
    }
}



struct PosterView: View {
    let item: MediaItem
    let width: CGFloat
    let height: CGFloat
    var isFavourite = false
    @Environment(\.imageRefreshToken) private var imageRefreshToken
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: width * 0.18, style: .continuous)
                .fill(item.genreGradient)
            AsyncImage(url: item.posterURL?.refreshedImageURL(token: imageRefreshToken)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    Image(systemName: item.kind == .movie ? "film" : "tv")
                        .font(.system(size: width * 0.25, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            LinearGradient(colors: [.clear, .black.opacity(0.42)], startPoint: .center, endPoint: .bottom)
            
            if isFavourite {
                Image(systemName: "star.fill")
                    .font(.system(size: max(11, width * 0.095), weight: .black))
                    .foregroundStyle(.yellow)
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
            
            AsyncImage(url: person.profileURL?.refreshedImageURL(token: imageRefreshToken)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    Image(systemName: "person.fill")
                        .font(.system(size: width * 0.32, weight: .bold))
                        .foregroundStyle(.secondary)
                }
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

struct ProviderRow: View {
    let option: StreamingOption
    @Environment(\.openURL) private var openURL
    @Environment(\.imageRefreshToken) private var imageRefreshToken
    
    private var tappableURL: URL? {
        option.tappableURL
    }
    
    var body: some View {
        Button {
            guard let tappableURL else { return }
            openURL(tappableURL)
        } label: {
            HStack(spacing: 12) {
                providerLogo
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(option.cleanedServiceName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Text(option.cleanedAvailabilityLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                if tappableURL != nil {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .liquidGlass(cornerRadius: 22)
        .opacity(tappableURL == nil ? 0.72 : 1.0)
        .appScrollTouchSafe()
    }
    
    private var providerLogo: some View {
        let catalogService = option.matchedCatalogService
        return ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(catalogService.map { Color(hex: $0.brandColorHex) } ?? .white.opacity(0.13))

            if let url = option.logoURL {
                AsyncImage(url: url.refreshedImageURL(token: imageRefreshToken)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 52, height: 52)
                            .clipped()
                    default:
                        providerFallbackText(lightText: catalogService?.lightText ?? true)
                    }
                }
            } else {
                providerFallbackText(lightText: catalogService?.lightText ?? true)
            }
        }
        .frame(width: 52, height: 52)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func providerFallbackText(lightText: Bool) -> some View {
        Text(option.serviceShort)
            .font(.caption.bold())
            .foregroundStyle(lightText ? Color.white : Color.black)
    }
}

extension StreamingOption {
    var cleanedServiceName: String {
        let trimmed = serviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unknown service" : trimmed
    }
    
    var cleanedAvailabilityLine: String {
        let parts = [cleanedTypeText, cleanedPriceText, cleanedQualityText]
            .compactMap { $0 }
        
        if parts.isEmpty {
            return "Availability details not provided"
        }
        
        return parts.joined(separator: " • ")
    }

    var dialogTitle: String {
        "\(cleanedServiceName) - \(cleanedAvailabilityLine)"
    }

    var tappableURL: URL? {
        guard let rawURL = openURL?.trimmingCharacters(in: .whitespacesAndNewlines), !rawURL.isEmpty else {
            return nil
        }
        return URL(string: rawURL)
    }
    
    private var cleanedTypeText: String? {
        let trimmed = type.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.isUnknownPlaceholder else { return nil }
        return trimmed.capitalized
    }
    
    private var cleanedPriceText: String? {
        let trimmed = priceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.isUnknownPlaceholder else { return nil }
        return trimmed
    }
    
    private var cleanedQualityText: String? {
        let trimmed = qualityText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.isUnknownPlaceholder else { return nil }
        return trimmed
    }
    
    var matchedCatalogService: KnownStreamingService? {
        KnownStreamingService.catalog.first { $0.matches(serviceName) }
    }

    var logoURL: URL? {
        // Prefer Brandfetch via catalog — higher quality than favicons
        if let domain = matchedCatalogService?.domain {
            return URL(string: "https://mtttuyvpjyugudkevchj.supabase.co/functions/v1/vestigo-api/brand-logo?domain=\(domain)&w=128&h=128")
        }
        // Fallback: Google favicon for services not yet in catalog
        guard let domain = serviceLogoDomain else { return nil }
        var components = URLComponents(string: "https://www.google.com/s2/favicons")
        components?.queryItems = [
            URLQueryItem(name: "sz", value: "128"),
            URLQueryItem(name: "domain", value: domain)
        ]
        return components?.url
    }

    private var serviceLogoDomain: String? {
        let normalized = cleanedServiceName
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "+", with: "plus")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "-", with: "")

        if normalized.contains("showtime") { return "showtime.com" }
        if normalized.contains("googleplay") { return "play.google.com" }
        if normalized.contains("microsoft") { return "microsoft.com" }
        if normalized.contains("hoopla") { return "hoopladigital.com" }
        if normalized.contains("freevee") { return "amazon.com" }

        return nil
    }
}

extension String {
    var isUnknownPlaceholder: Bool {
        let normalized = trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "unknown" || normalized == "unknown price" || normalized == "price unknown" || normalized == "unknown quality" || normalized == "quality unknown" || normalized == "n/a" || normalized == "na" || normalized == "none"
    }
    
    var normalizedForMatching: String {
        lowercased()
            .replacingOccurrences(of: "&", with: "and")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}


struct SearchBubble: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    var onSubmit: () -> Void = {}
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
            TextField("Search movies, series, people...", text: $text)
                .textFieldStyle(.plain)
                .focused(isFocused)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled(false)
                .submitLabel(.search)
                .onSubmit {
                    onSubmit()
                }
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .liquidGlass(cornerRadius: 24)
    }
}


struct FilterPills: View {
    @Binding var filter: MediaFilter
    let options: [MediaFilter]
    let onChange: () -> Void
    
    var body: some View {
        Picker("Filter", selection: $filter) {
            ForEach(options) { item in
                Text(item.title).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .liquidGlass(cornerRadius: 18)
        .onChange(of: filter) { _, _ in
            onChange()
        }
    }
}

struct SortPicker: View {
    @Binding var sort: SortOption
    let includeMyRating: Bool
    let ratingSource: RatingSource

    var body: some View {
        Picker("Sort", selection: $sort) {
            Text("Released").tag(SortOption.releaseDate)

            if includeMyRating {
                Text("My rating").tag(SortOption.myRating)
            }

            Text(ratingSource.title).tag(SortOption.tmdbRating)
        }
        .pickerStyle(.segmented)
        .liquidGlass(cornerRadius: 18)
    }
}

struct SortDirectionButton: View {
    @Binding var direction: SortDirection

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                direction.toggle()
            }
        } label: {
            Image(systemName: direction.iconName)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 42, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .liquidGlass(cornerRadius: 18)
        .accessibilityLabel(direction.accessibilityLabel)
    }
}

struct SortRow<Picker: View>: View {
    @Binding var direction: SortDirection
    @ViewBuilder let picker: Picker

    var body: some View {
        HStack(spacing: 8) {
            picker
                .frame(maxWidth: .infinity)

            SortDirectionButton(direction: $direction)
        }
    }
}

struct StarRatingView: View {
    @Binding var rating: Double
    
    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { index in
                Button { rating = nextRating(for: index) } label: {
                    Image(systemName: starName(index))
                        .font(.title2)
                        .foregroundStyle(.yellow)
                }
                .buttonStyle(.plain)
            }
            Text(rating.formatted(.number.precision(.fractionLength(1))))
                .font(.caption.bold())
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .liquidGlass(cornerRadius: 20)
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

struct TileIconButton: View {
    let systemName: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .bold))
                .frame(width: 32, height: 28)
                .liquidGlass(cornerRadius: 14)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(systemName.contains("bookmark") ? "Save" : "Watched")
    }
}

struct RemoteImageView: View {
    let url: URL?
    let fallback: AnyView
    @State private var platformImage: PlatformImage?
    @State private var loadedURL: URL?
    
    var body: some View {
        ZStack {
            if let platformImage {
                platformImageView(platformImage)
            } else {
                fallback
            }
        }
        .task(id: url) {
            await loadImage()
        }
    }
    
    @ViewBuilder
    private func platformImageView(_ image: PlatformImage) -> some View {
#if canImport(UIKit)
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
#elseif canImport(AppKit)
        Image(nsImage: image)
            .resizable()
            .scaledToFill()
#endif
    }
    
    @MainActor
    private func setLoadedImage(_ image: PlatformImage?, for url: URL?) {
        platformImage = image
        loadedURL = url
    }
    
    private func loadImage() async {
        guard let url else {
            setLoadedImage(nil, for: nil)
            return
        }
        
        if loadedURL == url, platformImage != nil {
            return
        }

        if let cachedImage = RemoteImageMemoryCache.shared.image(for: url) {
            setLoadedImage(cachedImage, for: url)
            return
        }
        
        do {
            let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                setLoadedImage(nil, for: url)
                return
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                setLoadedImage(nil, for: url)
                return
            }
            guard let image = PlatformImage(data: data) else {
                setLoadedImage(nil, for: url)
                return
            }
            RemoteImageMemoryCache.shared.setImage(image, for: url)
            setLoadedImage(image, for: url)
        } catch {
            setLoadedImage(nil, for: url)
        }
    }
}

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
        case "80s": return "clock.fill"
        case "90s": return "clock.fill"
        case "00s": return "clock.fill"
        case "10s": return "clock.fill"
        default: return "film.fill"
        }
    }
}

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

struct AppBackground: View {
    let settings: AppSettings
    
    var body: some View {
        Group {
            if settings.usePlainBackground {
                settings.appearance == .dark ? Color.black : Color.white
            } else {
                GeometryReader { proxy in
                    let topInset = proxy.safeAreaInsets.top
                    let bottomInset = proxy.safeAreaInsets.bottom
                    let fullHeight = proxy.size.height + topInset + bottomInset
                    
                    ZStack(alignment: .topLeading) {
                        LinearGradient(
                            colors: backgroundColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .frame(width: proxy.size.width, height: fullHeight)
                        
                        Circle()
                            .fill(settings.accentColor.opacity(settings.appearance == .dark ? 0.34 : 0.28))
                            .frame(width: 360, height: 360)
                            .blur(radius: 70)
                            .position(x: 50, y: -80)
                        
                        Circle()
                            .fill(settings.accentColor.opacity(settings.appearance == .dark ? 0.24 : 0.20))
                            .frame(width: 360, height: 360)
                            .blur(radius: 78)
                            .position(x: proxy.size.width + 40, y: 270)
                        
                        Circle()
                            .fill(settings.accentColor.opacity(settings.appearance == .dark ? 0.18 : 0.16))
                            .frame(width: 420, height: 420)
                            .blur(radius: 95)
                            .position(x: proxy.size.width * 0.62, y: 720)
                    }
                    .frame(width: proxy.size.width, height: fullHeight, alignment: .topLeading)
                    .offset(y: -topInset)
                }
            }
        }
        .ignoresSafeArea()
    }
    
    private var backgroundColors: [Color] {
        if settings.appearance == .dark {
            return [
                settings.accentColor.opacity(0.22),
                Color(red: 0.04, green: 0.045, blue: 0.075),
            ]
        } else {
            return [
                settings.accentColor.opacity(0.22),
                Color.white,
                settings.accentColor.opacity(0.16),
                Color(red: 0.90, green: 0.93, blue: 0.98)
            ]
        }
    }
}

// MARK: - API Services



final class RemoteImageMemoryCache {
    static let shared = RemoteImageMemoryCache()
    private var images: [URL: PlatformImage] = [:]

    func image(for url: URL) -> PlatformImage? {
        images[url]
    }

    func setImage(_ image: PlatformImage, for url: URL) {
        images[url] = image
    }
}


// MARK: - Swipe To Delete Modifier

private struct SwipeToDeleteModifier: ViewModifier {
    let cornerRadius: CGFloat
    let action: () -> Void
    @State private var offset: CGFloat = 0
    private let threshold: CGFloat = 72

    func body(content: Content) -> some View {
        ZStack(alignment: .trailing) {
            if offset < -2 {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.red)
                    // Cap at threshold * 1.5 so the ZStack never expands beyond the row width during fly-out
                    .frame(width: min(max(0, -offset), threshold * 1.5))
                    .overlay(alignment: .center) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .opacity(min(1.0, max(0, (abs(offset) - 24) / 20)))
                    }
            }

            content
                .offset(x: offset)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onChanged { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    guard dx < 0, abs(dx) > abs(dy) else { return }
                    withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.85)) {
                        offset = max(-threshold * 1.5, dx)
                    }
                }
                .onEnded { _ in
                    if offset < -threshold {
                        withAnimation(.easeIn(duration: 0.16)) { offset = -500 }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { action() }
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { offset = 0 }
                    }
                }
        )
    }
}

extension View {
    func swipeToDelete(cornerRadius: CGFloat = 16, action: @escaping () -> Void) -> some View {
        modifier(SwipeToDeleteModifier(cornerRadius: cornerRadius, action: action))
    }
}

// MARK: - LiquidGlass Modifier

struct LiquidGlassModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            content
                .padding(1)
                .background(.clear, in: shape)
                .glassEffect(.regular, in: shape)
                .overlay { shape.fill(colorScheme == .light ? .black.opacity(0.11) : .clear) }
                .overlay { shape.stroke(colorScheme == .light ? .black.opacity(0.22) : .clear, lineWidth: 1) }
                .clipShape(shape)
                .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 9)
        } else {
            content
                .background {
                    shape
                        .fill(.ultraThinMaterial)
                        .background(shape.fill(colorScheme == .light ? .black.opacity(0.13) : .white.opacity(0.10)))
                        .overlay { shape.stroke(colorScheme == .light ? .black.opacity(0.22) : .white.opacity(0.16), lineWidth: 1) }
                        .shadow(color: .black.opacity(colorScheme == .light ? 0.16 : 0.22), radius: 18, x: 0, y: 10)
                }
                .clipShape(shape)
        }
    }
}

// MARK: - View Modifier Extensions

extension View {
    @ViewBuilder
    func appScrollTouchSafe() -> some View { self }

    func liquidGlass(cornerRadius: CGFloat = 24) -> some View {
        modifier(LiquidGlassModifier(cornerRadius: cornerRadius))
    }

    @ViewBuilder
    func sheetLiquidGlass(cornerRadius: CGFloat = 54) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape).clipShape(shape)
                .shadow(color: .black.opacity(0.10), radius: 18, x: 0, y: 10)
        } else {
            self.background { shape.fill(.clear).shadow(color: .black.opacity(0.10), radius: 18, x: 0, y: 10) }
                .clipShape(shape)
        }
    }

    @ViewBuilder
    func selectedGlassCapsule(isSelected: Bool) -> some View {
        if isSelected {
            if #available(iOS 26.0, *) {
                self.padding(.horizontal, 1)
                    .background(.white.opacity(0.10), in: Capsule())
                    .glassEffect(.regular, in: Capsule())
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 5)
            } else {
                self.background(.white.opacity(0.18), in: Capsule())
                    .overlay { Capsule().stroke(.white.opacity(0.18), lineWidth: 1) }
            }
        } else {
            self.background(.clear, in: Capsule())
        }
    }

    @ViewBuilder
    func edgeBackGesture(isEnabled: Bool = true, action: @escaping () -> Void) -> some View {
        if isEnabled {
            self.background(alignment: .leading) {
                Color.clear.frame(width: 18).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 18, coordinateSpace: .global)
                        .onEnded { value in
                            let h = abs(value.translation.width) > abs(value.translation.height) * 2.0
                            if h && value.translation.width > 84 { action() }
                        })
            }
        } else {
            self
        }
    }

    func settingBubble() -> some View {
        self.padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.black.opacity(0.2)) }
            .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 1) }
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

#if canImport(UIKit)
struct ScrollViewTouchTuningView: UIViewRepresentable {
    let axis: Axis.Set
    let alwaysBounce: Bool

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        DispatchQueue.main.async { configureNearestScrollView(from: view) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { configureNearestScrollView(from: view) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { configureNearestScrollView(from: view) }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async { configureNearestScrollView(from: uiView) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { configureNearestScrollView(from: uiView) }
    }

    private func configureNearestScrollView(from view: UIView) {
        var current = view.superview
        while let candidate = current {
            if let scrollView = candidate as? UIScrollView { configure(scrollView); return }
            current = candidate.superview
        }
    }

    private func configure(_ scrollView: UIScrollView) {
        scrollView.panGestureRecognizer.minimumNumberOfTouches = 1
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = true
        scrollView.keyboardDismissMode = .onDrag
        scrollView.isDirectionalLockEnabled = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceVertical = axis == .vertical && alwaysBounce
        scrollView.alwaysBounceHorizontal = axis == .horizontal && alwaysBounce

        let vInset = scrollView.adjustedContentInset.top + scrollView.adjustedContentInset.bottom
        let hInset = scrollView.adjustedContentInset.left + scrollView.adjustedContentInset.right
        let canV = scrollView.contentSize.height + vInset > scrollView.bounds.height + 1
        let canH = scrollView.contentSize.width + hInset > scrollView.bounds.width + 1
        scrollView.isScrollEnabled = true
        scrollView.bounces = alwaysBounce || (axis == .horizontal ? canH : canV)
    }
}

extension View {
    func scrollViewTouchTuning(axis: Axis.Set = .vertical, alwaysBounce: Bool = false) -> some View {
        background(ScrollViewTouchTuningView(axis: axis, alwaysBounce: alwaysBounce))
    }
}
#else
extension View {
    func scrollViewTouchTuning(axis: Axis.Set = .vertical, alwaysBounce: Bool = false) -> some View {
        self
    }
}
#endif

// MARK: - Text Extensions

extension Text {
    func sectionTitle() -> some View {
        self.font(.system(size: 20, weight: .black, design: .rounded))
    }
}

// MARK: - PersonKnownForSortPicker

struct PersonKnownForSortPicker: View {
    @Binding var sort: PersonKnownForSort

    var body: some View {
        HStack(spacing: 0) {
            ForEach(PersonKnownForSort.allCases) { item in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { sort = item }
                } label: {
                    Text(item.title)
                        .font(.caption.bold())
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .selectedGlassCapsule(isSelected: sort == item)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .liquidGlass(cornerRadius: 18)
    }
}

// MARK: - FullMediaListView

struct FullMediaListView: View {
    let title: String
    let items: [MediaItem]
    @ObservedObject var model: VestigoModel

    var body: some View {
        BaseScreen(title: title, filter: .constant(.both), settings: model.settings) {
            MediaGridOrList(items: items, hideWatchedForUpcoming: false, model: model)
        }
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

// MARK: - Color Helpers

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
