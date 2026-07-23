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
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var fallbackText: String?
    @State private var isReviewingAnswers = false
    @State private var isEditingAnswerFromReview = false

    private var steps: [PickForMeStep] {
        PickForMeStep.steps(for: answers)
    }

    init(model: VestigoModel, startingFilter: MediaFilter) {
        self.model = model
        self.startingFilter = startingFilter
        self._answers = State(initialValue: PickForMeAnswers())
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

                        if isReviewingAnswers && !isEditingAnswerFromReview {
                            answerReviewContent
                        } else if results.isEmpty || isEditingAnswerFromReview {
                            questionContent
                        } else {
                            resultContent
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 28)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
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
            }
        }
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
                answers.runtime = nil
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
            if answers.wantsSpeculative {
                answers.dealBreakers.remove(.sciFiFantasy)
            }
            if !answers.shouldAskRealismQuestion {
                answers.realism = nil
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
            if answers.wantsSpeculative {
                answers.dealBreakers.remove(.sciFiFantasy)
            }
            if !answers.shouldAskRealismQuestion {
                answers.realism = nil
            }
            if step >= steps.count {
                step = max(steps.count - 1, 0)
            }
        }
        .onChange(of: answers.genrePreferences) { _, _ in
            if answers.wantsSpeculative {
                answers.dealBreakers.remove(.sciFiFantasy)
            }
        }
        .onChange(of: answers.contentRatings) { _, _ in
            if step >= steps.count {
                step = max(steps.count - 1, 0)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pick for me")
                .font(.largeTitle.bold())

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
        }
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
        case .seriousness:
            singleChoiceList(PickForMeSeriousness.allCases, selection: $answers.seriousness)
        case .realism:
            singleChoiceList(PickForMeRealism.allCases, selection: $answers.realism)
        case .sourceMaterial:
            singleChoiceList(PickForMeSourceMaterial.allCases, selection: $answers.sourceMaterial)
        case .action:
            multiChoiceList(PickForMeActionLevel.allCases, selection: $answers.actionLevels)
        case .engagement:
            singleChoiceList(PickForMeEngagement.allCases, selection: $answers.engagement)
        case .recommendationType:
            singleChoiceList(PickForMeRecommendationType.allCases, selection: $answers.recommendationType)
        case .runtime:
            singleChoiceList(PickForMeRuntime.allCases, selection: $answers.runtime)
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
            case .sciFiFantasy:
                return !answers.wantsSpeculative
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
                }
            }
        }
    }

    private func multiChoiceList<Option: PickForMeOption>(_ options: [Option], selection: Binding<Set<Option>>) -> some View {
        VStack(spacing: 10) {
            ForEach(options) { option in
                PickForMeOptionButton(title: option.title, subtitle: option.subtitle, isSelected: selection.wrappedValue.contains(option)) {
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
        case .seriousness:
            answers.seriousness = nil
        case .realism:
            answers.realism = nil
        case .sourceMaterial:
            answers.sourceMaterial = nil
        case .action:
            answers.actionLevels = []
        case .engagement:
            answers.engagement = nil
        case .recommendationType:
            answers.recommendationType = nil
        case .runtime:
            answers.runtime = nil
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
        case .seriousness:
            return answers.seriousness?.title ?? "Not answered"
        case .realism:
            return answers.realism?.title ?? "Not answered"
        case .sourceMaterial:
            return answers.sourceMaterial?.title ?? "Not answered"
        case .action:
            return optionTitles(answers.actionLevels)
        case .engagement:
            return answers.engagement?.title ?? "Not answered"
        case .recommendationType:
            return answers.recommendationType?.title ?? "Not answered"
        case .runtime:
            return answers.runtime?.title ?? "Not answered"
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
        case .seriousness:
            return answers.seriousness != nil
        case .realism:
            return answers.realism != nil
        case .sourceMaterial:
            return answers.sourceMaterial != nil
        case .action:
            return !answers.actionLevels.isEmpty
        case .engagement:
            return answers.engagement != nil
        case .recommendationType:
            return answers.recommendationType != nil
        case .runtime:
            return answers.runtime != nil
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
