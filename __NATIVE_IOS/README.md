# iOS

The iOS side is a native shell, not a second Rails frontend.

The shell loads the configured origin in WKWebView and owns the native boundary:
push registration, share integration, camera/photo access where the product
needs it, deep-link handling, safe-area behavior, and credentials/keychain.
Internal HTTPS navigation is restricted to the registered origin; external links
leave the shell for the system browser.

The target also enables Apple's Associated Domains capability through
`Pub4MobileApp.entitlements`. `MOBILE_APP_HOST` is the same host recorded in the
mobile registry. Apple uses that entitlement together with the site's AASA file
to establish the universal-link association.
Rails remains responsible for product UI and server state.

Each entry in `RAILS/mobile/apps.yml` gets its own bundle identifier and App
Store record. The shell code should be shared; targets differ only in product
identity, origin, icons, entitlements, and native capabilities.

Before the first upload, create the app record in App Store Connect. TestFlight
is the beta path; the final build is uploaded from Xcode and submitted through
App Store Connect.

The Apple association endpoint is populated only after `APPLE_TEAM_ID` is
configured, which keeps deep-link claims honest during development.

## Native shell controller

The shared Stimulus controller exposes one browser-safe boundary. A page can ask
the native shell to share content through the pub4Share message handler; in a
normal browser it falls back to Web Share when available.

Native APIs stay behind capability detection. Rails views and controllers do not
branch on iOS or Android, which keeps the web product identical across browser,
PWA, TWA, and the iOS shell.

The iOS shell owns the native share sheet. Android TWA continues to use the Web
Share API supplied by the browser.

## Project generation

The native source is deliberately not accompanied by a checked-in `.xcodeproj`.
`project.yml` is the source for the Xcode project and XcodeGen generates the
project on demand. XcodeGen supports YAML project specifications, per-target
build settings, configurations, entitlements, and generated schemes.


Generate it with:

    brew install xcodegen
    ruby RAILS/tools/mobile.rb ios
    open __NATIVE_IOS/.build/Pub4Mobile.xcodeproj

The project has one native target and separate configurations/schemes for
Brgen, Radio, Dating, TV, Takeaway, Marketplace, Maps, Messenger, and Amber.
The bundle IDs, origins, and product names mirror the mobile registry.

For a local unsigned simulator build:

    xcodebuild -project __NATIVE_IOS/.build/Pub4Mobile.xcodeproj \
      -scheme Brgen -configuration Brgen \
      -sdk iphonesimulator \
      -destination 'generic/platform=iOS Simulator' \
      CODE_SIGNING_ALLOWED=NO build
