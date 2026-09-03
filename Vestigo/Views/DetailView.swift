import SwiftUI
import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(MapKit)
import MapKit
#endif
#if canImport(CoreLocation)
import CoreLocation
#endif
#if canImport(WebKit)
import WebKit
#endif
#if canImport(UserNotifications)
import UserNotifications
#endif

// MARK: - Detail

struct DetailView: View {
    let item: MediaItem
    @ObservedObject var model: VestigoModel
    var allowsPersonSheet: Bool = true
    @Environment(\.imageRefreshToken) private var imageRefreshToken
    @State private var showCast = false
    @State private var showCollections = false
    @State private var selectedNestedItem: MediaItem?
    @State private var isPosterPreviewPresented = false
    @State private var showWatchedDatePopover = false
    @State private var showingFriendRating = true
    #if canImport(CoreLocation)
    @StateObject private var cinemaService = CinemaSearchService()
    @State private var cinemaSelectedDate: Date = Calendar.current.startOfDay(for: Date())
    #endif
    
    private var detail: MediaDetail? { model.detailsCache[item.key] }
    private var providers: [StreamingOption]? { model.providerCache[item.key] }
    private var isTMDbFallback: Bool { model.tmdbFallbackKeys.contains(item.key) }
    private var visibleProviders: [StreamingOption]? {
        guard let filtered = providers?.filter({ !$0.serviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return nil }
        let subscribed = model.settings.subscribedServiceNames
        guard !subscribed.isEmpty else { return filtered }
        return filtered.sorted { a, b in
            let aIn = a.isSubscribed(in: subscribed)
            let bIn = b.isSubscribed(in: subscribed)
            if aIn != bIn { return aIn }
            return false
        }
    }
    private var relatedMediaSections: [RelatedMediaSection] { model.relatedMediaCache[item.key] ?? [] }

    private enum ProviderAvailability { case available, paidOnly, unavailable }

    private var providerAvailability: ProviderAvailability? {
        let subscribed = model.settings.subscribedServiceNames
        guard !subscribed.isEmpty, let options = providers else { return nil }
        let hasFree = options.contains {
            ["subscription", "sub", "free"].contains($0.type.lowercased()) && $0.isSubscribed(in: subscribed)
        }
        if hasFree { return .available }
        let hasPaid = options.contains {
            ["rent", "buy", "addon"].contains($0.type.lowercased()) && $0.isSubscribed(in: subscribed)
        }
        return hasPaid ? .paidOnly : .unavailable
    }
    private var externalRatings: ExternalRatings? { model.externalRatingsCache[item.key] }
    
    private var selectedPersonBinding: Binding<PersonSummary?> {
        Binding(
            get: { allowsPersonSheet ? model.selectedPerson : nil },
            set: { model.selectedPerson = $0 }
        )
    }
    
    var body: some View {
        detailSheetSurface
            .overlay {
                if isPosterPreviewPresented {
                    posterPreviewOverlay
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: isPosterPreviewPresented)
            .favouriteReplacementOverlay(model: model)
            .ratingPromptOverlay(model: model, suppressedItemKey: model.friendDetailContext == nil ? item.key : nil)
            .presentationBackground(.clear)
            .presentationCornerRadius(54)
            .task { await model.loadDetail(item) }
            .onDisappear { model.friendDetailContext = nil }
            .sheet(isPresented: $showCollections) {
                AddToCollectionSheet(item: item, model: model)
            }
            .sheet(item: selectedPersonBinding) { person in
                PersonDetailView(person: person, model: model)
            }
            .sheet(item: $selectedNestedItem) { item in
                DetailView(item: item, model: model, allowsPersonSheet: allowsPersonSheet)
            }
    }
    
    private var detailSheetSurface: some View {
        detailScroll
            .safeAreaInset(edge: .top, spacing: 0) {
                sheetGrabBar
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .sheetLiquidGlass(cornerRadius: 48)
            .ignoresSafeArea(edges: .bottom)
    }

    private var sheetGrabBar: some View {
        Capsule()
            .fill(.white.opacity(0.46))
            .frame(width: 48, height: 5)
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(.clear)
    }
    
    private var detailScroll: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                headerSection
                ratingSection
                detailButtons
                overviewSection
                actionSection
                castSection
                episodeSection
                similarSection
                trailerSection
                providersSection
                cinemasSection
                relatedMediaSection
                soundtrackSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 110)
        }
        .scrollClipDisabled()
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        .scrollDismissesKeyboard(.immediately)
        .scrollIndicators(.hidden)
        .scrollViewTouchTuning(axis: .vertical)
    }
    
    private var headerSection: some View {
        HStack(alignment: .top, spacing: 16) {
            Button {
                isPosterPreviewPresented = true
            } label: {
                PosterView(item: item, width: 126, height: 188, isFavourite: model.library.isFavourite(item))
            }
            .buttonStyle(.plain)
            .disabled(item.posterURL == nil)
            .accessibilityLabel("Open poster")
            
            VStack(alignment: .leading, spacing: 10) {
                titleText
                metadataText
                ageRatingText
                rottenTomatoesText
                dateText
                primaryCrewText
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }

    private var posterPreviewOverlay: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.72)
                    .ignoresSafeArea()
                    .onTapGesture {
                        isPosterPreviewPresented = false
                    }
                
                posterPreviewImage(maxSize: proxy.size)
                    .onTapGesture { }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func posterPreviewImage(maxSize: CGSize) -> some View {
        let width = min(maxSize.width * 0.86, maxSize.height * 0.82 * 2 / 3)
        let height = width * 1.5
        
        return AsyncImage(url: item.posterURL?.refreshedImageURL(token: imageRefreshToken)) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
            default:
                ProgressView()
                    .tint(.white)
            }
        }
            .frame(width: width, height: height)
            .background(.black.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.38), radius: 28, x: 0, y: 18)
    }
    
    private var titleText: some View {
        Text(item.title)
            .font(.title2.bold())
            .foregroundStyle(.primary)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
    }
    
    private var metadataText: some View {
        Text(detailMetadataLine)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
    
    private var ageRatingText: some View {
        Text("Age rating: \(detail?.ageRating ?? "Not rated")")
            .font(.caption.bold())
            .foregroundStyle(.secondary)
    }

    @ViewBuilder private var rottenTomatoesText: some View {
        if let rottenTomatoesText = externalRatings?.rottenTomatoesDisplayText {
            Text(rottenTomatoesText)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
        }
    }
    
    private var dateText: some View {
        Text(item.kind == .tv ? "Aired: \(detail?.yearRangeText ?? item.releaseYearText)" : "Date: \(item.releaseDate ?? "Unknown")")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    
    @ViewBuilder private var primaryCrewText: some View {
        if let person = detail?.director ?? detail?.creator {
            Button {
                model.selectedPerson = person
            } label: {
                Text("\(item.kind == .tv ? "Creator" : "Director"): \(person.name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        } else {
            Text("\(item.kind == .tv ? "Creator" : "Director"): Unknown")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    @ViewBuilder private var providerAvailabilityNote: some View {
        switch providerAvailability {
        case .unavailable:
            Text("Not available on any of your streaming services. You can update your services in Content Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .paidOnly:
            Text("Only available to rent or buy on your services. You can update your services in Content Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .available, .none:
            EmptyView()
        }
    }

    @ViewBuilder private var detailButtons: some View {
        if showingFriendRating, let friend = model.friendDetailContext {
            let friendWatched = friend.watchedItems.contains { $0.key == item.key }
            let friendSaved = friend.watchlistItems.contains { $0.key == item.key }
            let friendFav = friend.favouriteKeys.contains(item.key.stableID)
            HStack(spacing: 10) {
                DetailRowButton(
                    title: friendSaved ? "Saved" : "Not saved",
                    systemName: friendSaved ? "bookmark.fill" : "bookmark",
                    isEnabled: false,
                    tint: .blue
                ) {}
                if !item.isUpcoming {
                    DetailRowButton(
                        title: friendWatched ? "Watched" : "Not watched",
                        systemName: friendWatched ? "checkmark.circle.fill" : "checkmark.circle",
                        isEnabled: false,
                        tint: .blue
                    ) {}
                    DetailRowButton(
                        title: "Favourite",
                        systemName: friendFav ? "star.fill" : "star",
                        isEnabled: false,
                        tint: .blue
                    ) {}
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
        } else {
            HStack(spacing: 10) {
                DetailRowButton(
                    title: model.library.isInWatchlist(item.key) ? "Saved" : "Save",
                    systemName: model.library.isInWatchlist(item.key) ? "bookmark.fill" : "bookmark"
                ) {
                    model.toggleWatchlist(item)
                }
                if item.isUpcoming {
                    DetailRowButton(
                        title: model.hasCalendarEvent(for: item) ? "In Calendar" : "Calendar",
                        systemName: model.hasCalendarEvent(for: item) ? "calendar.badge.checkmark" : "calendar.badge.plus"
                    ) {
                        model.addReleaseToCalendar(item)
                    }
                } else {
                    DetailRowButton(
                        title: "Watched",
                        systemName: model.library.isWatched(item.key) ? "checkmark.circle.fill" : "checkmark.circle"
                    ) {
                        model.toggleWatched(item, showsRatingPrompt: model.friendDetailContext != nil)
                    }
                    DetailRowButton(
                        title: "Favourite",
                        systemName: model.library.isFavourite(item) ? "star.fill" : "star",
                        isEnabled: model.library.isWatched(item.key),
                        tint: model.library.isFavourite(item) ? .yellow : nil
                    ) {
                        model.requestToggleFavourite(item)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
        }
    }
    
    @ViewBuilder private var ratingSection: some View {
        if let friend = model.friendDetailContext {
            HStack(alignment: .center, spacing: 10) {
                if showingFriendRating {
                    if let friendRating = friend.ratings[item.key], friendRating > 0 {
                        StarRatingView(rating: .constant(friendRating), tint: .blue, isReadOnly: true)
                    } else {
                        Text("Not rated")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .frame(height: 44)
                            .liquidGlass(cornerRadius: 22)
                    }
                } else {
                    if model.library.isWatched(item.key) {
                        StarRatingView(rating: Binding(
                            get: { model.library.ratings[item.key] ?? 0 },
                            set: { model.setRating($0, for: item) }
                        ))
                    } else {
                        Text("Not watched")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .frame(height: 44)
                            .liquidGlass(cornerRadius: 22)
                    }
                }
                Spacer()
                let firstName = friend.name.components(separatedBy: " ").first ?? friend.name
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { showingFriendRating.toggle() }
                } label: {
                    Label(showingFriendRating ? "\(firstName)'s" : "Yours",
                          systemImage: showingFriendRating ? "person.fill" : "person")
                        .font(.caption.bold())
                        .foregroundStyle(showingFriendRating ? Color.blue : Color.yellow)
                        .padding(.horizontal, 10)
                        .frame(height: 44)
                        .liquidGlass(cornerRadius: 22)
                }
                .buttonStyle(.plain)
            }
        } else if model.library.isWatched(item.key) {
            HStack(alignment: .center) {
                StarRatingView(rating: Binding(
                    get: { model.library.ratings[item.key] ?? 0 },
                    set: { model.setRating($0, for: item) }
                ))
                Spacer()
                Button {
                    showWatchedDatePopover = true
                } label: {
                    if let date = model.library.watchedDates[item.key] {
                        Label(date.formatted(.dateTime.day().month(.abbreviated).year()), systemImage: "calendar")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    } else {
                        Label("Add date", systemImage: "calendar.badge.plus")
                            .font(.caption.bold())
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showWatchedDatePopover) {
                    WatchedDatePopover(
                        date: Binding(
                            get: { model.library.watchedDates[item.key] ?? .now },
                            set: { model.setWatchedDate($0, for: item) }
                        ),
                        onClear: model.library.watchedDates[item.key] != nil ? {
                            model.clearWatchedDate(for: item)
                            showWatchedDatePopover = false
                        } : nil
                    )
                    .presentationCompactAdaptation(.popover)
                }
            }
        }
    }
    
    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.overview.isEmpty ? "No overview available." : item.overview)
                .font(.body)
                .foregroundStyle(.primary.opacity(0.82))

            ExternalLookupLink(
                searchQuery: item.title,
                imdbURL: mediaIMDbURL,
                accentColor: model.settings.accentColor,
                font: .body
            )
        }
    }

    private var mediaIMDbURL: URL? {
        guard let imdbID = detail?.imdbID?.trimmingCharacters(in: .whitespacesAndNewlines), !imdbID.isEmpty else {
            return nil
        }
        return URL(string: "https://www.imdb.com/title/\(imdbID)/")
    }
    
    private var actionSection: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 10) {
            DetailRowButton(title: "Cast list", systemName: "person.2.fill") {
                showCast.toggle()
            }
            if !showingFriendRating || model.friendDetailContext == nil {
                DetailRowButton(title: "Add to collection", systemName: "folder.badge.plus") {
                    showCollections = true
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var trailerSection: some View {
        if let trailers = detail?.trailers, !trailers.isEmpty {
            TrailersSection(trailers: Array(trailers.prefix(3)))
        }
    }
    
    struct DetailRowButton: View {
        let title: String
        let systemName: String
        var isEnabled = true
        var tint: Color? = nil
        let action: () -> Void

        var body: some View {
            Button {
                if isEnabled { action() }
            } label: {
                Label(title, systemImage: systemName)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                    .foregroundStyle(tint.map { AnyShapeStyle($0) } ?? (isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary.opacity(0.55))))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .liquidGlass(cornerRadius: 22)
                    .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
        }
    }
    
    @ViewBuilder private var castSection: some View {
        if showCast {
            CastCarousel(people: Array((detail?.castAndKeyCrew ?? []).prefix(22)), model: model)
        }
    }
    
    @ViewBuilder private var episodeSection: some View {
        if item.kind == .tv {
            let friendMode: Bool? = (showingFriendRating && model.friendDetailContext != nil)
                ? model.friendDetailContext!.watchedItems.contains { $0.key == item.key }
                : nil
            EpisodeProgressView(show: item, model: model, seasons: detail?.seasons ?? [], isLoading: detail == nil, friendMode: friendMode)
        }
    }
    
    @ViewBuilder private var similarSection: some View {
        if let similar = detail?.similar, !similar.isEmpty {
            MediaSection(title: "Movies and series like this", items: similar, hideWatchedForUpcoming: false, model: model, oneLineOnly: true, openItem: openNestedItem)
        }
    }

    @ViewBuilder private var cinemasSection: some View {
        #if canImport(CoreLocation)
        if item.kind == .movie && UserDefaults.standard.bool(forKey: "Vestigo.showCinemas") {
            CinemasNearYouSection(
                filmTitle: item.title,
                service: cinemaService,
                selectedDate: $cinemaSelectedDate,
                accentColor: model.settings.accentColor
            )
        }
        #endif
    }

    private var providersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Where to watch")
                .sectionTitle()
            providerStatus
            providerRows
        }
    }
    
    @ViewBuilder private var providerStatus: some View {
        if item.isUpcoming {
            StatusBubble(title: "Theatrical status", text: "This release is upcoming. Streaming availability may not exist yet.")
        } else if providers == nil {
            LoadingBubble(title: "Checking availability", text: "Loading \(model.settings.streamingRegion.displayName) streaming options and prices.")
        } else if visibleProviders?.isEmpty != false {
            StatusBubble(title: "No streaming prices found", text: "No \(model.settings.streamingRegion.displayName) provider data with price and quality was returned for this title.")
        }
    }
    
    @ViewBuilder private var providerRows: some View {
        if let visibleProviders, !visibleProviders.isEmpty {
            ForEach(visibleProviders.prefix(12)) { provider in
                ProviderRow(option: provider)
            }
            .allowsHitTesting(!isTMDbFallback)
            .opacity(isTMDbFallback ? 0.45 : 1)
            if isTMDbFallback {
                Text("Availability data from TMDb — no prices or direct links. Watchmode data currently unavailable for this title.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
            }
        }
    }

    @ViewBuilder private var relatedMediaSection: some View {
        if !relatedMediaSections.isEmpty {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(relatedMediaSections) { section in
                    RelatedMediaCarousel(section: section)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var soundtrackSection: some View {
        if item.kind == .movie || item.kind == .tv {
            SoundtrackLinksView(query: soundtrackSearchQuery)
        }
    }

    private var soundtrackSearchQuery: String {
        let year = item.releaseYearText == "TBA" ? "" : " \(item.releaseYearText)"
        return "\(item.title)\(year) soundtrack"
    }
    
    private var detailMetadataLine: String {
        let yearText = item.kind == .tv ? (detail?.yearRangeText ?? item.releaseYearText) : item.releaseYearText
        var parts = [item.kind.displayLabel(runtime: detail?.runtime ?? item.runtime), yearText]
        
        if item.kind == .movie, let runtime = detail?.runtime, runtime > 0 {
            parts.append(formatRuntime(runtime))
        }
        
        if let originalLanguage = item.originalLanguage, !originalLanguage.isEmpty {
            parts.append("Original language: \(originalLanguage.uppercased())")
        }

        let ratingText = model.ratingDisplayText(for: item)
        if !ratingText.isEmpty {
            parts.append(ratingText)
        }
        return parts.joined(separator: " • ")
    }
    
    private func formatRuntime(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        
        if hours > 0, mins > 0 {
            return "\(hours)h \(mins)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(mins)m"
        }
    }
    private func openNestedItem(_ item: MediaItem) {
        selectedNestedItem = item
    }
}

private struct WatchedDatePopover: View {
    @Binding var date: Date
    var onClear: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            DatePicker("Watched on", selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
            if let onClear {
                Divider()
                Button(role: .destructive, action: onClear) {
                    Text("Clear date")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            }
        }
        .frame(width: 320)
    }
}

private struct TrailersSection: View {
    let trailers: [TrailerVideo]
    @State private var currentIndex = 0

    private var currentTrailer: TrailerVideo { trailers[currentIndex] }

    private func navigate(by offset: Int) {
        let next = currentIndex + offset
        guard next >= 0, next < trailers.count else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { currentIndex = next }
    }

    private func handleTrailerError(_ code: Int) {
        guard [100, 101, 150, 152].contains(code), currentIndex < trailers.count - 1 else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { currentIndex += 1 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trailer")
                .sectionTitle()

            if trailers.count > 1 {
                HStack(spacing: 4) {
                    trailerNavButton(direction: -1, visible: currentIndex > 0)
                    styledPlayer
                    trailerNavButton(direction: 1, visible: currentIndex < trailers.count - 1)
                }
                .padding(.horizontal, -14)
                .gesture(
                    DragGesture(minimumDistance: 30)
                        .onEnded { value in
                            if value.translation.width < -50 { navigate(by: 1) }
                            else if value.translation.width > 50 { navigate(by: -1) }
                        }
                )
            } else {
                styledPlayer
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(currentTrailer.displayTitle)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if !currentTrailer.official {
                    Label("Not from official channel — may not be accurate", systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func trailerNavButton(direction: Int, visible: Bool) -> some View {
        Button { navigate(by: direction) } label: {
            Image(systemName: direction < 0 ? "chevron.left" : "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .padding(6)
                .background(.white.opacity(0.12), in: Circle())
        }
        .buttonStyle(.plain)
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)
    }

    private var styledPlayer: some View {
        YouTubeTrailerPlayer(videoKey: currentTrailer.key, title: currentTrailer.displayTitle, onError: handleTrailerError)
            .id(currentTrailer.id)
            .aspectRatio(16 / 9, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
    }
}

#if canImport(WebKit)
#if os(macOS)
struct YouTubeTrailerPlayer: NSViewRepresentable {
    let videoKey: String
    let title: String
    let onError: ((Int) -> Void)?

    func makeCoordinator() -> YouTubeErrorCoordinator { YouTubeErrorCoordinator(onError: onError) }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: webViewConfiguration(coordinator: context.coordinator))
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube-nocookie.com"))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) { }
}
#else
struct YouTubeTrailerPlayer: UIViewRepresentable {
    let videoKey: String
    let title: String
    let onError: ((Int) -> Void)?

    func makeCoordinator() -> YouTubeErrorCoordinator { YouTubeErrorCoordinator(onError: onError) }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: webViewConfiguration(coordinator: context.coordinator))
        webView.backgroundColor = .clear
        webView.isOpaque = false
        webView.scrollView.isScrollEnabled = false
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube-nocookie.com"))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) { }

    static func dismantleUIView(_ webView: WKWebView, coordinator: YouTubeErrorCoordinator) {
        webView.loadHTMLString("", baseURL: nil)
    }
}
#endif

final class YouTubeErrorCoordinator: NSObject, WKScriptMessageHandler {
    let onError: ((Int) -> Void)?
    init(onError: ((Int) -> Void)?) { self.onError = onError }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "ytError", let code = message.body as? Int else { return }
        DispatchQueue.main.async { self.onError?(code) }
    }
}

extension YouTubeTrailerPlayer {
    func webViewConfiguration(coordinator: YouTubeErrorCoordinator) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.userContentController.add(coordinator, name: "ytError")
        #if os(iOS)
        configuration.mediaTypesRequiringUserActionForPlayback = []
        #endif
        return configuration
    }

    var html: String {
        let escapedKey = videoKey
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
        return """
        <!doctype html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
            <style>
                html, body { margin: 0; padding: 0; width: 100%; height: 100%; overflow: hidden; background: #000; }
                iframe { border: 0; width: 100%; height: 100%; }
            </style>
        </head>
        <body>
            <iframe
                src="https://www.youtube-nocookie.com/embed/\(escapedKey)?playsinline=1&rel=0&modestbranding=1&enablejsapi=1"
                allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
                allowfullscreen>
            </iframe>
            <script>
                window.addEventListener('message', function(e) {
                    try {
                        var d = JSON.parse(e.data);
                        if (d.event === 'onError' && d.error != null) {
                            window.webkit.messageHandlers.ytError.postMessage(d.error);
                        }
                    } catch(_) {}
                });
            </script>
        </body>
        </html>
        """
    }
}
#else
struct YouTubeTrailerPlayer: View {
    let videoKey: String
    let title: String
    let onError: ((Int) -> Void)?

    var body: some View {
        StatusBubble(title: "Trailer unavailable", text: "This platform cannot display embedded web video.")
    }
}
#endif

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

struct CastCarousel: View {
    let people: [PersonSummary]
    @ObservedObject var model: VestigoModel
    
    var body: some View {
        content
    }
    
    @ViewBuilder private var content: some View {
        if people.isEmpty {
            StatusBubble(title: "No cast data", text: "TMDb did not return cast information for this title.")
        } else {
            carousel
        }
    }
    
    private var carousel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cast and crew")
                .sectionTitle()
            scrollRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var scrollRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(people, id: \.id) { person in
                    CastPersonButton(person: person, model: model)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .scrollClipDisabled()
        .scrollIndicators(.hidden)
        .scrollViewTouchTuning(axis: .horizontal)
    }
}

struct CastPersonButton: View {
    let person: PersonSummary
    @ObservedObject var model: VestigoModel
    
    var body: some View {
        Button {
            model.selectedPerson = person
        } label: {
            CastPersonCard(person: person)
        }
        .buttonStyle(.plain)
    }
}

struct CastPersonCard: View {
    let person: PersonSummary
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PersonImageView(person: person, width: 84, height: 112)
            
            Text(person.name)
                .font(.caption.bold())
                .lineLimit(1)
                .frame(width: 84, alignment: .leading)
            
            Text(person.role.isEmpty ? "Cast" : person.role)
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(width: 84, alignment: .topLeading)
                .frame(minHeight: 26, alignment: .topLeading)
        }
    }
}

struct PersonDetailView: View {
    let person: PersonSummary
    @ObservedObject var model: VestigoModel
    @State private var selectedCreditItem: MediaItem?
    @State private var knownForSort: PersonKnownForSort = .rating
    @State private var knownForSortDirection: SortDirection = .descending
    @State private var isBiographyExpanded = false
    @State private var creditFilter: PersonCreditFilter = .onScreen

    private var bundle: PersonCreditBundle? { model.personCreditsCache[person.id] }

    private var credits: [MediaItem] {
        switch creditFilter {
        case .onScreen: return bundle?.onScreen ?? []
        case .behindCamera: return bundle?.behindCamera ?? []
        }
    }

    private var sortedKnownForCredits: [MediaItem] {
        let result = credits.sorted { lhs, rhs in
            switch knownForSort {
            case .rating:
                let lhsRating = model.ratingSortValue(for: lhs)
                let rhsRating = model.ratingSortValue(for: rhs)
                if lhsRating != rhsRating {
                    return lhsRating > rhsRating
                }
            case .date:
                let lhsDate = lhs.releaseDateValue ?? .distantPast
                let rhsDate = rhs.releaseDateValue ?? .distantPast
                if lhsDate != rhsDate {
                    return lhsDate > rhsDate
                }
            }
            return (lhs.releaseDateValue ?? .distantPast) > (rhs.releaseDateValue ?? .distantPast)
        }
        return knownForSortDirection == .ascending ? result.reversed() : result
    }

    var body: some View {
        personSheetSurface
            .presentationBackground(.clear)
            .presentationCornerRadius(54)
            .task {
                await model.loadPersonCredits(person)
                if let b = bundle {
                    if b.onScreen.isEmpty && !b.behindCamera.isEmpty {
                        creditFilter = .behindCamera
                    }
                    await model.loadExternalRatings(for: b.all, limit: 80)
                }
            }
            .sheet(item: $selectedCreditItem) { item in
                DetailView(item: item, model: model, allowsPersonSheet: false)
            }
    }
    
    private var personSheetSurface: some View {
        scrollContent
            .safeAreaInset(edge: .top, spacing: 0) {
                Capsule()
                    .fill(.white.opacity(0.46))
                    .frame(width: 48, height: 5)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .background(.clear)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .sheetLiquidGlass(cornerRadius: 54)
            .ignoresSafeArea(edges: .bottom)
    }
    
    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                creditFilterHeader
                SortRow(direction: $knownForSortDirection) {
                    PersonKnownForSortPicker(sort: $knownForSort)
                }
                PersonCreditList(items: sortedKnownForCredits, model: model) { item in
                    selectedCreditItem = item
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 6)
            .padding(.bottom, 110)
        }
        .scrollDismissesKeyboard(.immediately)
        .scrollIndicators(.hidden)
        .scrollViewTouchTuning()
    }

    @ViewBuilder
    private var creditFilterHeader: some View {
        if bundle?.hasBothKinds == true {
            Picker("Credits", selection: $creditFilter) {
                Text("On Screen").tag(PersonCreditFilter.onScreen)
                Text("Behind the Camera").tag(PersonCreditFilter.behindCamera)
            }
            .pickerStyle(.segmented)
        } else {
            Text(creditFilter == .behindCamera ? "Behind the Camera" : "Known for")
                .sectionTitle()
        }
    }
    
    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            PersonImageView(person: person, width: 112, height: 150)
            personText
        }
    }
    
    private var personText: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(person.name)
                .font(.title2.bold())
                .lineLimit(2)
            
            Text(person.role.isEmpty ? "Known for" : person.role)
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            
            if let detail = model.personDetails[person.id] {
                if let metadata = detail.compactMetadataText {
                    Text(metadata)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                let biographyText = isBiographyExpanded ? detail.fullBiography : detail.detailBiography

                if let biography = biographyText {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(biography)
                            .font(.caption)
                            .foregroundStyle(.primary.opacity(0.82))
                            .lineLimit(isBiographyExpanded ? nil : 3)
                            .fixedSize(horizontal: false, vertical: true)

                        if detail.fullBiography != nil {
                            Button(isBiographyExpanded ? "Show less" : "More") {
                                withAnimation(.smooth(duration: 0.2)) {
                                    isBiographyExpanded.toggle()
                                }
                            }
                            .font(.caption.bold())
                            .buttonStyle(.plain)
                            .foregroundStyle(model.settings.accentColor)
                        }

                        ExternalLookupLink(
                            searchQuery: person.name,
                            imdbURL: personIMDbURL(detail: detail),
                            accentColor: model.settings.accentColor,
                            font: .caption
                        )
                    }
                    .padding(.top, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func personIMDbURL(detail: PersonDetail) -> URL? {
        guard let imdbID = detail.imdbID?.trimmingCharacters(in: .whitespacesAndNewlines), !imdbID.isEmpty else {
            return nil
        }
        return URL(string: "https://www.imdb.com/name/\(imdbID)/")
    }
}

struct PersonCreditList: View {
    let items: [MediaItem]
    @ObservedObject var model: VestigoModel
    let openItem: (MediaItem) -> Void
    
    var body: some View {
        MediaList(
            items: items,
            model: model,
            showsRole: true,
            emptyTitle: "No credits found",
            emptyText: "TMDb did not return other movies or series for this person.",
            openItem: openItem
        )
    }
}

struct MediaList: View {
    let items: [MediaItem]
    @ObservedObject var model: VestigoModel
    var showsRole: Bool = false
    var emptyTitle: String = "No results"
    var emptyText: String = "Nothing matched the current filter."
    var openItem: ((MediaItem) -> Void)? = nil
    
    var body: some View {
        if items.isEmpty {
            StatusBubble(title: emptyTitle, text: emptyText)
        } else {
            VStack(spacing: 12) {
                ForEach(items) { item in
                    MediaListRow(item: item, model: model, showsRole: showsRole, openItem: openItem)
                }
            }
        }
    }
}

struct MediaListRow: View {
    let item: MediaItem
    @ObservedObject var model: VestigoModel
    @State private var showCollections = false
    var showsRole: Bool = false
    var openItem: ((MediaItem) -> Void)? = nil
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            posterButton
            textAndActions
            Spacer(minLength: 0)
        }
        .padding(12)
        .liquidGlass(cornerRadius: 22)
        .appScrollTouchSafe()
        .contextMenu {
            MediaItemContextMenuActions(item: item, hideWatched: false, model: model, swipeContext: .none) {
                showCollections = true
            }
        }
        .sheet(isPresented: $showCollections) {
            AddToCollectionSheet(item: item, model: model)
        }
        .task(id: item.key) {
            await model.loadExternalRatings(item)
        }
    }
    
    private var posterButton: some View {
        Button {
            openItemFromList()
        } label: {
            PosterView(item: item, width: 72, height: 104, isFavourite: model.library.isFavourite(item))
        }
        .buttonStyle(.plain)
    }
    
    private var textAndActions: some View {
        VStack(alignment: .leading, spacing: 6) {
            infoButton
            actionButtons
        }
    }
    
    private var infoButton: some View {
        Button {
            openItemFromList()
        } label: {
            infoContent
        }
        .buttonStyle(.plain)
    }
    
    private var infoContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            titleText
            metadataText
            roleText
            overviewText
        }
    }
    
    private var titleText: some View {
        Text(item.title)
            .font(.system(size: 18, weight: .black, design: .rounded))
            .foregroundStyle(.primary)
            .lineLimit(2)
    }
    
    private var metadataText: some View {
        Text(metadataLine)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
    }
    
    @ViewBuilder private var roleText: some View {
        if showsRole, let role = item.creditRole, !role.isEmpty {
            Text("Role: \(role)")
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.78))
                .lineLimit(2)
        }
    }
    
    @ViewBuilder private var overviewText: some View {
        if !item.overview.isEmpty {
            Text(item.overview)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
    
    private var actionButtons: some View {
        HStack(spacing: 7) {
            TileIconButton(systemName: model.library.isInWatchlist(item.key) ? "bookmark.fill" : "bookmark") {
                model.toggleWatchlist(item)
            }
            
            if item.isUpcoming {
                TileIconButton(systemName: model.hasCalendarEvent(for: item) ? "calendar.badge.checkmark" : "calendar.badge.plus") {
                    model.addReleaseToCalendar(item)
                }
            } else {
                TileIconButton(systemName: model.library.isWatched(item.key) ? "checkmark.circle.fill" : "checkmark.circle") {
                    model.toggleWatched(item)
                }
            }
        }
        .padding(.top, 2)
    }
    
    private var metadataLine: String {
        var parts = [item.kind.label, item.releaseDateReadable]
        let ratingText = model.ratingDisplayText(for: item)
        if !ratingText.isEmpty {
            parts.append(ratingText)
        }
        return parts.joined(separator: " • ")
    }
    
    private func openItemFromList() {
        if let openItem {
            openItem(item)
        } else {
            model.selectedItem = item
        }
    }
}

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

struct AddToCollectionSheet: View {
    let item: MediaItem
    @ObservedObject var model: VestigoModel

    private var manualCollections: [MediaCollection] {
        model.library.collections.filter { !$0.isDynamic }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Add to collection")
                    .font(.title2.bold())

                if manualCollections.isEmpty {
                    StatusBubble(
                        title: "No collections yet",
                        text: "Create a collection from the Collections tab first."
                    )
                } else {
                    ForEach(manualCollections) { collection in
                        let alreadyIn = collection.itemKeys.contains(item.key)
                        Button {
                            if alreadyIn { model.removeFromCollection(item, collectionID: collection.id) }
                            else { model.addToCollection(item, collectionID: collection.id) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(collection.name).font(.headline)
                                    Text(alreadyIn ? "Already in collection" : "Tap to add")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: alreadyIn ? "checkmark.circle.fill" : "plus.circle")
                            }
                            .padding(14)
                            .liquidGlass(cornerRadius: 18)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(18)
            .padding(.bottom, 110)
        }
        .scrollClipDisabled()
        .scrollDismissesKeyboard(.immediately)
        .scrollIndicators(.hidden)
        .scrollViewTouchTuning()
        .safeAreaInset(edge: .top, spacing: 0) {
            Capsule()
                .fill(.white.opacity(0.46))
                .frame(width: 48, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background(.clear)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheetLiquidGlass(cornerRadius: 48)
        .ignoresSafeArea(edges: .bottom)
        .presentationBackground(.clear)
        .presentationCornerRadius(54)
    }
}

