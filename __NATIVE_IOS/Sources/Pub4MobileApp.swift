import SwiftUI
import UIKit
import WebKit

@main
struct Pub4MobileApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            WebAppView(url: AppConfiguration.url)
                .ignoresSafeArea(.container, edges: .bottom)
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    AppRouter.open(activity.webpageURL)
                }
        }
    }
}

final class AppConfiguration {
    static var url: URL {
        guard
            let raw = Bundle.main.object(forInfoDictionaryKey: "MOBILE_APP_URL") as? String,
            let url = URL(string: raw),
            url.scheme == "https"
        else {
            preconditionFailure("MOBILE_APP_URL must be an https URL")
        }
        return url
    }
}

enum AppRouter {
    static func open(_ url: URL?) {
        guard let url, let host = url.host?.lowercased(),
              host == AppConfiguration.host else { return }
        NotificationCenter.default.post(
            name: .pub4OpenURL,
            object: url
        )
    }
}

extension AppConfiguration {
    static var host: String {
        url.host!.lowercased()
    }
}

extension Notification.Name {
    static let pub4OpenURL = Notification.Name("pub4.openURL")
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        true
    }
}

struct WebAppView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(context.coordinator, name: "pub4Share")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        context.coordinator.observe(webView)
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard webView.url == nil else { return }
        webView.load(URLRequest(url: url))
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        private var openURLObserver: NSObjectProtocol?

        func observe(_ webView: WKWebView) {
            self.webView = webView
            openURLObserver = NotificationCenter.default.addObserver(
                forName: .pub4OpenURL,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let url = notification.object as? URL else { return }
                self?.webView?.load(URLRequest(url: url))
            }
        }

        deinit {
            if let openURLObserver { NotificationCenter.default.removeObserver(openURLObserver) }
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "pub4Share",
                  let payload = message.body as? [String: Any] else { return }

            let title = payload["title"] as? String ?? ""
            let text = payload["text"] as? String ?? ""
            let url = payload["url"] as? String ?? ""
            let shareItems = [title, text, url].filter { !$0.isEmpty }
            guard !shareItems.isEmpty else { return }

            let controller = UIActivityViewController(
                activityItems: shareItems,
                applicationActivities: nil
            )

            guard let presenter = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow })?.rootViewController else { return }

            var top = presenter
            while let next = top.presentedViewController { top = next }
            if let popover = controller.popoverPresentationController {
                popover.sourceView = top.view
                popover.sourceRect = CGRect(
                    x: top.view.bounds.midX,
                    y: top.view.bounds.maxY - 1,
                    width: 1,
                    height: 1
                )
            }
            top.present(controller, animated: true)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            if url.scheme == "https", url.host?.lowercased() == AppConfiguration.host {
                decisionHandler(.allow)
                return
            }

            UIApplication.shared.open(url)
            decisionHandler(.cancel)
        }
    }
}
