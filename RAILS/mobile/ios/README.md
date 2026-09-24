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
to establish the universal-link association. citeturn828476search0turn828476search4
Rails remains responsible for product UI and server state.

Each entry in `RAILS/mobile/apps.yml` gets its own bundle identifier and App
Store record. The shell code should be shared; targets differ only in product
identity, origin, icons, entitlements, and native capabilities.

Before the first upload, create the app record in App Store Connect. TestFlight
is the beta path; the final build is uploaded from Xcode and submitted through
App Store Connect. citeturn829489search2turn829489search7

The Apple association endpoint is populated only after `APPLE_TEAM_ID` is
configured, which keeps deep-link claims honest during development.
