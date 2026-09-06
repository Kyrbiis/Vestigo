import SwiftUI
import Foundation
#if canImport(WebKit)
import WebKit
#endif

struct TrailersSection: View {
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

// MARK: - YouTube player

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
