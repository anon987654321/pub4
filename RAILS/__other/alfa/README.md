# Alfa Bergen — alfa.brgen.no

**Én side, null byggetrinn — flyttebyrået som har flyttet Bergen siden 2006,
nå med eget hus for forvaltning.**

Statisk HTML. Ingen byggetrinn, ingen pakkeadministrator, ingen
node_modules — treet er det som serveres. Favoroppgave for familien
bak flyttebyrået (siden 2006), ikke et produkt i stakkmatrisen.

Siden er ett dokument: fire nummererte seksjoner pluss kontakt.
Stilarket bærer reset, bevegelses-CSS og merkevaren (kaldt papir og
messing); bevegelseslaget er vanilje-JS med innganger, ordmasker,
parallaks, marquee, magnetiske knapper og markør. Fontene er
Bricolage Grotesque (variabel 200–800), Geist 400 og Geist Mono 400 —
selvhostet latin-subsett med æ, ø og å. Totalt under 600 kB.

## Merkene

Merkene er regnet ut av konstruksjonsgrammatikken
i `MASTER/data/tokens.yml#tokens.brand_systems` (skråtak stigning 25
over halv bredde 16, dør `r=5.2` — 0,8 × Sommerseths sol). Faviconen
ligger i `alfa-mark.svg` (Bergen-snittet v1: A-scråtak + halvsirkeldør);
fotografiene ligger under `images/`.

## Bevegelseskontrakten

Alt er progressivt: uten JavaScript, eller med
`prefers-reduced-motion: reduce`, vises siden flat og fullstendig —
marqueen står stille, ordene står på plass. Lenis og framer-motion er
byttet ut med native `scroll-behavior` og ~140 linjer vanilje-JS
(`assets/motion.js`), med samme timingkurve
`cubic-bezier(0.2, 0.6, 0.2, 1)`.

## Drift

Serveres av OpenBSD httpd fra chroot `/var/www/alfa`
(loopback 38192) bak relayd-TLS på `alfa.brgen.no` — SAN på
brgen.no-sertifikatet, DNS i `OPENBSD/var/nsd/zones/master/brgen.no.zone`.
Deploy: `zsh OPENBSD/bin/vps-deploy-static alfa` kopierer treet
(uten denne filen) til chrooten og verifiserer serving på loopback.
Porter og status registreres i `RAILS/apps.yml#static_exports`;
status der er `planned` inntil første verifiserte deploy — ikke
oppgrader den uten en kjørt sjekk.

## Treet

```
index.html              hele siden — fire nummererte seksjoner + kontakt
assets/site.css         reset + bevegelses-CSS + merkevaren (kaldt papir/messing)
assets/motion.js        vanilje-bevegelse: innganger, ordmasker, parallaks,
                        marquee, magnetiske knapper, markør
assets/fonts/           Bricolage Grotesque (variabel 200–800), Geist 400,
                        Geist Mono 400 — selvhostet latin-subsett (æ ø å)
images/                 fotografiene
alfa-mark.svg           favicon (Bergen-snittet v1: A-scråtak + halvsirkeldør)
```
