# Alfa Bergen — alfa.brgen.no

Statisk HTML. Ingen byggetrinn, ingen pakkeadministrator, ingen
node_modules — treet er det som serveres. Favoroppgave for familien
bak flyttebyrået (siden 2006), ikke et produkt i stakkmatrisen.

## Treet

```
index.html              hele siden — fire nummererte seksjoner + kontakt
assets/site.css         reset + bevegelses-CSS + merkevaren (kaldt papir/messing)
assets/motion.js        vanilje-bevegelse: innganger, ordmasker, parallaks,
                        marquee, magnetiske knapper, markør
assets/fonts/           Source Sans 3 (variabel), Source Code Pro (variabel)
                        — samme OFL-1.1-sett som RAILS-nettverket, latin-subsett (æ ø å)
images/                 fotografiene
```

Totalt under 1 MB. Ingen logo-doodle: ordmerket er satt i
Source Sans 3, og sidehodet/foten bærer bare tekst.

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
