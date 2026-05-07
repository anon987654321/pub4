# brgen

### brgen.no, oshlo.no, trndheim.no, stvanger.no, trmso.no, longyearbyn.no, reykjavk.is, kbenhvn.dk, stholm.se, gtebrg.se, mlmoe.se, hlsinki.fi, lndon.uk, cardff.uk, mnchester.uk, brmingham.uk, lverpool.uk, edinbrgh.uk, glasgw.uk, amstrdam.nl, rottrdam.nl, utrcht.nl, brssels.be, zrich.ch, lchtenstein.li, frankfrt.de, wrsawa.pl, gdnsk.pl, brdeaux.fr, mrseille.fr, mlan.it, lsbon.pt, lsangeles.com, newyrk.us, chcago.us, houstn.us, dllas.us, austn.us, prtland.com, mnneapolis.com

Brgen is a hyperlocal social network unique to every major city. One Rails 8 codebase, served per-domain via SNI, with sub-applications for marketplace, dating, music, TV, and street-food takeaway. Monetization: SEO, PPC, affiliate marketing, targeted email.

### Sub-applications

| Namespace | Subdomain | Models |
|---|---|---|
| `Marketplace::` | `markedsplass.brgen.no` (and locale aliases: markadur, marknadsplats, marktplaats, marche, mercato, mercado, markkinapaikka, marketplace) | Category, Listing, Order |
| `Dating::` | `dating.brgen.no` | Profile, Like, Dislike, Match |
| `Playlist::` | `playlist.brgen.no` | Playlist, Track, PlaylistTrack, Listen |
| `Tv::` | `tv.brgen.no` | Channel, Video, Broadcast, Subscription, ViewEvent |
| `Takeaway::` | `takeaway.brgen.no` | Restaurant, MenuItem, Order, OrderItem |

### Stack

Rails 8 · SQLite3 · Solid Queue · Solid Cache · Hotwire (Turbo + Stimulus) · Devise · OmniAuth · Falcon · Active Storage · ImageProcessing · I18n.

### Deploy

```zsh
doas zsh DEPLOY/rails/brgen/brgen.sh
```

Idempotent. Installs gems, migrates, seeds, registers `rc.d/brgen` on the random app port, and adds the relayd backend.

DNS, TLS, HAProxy SNI routing, and per-city domain registration are handled by `DEPLOY/openbsd/openbsd.sh`.
