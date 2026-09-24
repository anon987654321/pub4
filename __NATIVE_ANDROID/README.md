# Android

Android uses Bubblewrap Trusted Web Activity projects generated from the deployed
PWA manifest. Bubblewrap creates a normal Android project and can build the
signed App Bundle used for Play submission. It also generates the information
needed for Digital Asset Links.

Run:

    ruby RAILS/tools/mobile.rb android brgen
    ruby RAILS/tools/mobile.rb android marketplace

The product matrix is RAILS/mobile/apps.yml. The generator passes each product
manifest URL and a product-specific output directory to Bubblewrap.

Do not hand-edit generated Bubblewrap project files. Bubblewrap documents
twa-manifest.json as the durable input and warns that update regenerates the
project.

Google Play now requires new apps and updates submitted from 31 August 2026 to
target Android 16 (API 36) or higher. Verify the generated project targets API
36 before a release build.

## Release flow

Bubblewrap's `init` is intentionally interactive because its first run confirms
the web manifest and collects signing-key details. The generated Android project
belongs in `__NATIVE_ANDROID/.build/<app>` and is ignored by Git.


Use:

    ruby RAILS/tools/mobile.rb android brgen

Then inspect the generated `twa-manifest.json`, run the Bubblewrap build, and
deploy the resulting Digital Asset Links data to the matching origin. Bubblewrap
documents `build` as producing the Play App Bundle and supports environment
variables for CI signing passwords.

Google Play requires new apps and updates submitted from 31 August 2026 to target
Android 16/API 36 or higher.
