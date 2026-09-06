import SwiftUI
import Foundation

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

struct WatchedDatePopover: View {
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
