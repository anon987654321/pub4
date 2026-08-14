import { build } from "esbuild"
import { injectManifest } from "workbox-build"
import { mkdtemp, rm } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join, resolve } from "node:path"

// brgen is deliberately absent. It does not build its service worker: after the
// precache manifest broke the PWA on playlist.brgen.no it was replaced by a
// hand-rolled minimal worker, whose header says so and which precaches only
// /offline. Listing it here meant `npm run build:pwa` silently overwrote that
// file with the Workbox bundle it exists to replace — a one-command
// reintroduction of the outage, and the generated_asset gate used to print that
// very command as brgen's remediation. Running this must not undo a decision.
//
// Now that the manifest no longer pins digested URLs (globIgnores below), moving
// brgen back onto the shared worker would give it the offline form queue and
// periodic sync it lost. That is a product change, not a build fix, so it is not
// made here.
const APPS = ["amber", "bsdports"]
const root = resolve(import.meta.dirname, "..")
const source = join(root, "shared", "pwa", "service_worker.js")
const temp = await mkdtemp(join(tmpdir(), "pub4-workbox-"))

try {
  for (const app of APPS) {
    const bundled = join(temp, `${app}.js`)
    const destination = join(root, app, "app", "views", "pwa", "service-worker.js")
    await build({
      entryPoints: [source],
      outfile: bundled,
      bundle: true,
      minify: true,
      format: "iife",
      target: ["chrome96", "firefox102", "safari16"],
      define: { __APP_NAME__: JSON.stringify(app) },
      banner: { js: `/* Workbox 7.4.1 generated for ${app}; npm run build:pwa */` },
    })
    const result = await injectManifest({
      swSrc: bundled,
      swDest: destination,
      globDirectory: join(root, app, "public"),
      globPatterns: ["**/*.{css,js,png,jpg,jpeg,webp,svg,woff,woff2,ico,html}"],
      // assets/ is excluded because precaching content-addressed URLs is a
      // contradiction: the whole point of a digest is that the URL changes with
      // the content, and a precache manifest freezes the URL at build time.
      //
      // `assets:precompile` runs on the deploy host, so whether this glob sees
      // anything depends on whether someone precompiled before running
      // build:pwa — which is why it is intermittent rather than always broken.
      // Reproduced by putting two digested files under amber/public/assets: the
      // manifest went from 17 entries to 19 and pinned both. The next deploy
      // re-digests every one, and `install` then fails with
      // bad-precaching-response against URLs that 404. That broke the PWA on
      // playlist.brgen.no, and brgen's answer was to throw the whole Workbox
      // worker away and hand-roll a minimal one — which also cost it the offline
      // form queue and periodic sync that amber and bsdports still have.
      //
      // Nothing is lost by excluding them: the CacheFirst route already caches
      // assets at runtime, on demand, and a content-addressed URL can never go
      // stale there — a changed asset is simply a different URL. What stays
      // precached is the stable set: icons, fonts, error pages, / and /offline.
      globIgnores: ["service-worker.js", "assets/**"],
      additionalManifestEntries: [
        { url: "/", revision: "shell-v1" },
        { url: "/offline", revision: "offline-v1" },
      ],
      maximumFileSizeToCacheInBytes: 4 * 1024 * 1024,
    })
    console.log(`${app}: ${result.count} precached files, ${result.size} bytes`)
  }
} finally {
  await rm(temp, { recursive: true, force: true })
}
