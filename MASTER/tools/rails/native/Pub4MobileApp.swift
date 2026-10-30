import SwiftUI
import UIKit
import UserNotifications
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

    // The server needs to know which APNs gateway a token belongs to.
    static var pushEnvironment: String {
        let raw = Bundle.main.object(forInfoDictionaryKey: "APS_ENVIRONMENT") as? String
        return raw == "development" ? "sandbox" : "production"
    }
}

extension Notification.Name {
    static let pub4OpenURL = Notification.Name("pub4.openURL")
    static let pub4PushToken = Notification.Name("pub4.pushToken")
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        NotificationCenter.default.post(name: .pub4PushToken, object: token)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        NSLog("pub4: APNs registration failed: %@", error.localizedDescription)
    }

    // A tapped notification opens its path in the web view, on the app's host only.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let path = response.notification.request.content.userInfo["path"] as? String {
            AppRouter.open(URL(string: path, relativeTo: AppConfiguration.url)?.absoluteURL)
        }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
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
        configuration.userContentController.add(context.coordinator, name: "pub4Push")

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
        private var pushTokenObserver: NSObjectProtocol?

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
            pushTokenObserver = NotificationCenter.default.addObserver(
                forName: .pub4PushToken,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let token = notification.object as? String else { return }
                self?.dispatch("pub4:native-push-token", [
                    "token": token,
                    "environment": AppConfiguration.pushEnvironment,
                ])
            }
        }

        deinit {
            if let openURLObserver { NotificationCenter.default.removeObserver(openURLObserver) }
            if let pushTokenObserver { NotificationCenter.default.removeObserver(pushTokenObserver) }
        }

        // Answers the page as a window CustomEvent; JSONSerialization keeps the
        // detail a JSON literal, never interpolated text.
        private func dispatch(_ name: String, _ detail: [String: String]) {
            guard let data = try? JSONSerialization.data(withJSONObject: detail),
                  let json = String(data: data, encoding: .utf8) else { return }
            webView?.evaluateJavaScript(
                "window.dispatchEvent(new CustomEvent(\"\(name)\", { detail: \(json) }))"
            )
        }

        // status reports the permission state, and registers at once when already
        // allowed so a fresh token reaches the server on every launch; request
        // shows the iOS sheet, and registers if the reader allows.
        private func handlePush(_ action: String?) {
            let center = UNUserNotificationCenter.current()
            switch action {
            case "status":
                center.getNotificationSettings { settings in
                    DispatchQueue.main.async {
                        let status: String
                        switch settings.authorizationStatus {
                        case .notDetermined: status = "notDetermined"
                        case .denied: status = "denied"
                        default: status = "authorized"
                        }
                        self.dispatch("pub4:native-push-status", ["status": status])
                        if status == "authorized" { UIApplication.shared.registerForRemoteNotifications() }
                    }
                }
            case "request":
                center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                    guard granted else { return }
                    DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
                }
            default:
                return
            }
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            if message.name == "pub4Push" {
                handlePush((message.body as? [String: Any])?["action"] as? String)
                return
            }
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
