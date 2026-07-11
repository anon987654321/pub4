import { build } from "esbuild"
import { injectManifest } from "workbox-build"
import { mkdtemp, rm } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join, resolve } from "node:path"

const APPS = ["amber", "brgen", "bsdports", "hjerterom", "mytoonz", "privcam", "pub_attorney"]
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
      globIgnores: ["service-worker.js"],
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
