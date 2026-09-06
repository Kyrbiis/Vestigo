import SwiftUI

struct GenreSortPicker: View {
    @Binding var sort: GenreSort
    let onChange: () -> Void

    var body: some View {
        Picker("Sort", selection: $sort) {
            ForEach(GenreSort.allCases) { item in
                Text(item.title).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .liquidGlass(cornerRadius: 18)
        .onChange(of: sort) { _, _ in
            onChange()
        }
    }
}

struct SearchFiltersPanel: View {
    @ObservedObject var model: VestigoModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                    model.searchFiltersExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Label(filterButtonTitle, systemImage: "line.3.horizontal.decrease.circle")
                        .font(.caption.bold())

                    Spacer(minLength: 0)

                    if model.searchFiltersExpanded {
                        Button {
                            model.clearSearchFilters()
                        } label: {
                            Text("Clear all")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                    }

                    Image(systemName: "chevron.down")
                        .font(.caption.bold())
                        .rotationEffect(.degrees(model.searchFiltersExpanded ? 180 : 0))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .frame(height: 34)
            }
            .buttonStyle(.plain)
            .focusable(false)

            if model.searchFiltersExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    runtimeSection
                    ratingSection
                    dateSection
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(3)
        .liquidGlass(cornerRadius: 18)
    }

    private var filterButtonTitle: String {
        let count = model.activeSearchFilterCount
        return count == 0 ? "Filters" : "Filters (\(count))"
    }

    private var runtimeSection: some View {
        SearchFilterDisclosureSection(
            section: .runtime,
            expandedSections: $model.expandedSearchFilterSections,
            summary: runtimeSummary
        ) {
            SearchChipWrap {
                ForEach(SearchRuntimeFilter.allCases) { filter in
                    SearchFilterChip(
                        title: filter.title,
                        isSelected: model.selectedRuntimeFilters.contains(filter)
                    ) {
                        if model.selectedRuntimeFilters.contains(filter) {
                            model.selectedRuntimeFilters.remove(filter)
                        } else {
                            model.selectedRuntimeFilters.insert(filter)
                        }

                        model.refreshRuntimeFilteredSearchIfNeeded()
                    }
                }
            }
        }
    }

    private var ratingSection: some View {
        SearchFilterDisclosureSection(
            section: .rating,
            expandedSections: $model.expandedSearchFilterSections,
            summary: ratingSummary
        ) {
            SearchChipWrap {
                ForEach(SearchRatingFilter.allCases) { filter in
                    SearchFilterChip(
                        title: filter.title,
                        isSelected: model.minimumTMDbRatingFilter == filter
                    ) {
                        if model.minimumTMDbRatingFilter == filter {
                            model.minimumTMDbRatingFilter = nil
                        } else {
                            model.minimumTMDbRatingFilter = filter
                        }
                    }
                }
            }
        }
    }

    private var dateSection: some View {
        SearchFilterDisclosureSection(
            section: .date,
            expandedSections: $model.expandedSearchFilterSections,
            summary: dateSummary
        ) {
            SearchChipWrap {
                ForEach(SearchDateFilter.allCases) { filter in
                    SearchFilterChip(
                        title: filter.title,
                        isSelected: model.selectedDateFilters.contains(filter)
                    ) {
                        if model.selectedDateFilters.contains(filter) {
                            model.selectedDateFilters.remove(filter)
                        } else {
                            model.selectedDateFilters.insert(filter)
                        }
                    }
                }
            }
        }
    }

    private var runtimeSummary: String? {
        guard !model.selectedRuntimeFilters.isEmpty else { return nil }

        return SearchRuntimeFilter.allCases
            .filter { model.selectedRuntimeFilters.contains($0) }
            .map(\.title)
            .joined(separator: ", ")
    }

    private var ratingSummary: String? {
        model.minimumTMDbRatingFilter?.title
    }

    private var dateSummary: String? {
        guard !model.selectedDateFilters.isEmpty else { return nil }

        return SearchDateFilter.allCases
            .filter { model.selectedDateFilters.contains($0) }
            .map(\.title)
            .joined(separator: ", ")
    }
}

struct SearchFilterDisclosureSection<Content: View>: View {
    let section: SearchFilterSection
    @Binding var expandedSections: Set<SearchFilterSection>
    let summary: String?
    @ViewBuilder let content: Content

    private var isExpanded: Bool {
        expandedSections.contains(section)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    if isExpanded {
                        expandedSections.remove(section)
                    } else {
                        expandedSections.insert(section)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(summary == nil ? section.title : "\(section.title) • \(summary!)")
                        .font(.caption.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.down")
                        .font(.caption.bold())
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(.white.opacity(summary == nil ? 0.08 : 0.14), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            }
            .buttonStyle(.plain)
            .focusable(false)

            if isExpanded {
                content
                    .padding(.horizontal, 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(8)
        .liquidGlass(cornerRadius: 22)
    }
}

struct SearchChipWrap<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 8)], alignment: .leading, spacing: 8) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SearchFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(.white.opacity(isSelected ? 0.20 : 0.08), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(isSelected ? 0.24 : 0.10), lineWidth: 1)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}
