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

struct PickForMeView: View {
    @ObservedObject var model: VestigoModel
    let startingFilter: MediaFilter
    @Environment(\.dismiss) private var dismiss
    @State private var answers: PickForMeAnswers
    @State private var step = 0
    @State private var results: [MediaItem] = []
    @State private var resultIndex = 0
    @State private var resultDragOffset: CGFloat = 0
    @State private var screenWidth: CGFloat = 393
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var fallbackText: String?
    @State private var isReviewingAnswers = false
    @State private var isEditingAnswerFromReview = false
    @State private var showingInfoSheet = false
    @State private var scrollToBottomToken = UUID()

    private var steps: [PickForMeStep] {
        PickForMeStep.steps(for: answers)
    }

    init(model: VestigoModel, startingFilter: MediaFilter) {
        self.model = model
        self.startingFilter = startingFilter
        if let saved = model.pickForMeSessionAnswers {
            self._answers = State(initialValue: saved)
            self._results = State(initialValue: model.pickForMeSessionResults)
            self._isReviewingAnswers = State(initialValue: true)
        } else {
            self._answers = State(initialValue: PickForMeAnswers())
        }
    }

    var body: some View {
        ZStack {
            AppBackground(settings: model.settings)
                .ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    Color.clear
                        .frame(height: 0)
                        .id("pickForMeTop")

                    VStack(alignment: .leading, spacing: 24) {
                        header
                        mainContent
                    }
                    .padding(16)
                    .padding(.bottom, 28)
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    Color.clear.frame(height: 0).id("pickForMeBottom")
                }
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize, axes: .vertical)
                .onChange(of: step) { _, _ in
                    scrollToTop(with: proxy)
                }
                .onChange(of: resultIndex) { _, _ in
                    scrollToTop(with: proxy)
                }
                .onChange(of: results.isEmpty) { _, _ in
                    scrollToTop(with: proxy)
                }
                .onChange(of: scrollToBottomToken) { _, _ in
                    withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo("pickForMeBottom", anchor: .bottom) }
                }
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 30, coordinateSpace: .global)
                .onChanged { value in
                    guard !results.isEmpty, !isEditingAnswerFromReview, !isReviewingAnswers else { return }
                    guard value.startLocation.x > 50 else { return }
                    let dx = value.translation.width
                    let dy = value.translation.height
                    guard abs(dx) > abs(dy) * 0.7 else { return }
                    resultDragOffset = dx * 0.75
                }
                .onEnded { value in
                    guard !results.isEmpty, !isEditingAnswerFromReview, !isReviewingAnswers else {
                        withAnimation(.spring(response: 0.3)) { resultDragOffset = 0 }
                        return
                    }
                    guard value.startLocation.x > 50 else {
                        withAnimation(.spring(response: 0.3)) { resultDragOffset = 0 }
                        return
                    }
                    let dx = value.translation.width
                    let dy = value.translation.height
                    guard abs(dx) > abs(dy) * 1.5, abs(dx) > 50 else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { resultDragOffset = 0 }
                        return
                    }
                    let goRight = dx > 0
                    let screenWidth = self.screenWidth
                    withAnimation(.easeIn(duration: 0.15)) {
                        resultDragOffset = goRight ? screenWidth : -screenWidth
                    }
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 150_000_000)
                        if goRight { showPreviousResult() } else { showNextResult() }
                        resultDragOffset = goRight ? -screenWidth : screenWidth
                        withAnimation(.easeOut(duration: 0.2)) { resultDragOffset = 0 }
                    }
                }
        )
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { screenWidth = $0 }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    handleToolbarBack()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
            }
        }
        .onChange(of: answers.mediaFormat) { _, _ in
            if answers.isSeriesOnly {
                answers.runtimeRange = .unconstrained
            }

            if step >= steps.count {
                step = max(steps.count - 1, 0)
            }
        }
        .onChange(of: answers.archetypes) { _, newValue in
            answers.secondaryArchetypes.subtract(newValue)
            if newValue.contains(.documentary) {
                answers.dealBreakers.remove(.documentary)
            }
            if newValue.contains(.war) {
                answers.dealBreakers.remove(.war)
            }
            if step >= steps.count {
                step = max(steps.count - 1, 0)
            }
        }
        .onChange(of: answers.secondaryArchetypes) { _, newValue in
            if newValue.contains(.documentary) {
                answers.dealBreakers.remove(.documentary)
            }
            if newValue.contains(.war) {
                answers.dealBreakers.remove(.war)
            }
            if step >= steps.count {
                step = max(steps.count - 1, 0)
            }
        }
        .onChange(of: answers.contentRatings) { _, _ in
            if step >= steps.count {
                step = max(steps.count - 1, 0)
            }
        }
    }

    @ViewBuilder private var mainContent: some View {
        if isReviewingAnswers && !isEditingAnswerFromReview {
            answerReviewContent
        } else if results.isEmpty || isEditingAnswerFromReview {
            questionContent
        } else {
            resultContent
                .offset(x: resultDragOffset)
                .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: resultDragOffset)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Pick for me")
                    .font(.largeTitle.bold())
                Spacer()
                Button {
                    showingInfoSheet = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showingInfoSheet) {
                    PickForMeInfoSheet()
                }
            }

            if isReviewingAnswers && !isEditingAnswerFromReview {
                Text("Review your answers, edit a specific question, or regenerate.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if results.isEmpty || isEditingAnswerFromReview {
                Text("Answer each question. Use no preference when you do not care.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Recommendation \(resultIndex + 1) of \(results.count)")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var questionContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            progressView

            Text(currentStep.title)
                .font(.title2.bold())
                .frame(maxWidth: .infinity, alignment: .leading)

            if let subtitle = currentStep.subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            answerOptions

            if let errorText {
                StatusBubble(title: "Choose an answer", text: errorText)
            }

            HStack(spacing: 10) {
                Button {
                    goBack()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.headline.bold())
                        .frame(width: 104)
                        .frame(height: 52)
                        .contentShape(Rectangle())
                        .liquidGlass(cornerRadius: 26)
                }
                .buttonStyle(.plain)
                .disabled(isLoading || step == 0)
                .opacity(step == 0 ? 0.45 : 1)

                Button {
                    advance()
                } label: {
                    Label(nextButtonTitle, systemImage: nextButtonIcon)
                    .font(.headline.bold())
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .contentShape(Rectangle())
                    .liquidGlass(cornerRadius: 26)
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
                .opacity(isLoading ? 0.55 : 1)
            }

            if isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Finding a good fit...")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                }
            }

            if step == 0 {
                recentSearchesSection
            }
        }
    }

    @ViewBuilder private var recentSearchesSection: some View {
        let recents = model.settings.pickForMeRecentSearches
        if !recents.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Recent searches")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    ForEach(recents) { search in
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                answers = search.answers
                                isReviewingAnswers = true
                            }
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(recentSearchDateLabel(search.date))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                    Text(search.answers.summaryTags.isEmpty ? "No preferences set" : search.answers.summaryTags.joined(separator: ", "))
                                        .font(.caption.bold())
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    if !search.answers.detailTags.isEmpty {
                                        Text(search.answers.detailTags.joined(separator: " · "))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                Image(systemName: "arrow.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .liquidGlass(cornerRadius: 16)
                        }
                        .buttonStyle(.plain)
                        .swipeToDelete(cornerRadius: 16) { model.removePickForMeRecentSearch(search) }
                    }
                }
            }
        }
    }

    private func recentSearchDateLabel(_ date: Date) -> String {
        let cal = Calendar.current
        let time = date.formatted(.dateTime.hour().minute())
        if cal.isDateInToday(date) { return "Today at \(time)" }
        if cal.isDateInYesterday(date) { return "Yesterday at \(time)" }
        return date.formatted(.dateTime.month(.abbreviated).day()) + " at \(time)"
    }

    private var progressView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(step + 1) / \(steps.count)")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.12))
                    Capsule()
                        .fill(model.settings.accentColor)
                        .frame(width: proxy.size.width * CGFloat(step + 1) / CGFloat(steps.count))
                }
            }
            .frame(height: 7)
        }
    }

    private var nextButtonTitle: String {
        if isEditingAnswerFromReview {
            return "Done"
        }

        return step == steps.count - 1 ? "Check Results" : "Next"
    }

    private var nextButtonIcon: String {
        if isEditingAnswerFromReview {
            return "checkmark"
        }

        return step == steps.count - 1 ? "sparkles" : "chevron.right"
    }

    @ViewBuilder private var answerOptions: some View {
        switch currentStep {
        case .format:
            mediaFormatChoiceList(selection: $answers.mediaFormat)
        case .archetype:
            primaryArchetypeChoiceList(selection: $answers.archetypes)
        case .secondaryArchetypes:
            multiChoiceList(secondaryArchetypeOptions, selection: $answers.secondaryArchetypes)
        case .genrePreferences:
            multiChoiceList(PickForMeGenrePreference.allCases, selection: $answers.genrePreferences)
        case .fictionPreference:
            singleChoiceList(PickForMeFictionPreference.allCases, selection: $answers.fictionPreference)
        case .sourceMaterial:
            singleChoiceList(PickForMeSourceMaterial.allCases, selection: $answers.sourceMaterial)
        case .runtime:
            RuntimeRangeSlider(range: $answers.runtimeRange, accentColor: model.settings.accentColor)
        case .releaseAge:
            singleChoiceList(PickForMeReleaseAge.allCases, selection: $answers.releaseAge)
        case .ageRating:
            multiChoiceList(PickForMeContentRating.allCases, selection: $answers.contentRatings)
        case .minimumRating:
            singleChoiceList(PickForMeMinimumRating.allCases, selection: $answers.minimumRating)
        case .dealBreakers:
            multiChoiceList(dealBreakerOptions, selection: $answers.dealBreakers)
        }
    }

    private var resultContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            let item = results[resultIndex]

            if let fallbackText {
                StatusBubble(title: "Not enough data to decide", text: fallbackText)
            }

            HStack(alignment: .top, spacing: 18) {
                Button {
                    model.selectedItem = item
                } label: {
                    PosterView(item: item, width: 164, height: 238, isFavourite: model.library.isFavourite(item))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 10) {
                    Text(item.title)
                        .font(.title2.bold())
                        .lineLimit(3)

                    Text(resultMetadataText(for: item))
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    Text(item.overview.isEmpty ? "No overview is available for this title." : item.overview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(8)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            HStack(spacing: 10) {
                Button {
                    model.selectedItem = item
                } label: {
                    Label("Details", systemImage: "info.circle")
                        .font(.headline.bold())
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .liquidGlass(cornerRadius: 24)
                }
                .buttonStyle(.plain)

                Button {
                    model.toggleWatchlist(item)
                } label: {
                    Image(systemName: model.library.isInWatchlist(item.key) ? "bookmark.fill" : "bookmark")
                        .font(.headline.bold())
                        .frame(width: 54, height: 48)
                        .liquidGlass(cornerRadius: 24)
                }
                .buttonStyle(.plain)

                Button {
                    model.toggleWatched(item)
                } label: {
                    Image(systemName: model.library.isWatched(item.key) ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(.headline.bold())
                        .frame(width: 54, height: 48)
                        .liquidGlass(cornerRadius: 24)
                }
                .buttonStyle(.plain)
                .disabled(item.isUpcoming)
                .opacity(item.isUpcoming ? 0.45 : 1)
            }

            Button {
                toggleNotInterestedForCurrentResult(item)
            } label: {
                Label(
                    model.library.isNotInterested(item.key) ? "Remove not interested" : "Not interested",
                    systemImage: model.library.isNotInterested(item.key) ? "hand.thumbsup" : "hand.thumbsdown"
                )
                .font(.headline.bold())
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .liquidGlass(cornerRadius: 24)
            }
            .buttonStyle(.plain)

            Button(role: model.library.isNeverShowAgain(item.key) ? nil : .destructive) {
                toggleNeverShowAgainForCurrentResult(item)
            } label: {
                Label(
                    model.library.isNeverShowAgain(item.key) ? "Show in recommendations again" : "Never show this again",
                    systemImage: model.library.isNeverShowAgain(item.key) ? "eye" : "eye.slash"
                )
                .font(.headline.bold())
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .liquidGlass(cornerRadius: 24)
            }
            .buttonStyle(.plain)

            Button {
                editAnswers()
            } label: {
                Label("Review answers", systemImage: "list.bullet.rectangle")
                    .font(.headline.bold())
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .liquidGlass(cornerRadius: 24)
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                Button {
                    showPreviousResult()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.headline.bold())
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .liquidGlass(cornerRadius: 24)
                }
                .buttonStyle(.plain)
                .disabled(resultIndex == 0)
                .opacity(resultIndex == 0 ? 0.45 : 1)

                Button {
                    showNextResult()
                } label: {
                    Label(resultIndex == results.count - 1 ? "Retake" : "Next", systemImage: resultIndex == results.count - 1 ? "arrow.counterclockwise" : "chevron.right")
                        .font(.headline.bold())
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .liquidGlass(cornerRadius: 24)
                }
                .buttonStyle(.plain)
            }
        }
        .task(id: results[resultIndex].key) {
            await model.loadDetail(results[resultIndex])
        }
    }

    private var answerReviewContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                startOver()
            } label: {
                Label("Start over", systemImage: "arrow.counterclockwise")
                    .font(.headline.bold())
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .liquidGlass(cornerRadius: 26)
            }
            .buttonStyle(.plain)

            Text("Your answers")
                .font(.title2.bold())
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 10) {
                ForEach(Array(steps.enumerated()), id: \.element) { index, reviewStep in
                    Button {
                        step = index
                        isEditingAnswerFromReview = true
                        errorText = nil
                    } label: {
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(reviewStep.title)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)

                                Text(answerSummary(for: reviewStep))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 13)
                        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                        .liquidGlass(cornerRadius: 24)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                Task { await loadResults() }
            } label: {
                Label("Regenerate", systemImage: "arrow.clockwise")
                    .font(.headline.bold())
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .liquidGlass(cornerRadius: 26)
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            .opacity(isLoading ? 0.55 : 1)

            if isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Finding a good fit...")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                }
            }

            if let errorText {
                StatusBubble(title: "No results", text: errorText)
            }
        }
    }

    private var currentStep: PickForMeStep {
        steps[min(step, max(steps.count - 1, 0))]
    }

    private var secondaryArchetypeOptions: [PickForMeArchetype] {
        PickForMeArchetype.allCases.filter { option in
            option != .surprise && (option == .noPreference || !answers.archetypes.contains(option))
        }
    }

    private var dealBreakerOptions: [PickForMeDealBreaker] {
        PickForMeDealBreaker.allCases.filter { option in
            switch option {
            case .documentary:
                return !answers.wantsDocumentary
            case .war:
                return !answers.wantsWar
            case .longRuntime:
                return !answers.isSeriesOnly
            default:
                return true
            }
        }
    }

    private var hasEnoughDataForSurprise: Bool {
        model.library.watchedItems.count >= 3
    }

    private func scrollToTop(with proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo("pickForMeTop", anchor: .top)
            }
        }
    }

    private func formatChoiceList(selection: Binding<MediaFilter?>) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                PickForMeOptionButton(title: MediaFilter.movie.title, subtitle: nil, isSelected: selection.wrappedValue == .movie) {
                    selection.wrappedValue = selection.wrappedValue == .movie ? nil : .movie
                    pruneAgeRatingsForCurrentFormat()
                    errorText = nil
                }

                PickForMeOptionButton(title: MediaFilter.tv.title, subtitle: nil, isSelected: selection.wrappedValue == .tv) {
                    selection.wrappedValue = selection.wrappedValue == .tv ? nil : .tv
                    pruneAgeRatingsForCurrentFormat()
                    errorText = nil
                }
            }

            PickForMeOptionButton(title: MediaFilter.both.title, subtitle: nil, isSelected: selection.wrappedValue == .both) {
                selection.wrappedValue = selection.wrappedValue == .both ? nil : .both
                pruneAgeRatingsForCurrentFormat()
                errorText = nil
            }
        }
    }

    private func singleChoiceList<Option: PickForMeOption>(_ options: [Option], selection: Binding<Option?>) -> some View {
        VStack(spacing: 10) {
            ForEach(options) { option in
                PickForMeOptionButton(title: option.title, subtitle: option.subtitle, isSelected: selection.wrappedValue == option) {
                    selection.wrappedValue = selection.wrappedValue == option ? nil : option
                    errorText = nil
                    if selection.wrappedValue != nil { scrollToBottomToken = UUID() }
                }
            }
        }
    }

    private func mediaFormatChoiceList(selection: Binding<PickForMeMediaFormat?>) -> some View {
        VStack(spacing: 10) {
            ForEach(PickForMeMediaFormat.allCases.filter { $0 != .both }) { option in
                PickForMeOptionButton(title: option.title, subtitle: option.subtitle, isSelected: selection.wrappedValue == option) {
                    selection.wrappedValue = option
                    errorText = nil
                    scrollToBottomToken = UUID()
                }
            }
        }
    }

    private func primaryArchetypeChoiceList(selection: Binding<Set<PickForMeArchetype>>) -> some View {
        VStack(spacing: 10) {
            ForEach(PickForMeArchetype.allCases.filter { option in
                option != .noPreference && (option != .surprise || hasEnoughDataForSurprise)
            }) { option in
                PickForMeOptionButton(title: option.title, subtitle: option.subtitle, isSelected: selection.wrappedValue.contains(option)) {
                    selection.wrappedValue = [option]
                    answers.secondaryArchetypes.remove(option)
                    errorText = nil
                    scrollToBottomToken = UUID()
                }
            }
        }
    }

    private func multiChoiceList<Option: PickForMeOption>(_ options: [Option], selection: Binding<Set<Option>>, maxCount: Int = .max) -> some View {
        VStack(spacing: 10) {
            ForEach(options) { option in
                let selectedNonAny = selection.wrappedValue.filter { !$0.isAnyOption }
                let atMax = !option.isAnyOption && !selection.wrappedValue.contains(option) && selectedNonAny.count >= maxCount
                PickForMeOptionButton(title: option.title, subtitle: option.subtitle, isSelected: selection.wrappedValue.contains(option)) {
                    guard !atMax else { return }
                    if option.isAnyOption {
                        selection.wrappedValue = [option]
                    } else {
                        selection.wrappedValue = selection.wrappedValue.filter { !$0.isAnyOption }
                        if selection.wrappedValue.contains(option) {
                            selection.wrappedValue.remove(option)
                        } else {
                            selection.wrappedValue.insert(option)
                        }
                    }
                    errorText = nil
                }
                .disabled(atMax)
            }
        }
    }

    private func cappedMultiChoiceList<Option: PickForMeOption>(_ options: [Option], selection: Binding<Set<Option>>, maximumSelectionCount: Int) -> some View {
        VStack(spacing: 10) {
            ForEach(options) { option in
                PickForMeOptionButton(title: option.title, subtitle: option.subtitle, isSelected: selection.wrappedValue.contains(option)) {
                    if option.isAnyOption {
                        selection.wrappedValue = [option]
                    } else {
                        selection.wrappedValue = selection.wrappedValue.filter { !$0.isAnyOption }
                        if selection.wrappedValue.contains(option) {
                            selection.wrappedValue.remove(option)
                        } else if selection.wrappedValue.count < maximumSelectionCount {
                            selection.wrappedValue.insert(option)
                        } else {
                            errorText = "Choose up to \(maximumSelectionCount) options."
                            return
                        }
                    }

                    errorText = nil
                }
            }
        }
    }

    private func advance() {
        guard !isLoading else { return }
        guard currentStepIsAnswered else {
            errorText = "Please choose an answer before continuing."
            return
        }

        if isEditingAnswerFromReview {
            isEditingAnswerFromReview = false
            isReviewingAnswers = true
            errorText = nil
            return
        }

        if step < steps.count - 1 {
            step += 1
        } else {
            Task { await loadResults() }
        }
    }

    private func clearCurrentAnswer() {
        switch currentStep {
        case .format:
            answers.mediaFormat = nil
        case .archetype:
            answers.archetypes = []
            answers.secondaryArchetypes = []
        case .secondaryArchetypes:
            answers.secondaryArchetypes = []
        case .genrePreferences:
            answers.genrePreferences = []
        case .fictionPreference:
            answers.fictionPreference = nil
        case .sourceMaterial:
            answers.sourceMaterial = nil
        case .runtime:
            answers.runtimeRange = .unconstrained
        case .releaseAge:
            answers.releaseAge = nil
        case .ageRating:
            answers.contentRatings = []
        case .minimumRating:
            answers.minimumRating = nil
        case .dealBreakers:
            answers.dealBreakers = []
        }

        errorText = nil
    }

    private func pruneAgeRatingsForCurrentFormat() {
    }

    private func goBack() {
        if isEditingAnswerFromReview {
            isEditingAnswerFromReview = false
            isReviewingAnswers = true
            errorText = nil
            return
        }

        if isReviewingAnswers {
            isReviewingAnswers = false
            errorText = nil
            return
        }

        if !results.isEmpty {
            isReviewingAnswers = true
            isEditingAnswerFromReview = false
        } else if step > 0 {
            step -= 1
        } else {
            dismiss()
        }
    }

    private func handleToolbarBack() {
        if isEditingAnswerFromReview || isReviewingAnswers {
            goBack()
        } else {
            dismiss()
        }
    }

    private func loadResults() async {
        isLoading = true
        errorText = nil
        let shouldUseFallback = answers.meaningfulQuestionCount == 0
        fallbackText = shouldUseFallback ? "Here are some popular movies and shows instead." : nil
        let queryAnswers = shouldUseFallback ? PickForMeAnswers(mediaFormat: answers.mediaFormat) : answers
        let picked = await model.pickForMeRecommendations(for: queryAnswers)
        isLoading = false

        if picked.isEmpty {
            errorText = "Please repeat the quiz and try different answer combinations."
        } else {
            isReviewingAnswers = false
            isEditingAnswerFromReview = false
            results = picked
            resultIndex = 0
            model.pickForMeSessionAnswers = answers
            model.pickForMeSessionResults = picked
            model.savePickForMeRecentSearch(answers)
        }
    }

    private func resultMetadataText(for item: MediaItem) -> String {
        var parts = [item.displayKindLabel, item.releaseDateReadable]

        if let ageRating = model.detailsCache[item.key]?.ageRating,
           !ageRating.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(ageRating)
        }

        let ratingText = model.ratingDisplayText(for: item)
        if !ratingText.isEmpty {
            parts.append(ratingText)
        }
        return parts.joined(separator: " • ")
    }

    private func answerSummary(for reviewStep: PickForMeStep) -> String {
        switch reviewStep {
        case .format:
            return answers.mediaFormat?.title ?? "Not answered"
        case .archetype:
            return optionTitles(answers.archetypes)
        case .secondaryArchetypes:
            return optionTitles(answers.secondaryArchetypes)
        case .genrePreferences:
            return optionTitles(answers.genrePreferences)
        case .fictionPreference:
            return answers.fictionPreference?.title ?? "Not answered"
        case .sourceMaterial:
            return answers.sourceMaterial?.title ?? "Not answered"
        case .runtime:
            return answers.runtimeRange.hasConstraint ? answers.runtimeRange.displayString : "Not answered"
        case .releaseAge:
            return answers.releaseAge?.title ?? "Not answered"
        case .ageRating:
            return optionTitles(answers.contentRatings)
        case .minimumRating:
            return answers.minimumRating?.title ?? "Not answered"
        case .dealBreakers:
            return optionTitles(answers.dealBreakers)
        }
    }

    private func optionTitles<Option: PickForMeOption>(_ options: Set<Option>) -> String {
        guard !options.isEmpty else { return "Not answered" }
        return options
            .map(\.title)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .joined(separator: ", ")
    }

    private func showPreviousResult() {
        guard resultIndex > 0 else { return }
        resultIndex -= 1
    }

    private func showNextResult() {
        if resultIndex < results.count - 1 {
            resultIndex += 1
        } else {
            results = []
            resultIndex = 0
            step = 0
        }
    }

    private func toggleNeverShowAgainForCurrentResult(_ item: MediaItem) {
        let willHide = !model.library.isNeverShowAgain(item.key)
        model.toggleNeverShowAgain(item)

        guard willHide else { return }
        results.removeAll { $0.key == item.key }

        if results.isEmpty {
            editAnswers()
        } else {
            resultIndex = min(resultIndex, results.count - 1)
        }
    }

    private func toggleNotInterestedForCurrentResult(_ item: MediaItem) {
        let willMark = !model.library.isNotInterested(item.key)
        model.toggleNotInterested(item)

        guard willMark else { return }
        results.removeAll { $0.key == item.key }

        if results.isEmpty {
            editAnswers()
        } else {
            resultIndex = min(resultIndex, results.count - 1)
        }
    }

    private func editAnswers() {
        isReviewingAnswers = true
        isEditingAnswerFromReview = false
        fallbackText = nil
        errorText = nil
    }

    private func startOver() {
        model.pickForMeSessionAnswers = nil
        model.pickForMeSessionResults = []
        answers = PickForMeAnswers()
        results = []
        resultIndex = 0
        step = 0
        isReviewingAnswers = false
        isEditingAnswerFromReview = false
        fallbackText = nil
        errorText = nil
    }

    private var currentStepIsAnswered: Bool {
        switch currentStep {
        case .format:
            return answers.mediaFormat != nil
        case .archetype:
            return !answers.archetypes.isEmpty
        case .secondaryArchetypes:
            return !answers.secondaryArchetypes.isEmpty
        case .genrePreferences:
            return !answers.genrePreferences.isEmpty
        case .fictionPreference:
            return answers.fictionPreference != nil
        case .sourceMaterial:
            return answers.sourceMaterial != nil
        case .runtime:
            return true
        case .releaseAge:
            return answers.releaseAge != nil
        case .ageRating:
            return !answers.contentRatings.isEmpty
        case .minimumRating:
            return answers.minimumRating != nil
        case .dealBreakers:
            return !answers.dealBreakers.isEmpty
        }
    }
}

// MARK: - Info Sheet

struct PickForMeInfoSheet: View {
    private struct Tip: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let body: String
    }

    private let tips: [Tip] = [
        Tip(
            icon: "theatermasks",
            title: "Primary mood",
            body: "The most important thing you want to feel. If you have multiple moods in mind, pick the most specific or niche one — it anchors every result. The others can go in secondary."
        ),
        Tip(
            icon: "slider.horizontal.3",
            title: "Secondary moods",
            body: "Additional layers that blend alongside the primary. 1 or 2 gives the most focused results. More secondaries add flexibility rather than restricting — but too many dilutes the signal."
        ),
        Tip(
            icon: "circle.hexagongrid",
            title: "Genre flavor",
            body: "A hard requirement. Every single result must genuinely fit the genre or setting you choose. 1 flavor is ideal — each extra one you add is applied simultaneously, which significantly shrinks the pool."
        ),
        Tip(
            icon: "doc.text",
            title: "Fiction or non-fiction",
            body: "Leave this as no preference unless you specifically care — any non-\"no preference\" answer can be very restrictive. \"Based on a true story\" is broad (historical fiction, biopics, documentaries). \"Non-fiction only\" is documentary-strict and will cut most of the library."
        ),
        Tip(
            icon: "star.leadinghalf.filled",
            title: "Minimum rating",
            body: "7.0+ is the sweet spot for quality without cutting too deep. 7.5+ noticeably reduces results in niche genres like space or historical. 8.0+ will often return fewer than 10 results."
        ),
        Tip(
            icon: "calendar",
            title: "Release window",
            body: "Only set this if you genuinely care about the era. Leaving it as any age includes classics that are often the strongest matches. Many niche genres have their best films pre-2000."
        ),
        Tip(
            icon: "hand.thumbsdown",
            title: "Deal breakers",
            body: "Only add things you truly cannot watch. Each cuts an entire category from every result — use them sparingly. Sci-Fi and Heavy fantasy are useful if you want grounded, real-world stories without speculative elements."
        ),
        Tip(
            icon: "book",
            title: "Adaptations",
            body: "Only set this if you specifically want a book or game adaptation. Leave it as no preference otherwise — it restricts results more than most people expect."
        ),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Getting better results")
                    .font(.title2.bold())

                Text("Genre flavor and deal breakers are hard cuts — every extra one reduces the pool. Mood and secondary are layered — more gives Groq more surface area to match against.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ForEach(tips) { tip in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: tip.icon)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(width: 28, alignment: .center)
                            .padding(.top, 1)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(tip.title)
                                .font(.subheadline.bold())
                            Text(tip.body)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .liquidGlass(cornerRadius: 20)
                }
            }
            .padding(18)
            .padding(.bottom, 110)
        }
        .scrollClipDisabled()
        .scrollIndicators(.hidden)
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

struct PickForMeOptionButton: View {
    let title: String
    let subtitle: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.subheadline.bold())
                        .lineLimit(2)

                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.headline.bold())
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .liquidGlass(cornerRadius: 28)
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(.primary.opacity(isSelected ? 0.45 : 0), lineWidth: 1.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Runtime Range Slider

private struct RuntimeRangeSlider: View {
    @Binding var range: PickForMeRuntimeRange
    let accentColor: Color

    private let steps = PickForMeRuntimeRange.steps
    private let handleSize: CGFloat = 28

    private var leftIndex: Int {
        steps.firstIndex(of: range.minMinutes) ?? 0
    }

    private var rightIndex: Int {
        range.maxMinutes == 0 ? steps.count - 1 : (steps.firstIndex(of: range.maxMinutes) ?? steps.count - 1)
    }

    private func xForIndex(_ index: Int, trackWidth: CGFloat) -> CGFloat {
        guard steps.count > 1 else { return 0 }
        return trackWidth * CGFloat(index) / CGFloat(steps.count - 1)
    }

    private func indexForX(_ x: CGFloat, trackWidth: CGFloat) -> Int {
        guard trackWidth > 0, steps.count > 1 else { return 0 }
        let fraction = max(0, min(1, x / trackWidth))
        return Int((fraction * CGFloat(steps.count - 1)).rounded())
    }

    var body: some View {
        VStack(spacing: 14) {
            GeometryReader { geo in
                let trackWidth = geo.size.width - handleSize

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.15))
                        .frame(height: 5)
                        .padding(.horizontal, handleSize / 2)

                    let lx = xForIndex(leftIndex, trackWidth: trackWidth)
                    let rx = xForIndex(rightIndex, trackWidth: trackWidth)
                    Capsule()
                        .fill(accentColor)
                        .frame(width: max(0, rx - lx), height: 5)
                        .offset(x: lx + handleSize / 2)

                    Circle()
                        .fill(.white)
                        .frame(width: handleSize, height: handleSize)
                        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                        .offset(x: xForIndex(leftIndex, trackWidth: trackWidth))
                        .gesture(
                            DragGesture(coordinateSpace: .named("runtime_slider"))
                                .onChanged { value in
                                    let newIndex = indexForX(value.location.x - handleSize / 2, trackWidth: trackWidth)
                                    let clamped = max(0, min(newIndex, rightIndex))
                                    range = PickForMeRuntimeRange(minMinutes: steps[clamped], maxMinutes: range.maxMinutes)
                                }
                        )

                    Circle()
                        .fill(.white)
                        .frame(width: handleSize, height: handleSize)
                        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                        .offset(x: xForIndex(rightIndex, trackWidth: trackWidth))
                        .gesture(
                            DragGesture(coordinateSpace: .named("runtime_slider"))
                                .onChanged { value in
                                    let newIndex = indexForX(value.location.x - handleSize / 2, trackWidth: trackWidth)
                                    let clamped = max(leftIndex, min(newIndex, steps.count - 1))
                                    let newMax = clamped == steps.count - 1 ? 0 : steps[clamped]
                                    range = PickForMeRuntimeRange(minMinutes: range.minMinutes, maxMinutes: newMax)
                                }
                        )
                }
                .frame(height: handleSize)
                .coordinateSpace(name: "runtime_slider")
            }
            .frame(height: handleSize)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Minimum")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(range.minMinutes > 0 ? PickForMeRuntimeRange.formatMinutes(range.minMinutes) : "Any")
                        .font(.subheadline.bold())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Maximum")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(range.maxMinutes > 0 ? PickForMeRuntimeRange.formatMinutes(range.maxMinutes) : "Any")
                        .font(.subheadline.bold())
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .liquidGlass(cornerRadius: 28)
    }
}
