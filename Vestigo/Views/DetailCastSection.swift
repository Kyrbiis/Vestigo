import SwiftUI
import Foundation

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
