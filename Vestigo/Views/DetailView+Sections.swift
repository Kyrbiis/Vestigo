import SwiftUI
import Foundation
#if canImport(CoreLocation)
import CoreLocation
#endif

// MARK: - DetailView section views

extension DetailView {

    // MARK: Header

    var headerSection: some View {
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

    var posterPreviewOverlay: some View {
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

    func posterPreviewImage(maxSize: CGSize) -> some View {
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

    var titleText: some View {
        Text(item.title)
            .font(.title2.bold())
            .foregroundStyle(.primary)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
    }

    var metadataText: some View {
        Text(detailMetadataLine)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    var ageRatingText: some View {
        Text("Age rating: \(detail?.ageRating ?? "Not rated")")
            .font(.caption.bold())
            .foregroundStyle(.secondary)
    }

    @ViewBuilder var rottenTomatoesText: some View {
        if let rottenTomatoesText = externalRatings?.rottenTomatoesDisplayText {
            Text(rottenTomatoesText)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
        }
    }

    var dateText: some View {
        Text(item.kind == .tv ? "Aired: \(detail?.yearRangeText ?? item.releaseYearText)" : "Date: \(item.releaseDate ?? "Unknown")")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder var primaryCrewText: some View {
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

    @ViewBuilder var providerAvailabilityNote: some View {
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

    // MARK: Rating + Buttons

    @ViewBuilder var ratingSection: some View {
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

    @ViewBuilder var detailButtons: some View {
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

    // MARK: Overview + Action

    var overviewSection: some View {
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

    var mediaIMDbURL: URL? {
        guard let imdbID = detail?.imdbID?.trimmingCharacters(in: .whitespacesAndNewlines), !imdbID.isEmpty else {
            return nil
        }
        return URL(string: "https://www.imdb.com/title/\(imdbID)/")
    }

    var actionSection: some View {
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

    // MARK: Cast + Episodes + Similar

    @ViewBuilder var castSection: some View {
        if showCast {
            CastCarousel(people: Array((detail?.castAndKeyCrew ?? []).prefix(22)), model: model)
        }
    }

    @ViewBuilder var episodeSection: some View {
        if item.kind == .tv {
            let friendMode: Bool? = (showingFriendRating && model.friendDetailContext != nil)
                ? model.friendDetailContext!.watchedItems.contains { $0.key == item.key }
                : nil
            EpisodeProgressView(show: item, model: model, seasons: detail?.seasons ?? [], isLoading: detail == nil, friendMode: friendMode)
        }
    }

    @ViewBuilder var similarSection: some View {
        if let similar = detail?.similar, !similar.isEmpty {
            MediaSection(title: "Movies and series like this", items: similar, hideWatchedForUpcoming: false, model: model, oneLineOnly: true, openItem: openNestedItem)
        }
    }

    // MARK: Trailers

    @ViewBuilder var trailerSection: some View {
        if let trailers = detail?.trailers, !trailers.isEmpty {
            TrailersSection(trailers: Array(trailers.prefix(3)))
        }
    }

    // MARK: Providers

    var providersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Where to watch")
                .sectionTitle()
            providerStatus
            providerRows
        }
    }

    @ViewBuilder var providerStatus: some View {
        if item.isUpcoming {
            StatusBubble(title: "Theatrical status", text: "This release is upcoming. Streaming availability may not exist yet.")
        } else if providers == nil {
            LoadingBubble(title: "Checking availability", text: "Loading \(model.settings.streamingRegion.displayName) streaming options and prices.")
        } else if visibleProviders?.isEmpty != false {
            StatusBubble(title: "No streaming prices found", text: "No \(model.settings.streamingRegion.displayName) provider data with price and quality was returned for this title.")
        }
    }

    @ViewBuilder var providerRows: some View {
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

    // MARK: Cinemas

    @ViewBuilder var cinemasSection: some View {
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

    // MARK: Related + Soundtrack

    @ViewBuilder var relatedMediaSection: some View {
        if !relatedMediaSections.isEmpty {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(relatedMediaSections) { section in
                    RelatedMediaCarousel(section: section)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder var soundtrackSection: some View {
        if item.kind == .movie || item.kind == .tv {
            SoundtrackLinksView(query: soundtrackSearchQuery)
        }
    }

    var soundtrackSearchQuery: String {
        let year = item.releaseYearText == "TBA" ? "" : " \(item.releaseYearText)"
        return "\(item.title)\(year) soundtrack"
    }

    // MARK: Helpers

    var detailMetadataLine: String {
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

    func formatRuntime(_ minutes: Int) -> String {
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
}
