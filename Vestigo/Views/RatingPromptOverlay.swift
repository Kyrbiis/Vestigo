import SwiftUI
import Foundation

struct RatingPromptOverlay: ViewModifier {
    @ObservedObject var model: VestigoModel
    var suppressedItemKey: MediaKey?
    @State private var showDatePicker = false

    func body(content: Content) -> some View {
        ZStack {
            content

            if let item = model.pendingRatingPromptItem, item.key != suppressedItemKey {
                Color.black.opacity(0.32)
                    .ignoresSafeArea()
                    .transition(.opacity)

                VStack(alignment: .leading, spacing: 16) {
                    Text("Rate \(item.title)?")
                        .font(.title3.bold())
                        .foregroundStyle(.primary)

                    Text("This feature can be disabled in Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(alignment: .center, spacing: 12) {
                        StarRatingView(rating: $model.pendingRatingPromptValue)

                        Spacer(minLength: 0)

                        Button {
                            showDatePicker.toggle()
                        } label: {
                            if let date = model.pendingRatingPromptDate {
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
                        .popover(isPresented: $showDatePicker) {
                            VStack(spacing: 0) {
                                DatePicker(
                                    "Watched on",
                                    selection: Binding(
                                        get: { model.pendingRatingPromptDate ?? .now },
                                        set: { model.pendingRatingPromptDate = $0 }
                                    ),
                                    displayedComponents: .date
                                )
                                .datePickerStyle(.graphical)
                                .padding()
                                if model.pendingRatingPromptDate != nil {
                                    Divider()
                                    Button(role: .destructive) {
                                        model.pendingRatingPromptDate = nil
                                        showDatePicker = false
                                    } label: {
                                        Text("Clear date")
                                            .font(.subheadline)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                    }
                                }
                            }
                            .frame(width: 320)
                            .presentationCompactAdaptation(.popover)
                        }

                        if model.pendingRatingPromptDate != nil {
                            Button {
                                model.pendingRatingPromptDate = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button {
                        model.pendingRatingPromptMakeFavourite.toggle()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: model.pendingRatingPromptMakeFavourite ? "star.fill" : "star")
                                .font(.headline.bold())
                                .foregroundStyle(model.pendingRatingPromptMakeFavourite ? .yellow : .primary)

                            Text(model.pendingRatingPromptMakeFavourite ? "Make favourite" : "Also make favourite")
                                .font(.headline.bold())

                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 14)
                        .frame(height: 46)
                        .liquidGlass(cornerRadius: 22)
                        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 12) {
                        Button("Cancel") {
                            model.dismissPendingRatingPrompt()
                        }
                        .buttonStyle(.plain)
                        .font(.headline.bold())
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .liquidGlass(cornerRadius: 22)

                        Button("Confirm") {
                            model.confirmPendingRatingPrompt()
                        }
                        .buttonStyle(.plain)
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(model.settings.accentColor, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                }
                .padding(18)
                .frame(maxWidth: 360, alignment: .leading)
                .liquidGlass(cornerRadius: 30)
                .padding(.horizontal, 22)
                .transition(.scale(scale: 0.96).combined(with: .opacity))
                .zIndex(50)
            }
        }
        .animation(.smooth(duration: 0.22), value: model.pendingRatingPromptItem?.key)
    }
}

extension View {
    func ratingPromptOverlay(model: VestigoModel, suppressedItemKey: MediaKey? = nil) -> some View {
        modifier(RatingPromptOverlay(model: model, suppressedItemKey: suppressedItemKey))
    }
}
