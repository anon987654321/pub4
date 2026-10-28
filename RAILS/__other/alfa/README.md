# Alfa Bergen — RAILS/\_\_other

Standalone merkevarenettsted (Next.js, statisk eksport). Søstermerket
Sommerseth Eiendom lever i `RAILS/__other/sommerseth/` — begge er bygget på
Bergen-snittet v1 og doktrinen i
`MASTER/docs/visual/bergen_brand_systems.md` (lover: `MASTER/law/brand.rb`,
tokens: `MASTER/data/tokens.yml#brand_systems`).

- Identitet: arkitektonisk minimalisme — Bricolage Grotesque 700 / Geist /
  Geist Mono, papir `#F2F4F6`, blekk `#14212E`, signal (messing) `#A4762F`,
  skarpe hjørner, blåkopp-hårsbredder på sidene.
- Merket: parametrisk (A-scråtak med hvelvdør) — `src/lib/marks.ts`,
  favicons regenereres med `node scripts/gen-marks.mjs` i dev-treet.
- Språk: norsk bokmål (snl.no-orthografi).
- Bevegelse: Lenis + framer-motion (`src/components/motion.tsx`), alt
  respekterer `prefers-reduced-motion`.

## Bygg og drift

```
bun install
bun run build     # → out/ (statisk eksport)
```

`out/` serveres av OpenBSD httpd med relayd-TLS; se `OPENBSD/etc/httpd.conf`
og `RAILS/apps.yml` (`static_exports`). Domene er planlagt, ikke kjøpt:
`alfabergen.no` (Domeneshop, som de øvrige) — legges i
`OPENBSD/data/dns.yml` først når kjøpet er på plass.

Planlagt status: `planned` i apps.yml inntil domene og første deploy er
verifisert — ikke oppgrader statusen uten et kjørt deploy-sjekk.
