# Sommerseth Eiendom — thor.brgen.no

**Utleie med omsorg — hjem folk trives i, drevet av familien bak,
fra Fyllingsdalen.**

Statisk HTML. Ingen byggetrinn, ingen pakkeadministrator, ingen
node_modules — treet er det som serveres. Familien bak driver
utleie i Fyllingsdalen; favoroppgave, ikke et produkt i stakkmatrisen.

Siden er ett dokument med seksjoner og ankere. Stilarket bærer reset,
bevegelses-CSS og merkevaren (papir, blekk og rav); bevegelseslaget er
vanilje-JS med innganger, ordmasker, parallaks, tellere, magnetiske
knapper og markør. Fontene er Instrument Serif 400 (+kursiv), Geist 400
og Geist Mono 400 — selvhostet latin-subsett med æ, ø og å. Totalt
under 600 kB.

## Merkene

Merkene er regnet ut av konstruksjonsgrammatikken
i `MASTER/data/tokens.yml#tokens.brand_systems` (sol `r=6.5` ved takets
venstre fot, takstigning 25 over halv bredde). Faviconen ligger i
`sommerseth-mark.svg` (Bergen-snittet v1: sol + setertak); fotografiene
ligger under `images/`.

## Bevegelseskontrakten

Alt er progressivt: uten JavaScript, eller med
`prefers-reduced-motion: reduce`, vises siden flat og fullstendig —
ingen skjulte innganger, ingen klippede ord. Lenis og framer-motion er
byttet ut med native `scroll-behavior` og ~140 linjer vanilje-JS
(`assets/motion.js`), med samme timingkurve
`cubic-bezier(0.2, 0.6, 0.2, 1)`.

## Drift

Serveres av OpenBSD httpd fra chroot `/var/www/sommerseth`
(loopback 38191) bak relayd-TLS på `thor.brgen.no` — SAN på
brgen.no-sertifikatet, DNS i `OPENBSD/var/nsd/zones/master/brgen.no.zone`.
Deploy: `zsh OPENBSD/bin/vps-deploy-static sommerseth` kopierer treet
(uten denne filen) til chrooten og verifiserer serving på loopback.
Porter og status registreres i `RAILS/apps.yml#static_exports`;
status der er `planned` inntil første verifiserte deploy — ikke
oppgrader den uten en kjørt sjekk.

## Treet

```
index.html              hele siden — ett dokument, seksjoner med ankere
assets/site.css         reset + bevegelses-CSS + merkevaren (papir/blekk/rav)
assets/motion.js        vanilje-bevegelse: innganger, ordmasker, parallaks,
                        tellere, magnetiske knapper, markør
assets/fonts/           Instrument Serif 400 (+kursiv), Geist 400,
                        Geist Mono 400 — selvhostet latin-subsett (æ ø å)
images/                 fotografiene
sommerseth-mark.svg     favicon (Bergen-snittet v1: sol + setertak)
```
