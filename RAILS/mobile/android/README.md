# Android

Bubblewrap is the build envelope for these PWAs.

For each entry in `RAILS/mobile/apps.yml`:

```sh
npx @bubblewrap/cli init --manifest https://HOST/manifest.json
npx @bubblewrap/cli validate --url=https://HOST/
npx @bubblewrap/cli build
```

Keep `twa-manifest.json` as the Android-side configuration source. Do not
hand-edit generated project files that Bubblewrap regenerates.

The resulting App Bundle is uploaded to Google Play. The signed certificate
fingerprint produced for the release key becomes that app's
`certificate_env` value in the registry; the Rails association endpoint then
publishes the exact package/fingerprint pair.

Source: GoogleChromeLabs Bubblewrap documentation. citeturn284937search0
