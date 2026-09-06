import SwiftUI
import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - BaseScreen

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

                if !title.isEmpty {
                    HStack(alignment: .center, spacing: 12) {
                        Text(title)
                            .font(.largeTitle.bold())
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        headerAccessory
                    }
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

// MARK: - AppBackground

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
