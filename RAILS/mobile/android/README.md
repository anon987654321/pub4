# Android

Android uses Bubblewrap Trusted Web Activity projects generated from the deployed
PWA manifest. Bubblewrap creates a normal Android project and can build the
signed App Bundle used for Play submission. It also generates the information
needed for Digital Asset Links. citeturn943574search0

Run:

    ruby RAILS/tools/mobile.rb android brgen
    ruby RAILS/tools/mobile.rb android marketplace

The product matrix is RAILS/mobile/apps.yml. The generator passes each product
manifest URL and a product-specific output directory to Bubblewrap.

Do not hand-edit generated Bubblewrap project files. Bubblewrap documents
twa-manifest.json as the durable input and warns that update regenerates the
project. citeturn943574search2

Google Play now requires new apps and updates submitted from 31 August 2026 to
target Android 16 (API 36) or higher. Verify the generated project targets API
36 before a release build. citeturn293166search0
