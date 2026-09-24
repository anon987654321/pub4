# Mobile apps

RAILS stays the product. `RAILS/mobile` supplies the store registry and release
tooling. Native platform source lives separately in `__NATIVE_ANDROID` and
`__NATIVE_IOS`; it does not fork the web application.

The canonical product matrix is `RAILS/mobile/apps.yml`.

Brgen is one Rails application with separately installable vertical products:
Brgen, Radio, Dating, TV, Takeaway, Marketplace, Maps, and Messenger. Amber is
a separate product. Each entry owns one web origin, one Android package name,
and one iOS bundle identifier.

Android uses a Trusted Web Activity generated from the deployed Web App
Manifest. Bubblewrap creates a normal Android project and an App Bundle; the
domain must publish Digital Asset Links for the signed package.
Source: GoogleChromeLabs Bubblewrap documentation.

iOS uses a native application shell around the Rails PWA. The shell must add
real app utility rather than being only a repackaged website. Apple App Review
Guideline 4.2 requires features, content, and UI that elevate an app beyond a
repackaged website.

The Rails backend already exposes PWA manifests and service workers. It now also
serves:

- `/.well-known/assetlinks.json`
- `/.well-known/apple-app-site-association`

Both are generated from the same registry. Signing fingerprints and the Apple
Developer Team ID are environment configuration, never repository secrets.

## Release order

1. Deploy the Rails changes.
2. Validate each web origin as a standalone PWA.
3. Create the Android TWA project from its manifest with Bubblewrap.
4. Create the iOS shell target with its bundle identifier.
5. Register the apps in Google Play Console and App Store Connect.
6. Add the real Android signing fingerprints and Apple Team ID to production.
7. Re-run the domain association and deep-link gates.
8. Test signed Android and iOS builds against the deployed origins before store
   submission.

Do not create eight copies of the Rails frontend. Do not put signing keys,
App Store credentials, or store metadata secrets in this repository.

Apple requires an App Store Connect app record before the first upload; TestFlight
is the normal beta path.
