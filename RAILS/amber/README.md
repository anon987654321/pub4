# amber

**A wardrobe that knows what is in it, what you actually wear, and what it is
guessing at.** amber holds garments and outfits, runs the KonMari declutter loop,
keeps a style timeline, and makes recommendations that can say where they came
from. Rails 8.1 on SQLite behind Falcon, with Hotwire, Active Storage and relayd,
on port 61352.

Deploy it with `doas zsh RAILS/amber/amber.sh` and prove it on
`http://127.0.0.1:61352/up`. Check the port and not the site: every deploy of any
app sheds amber, and relayd keeps answering TLS while it is down, so the failure
arrives as `curl 000` rather than a 5xx. `ALLOW_AMBER_DOWN=1` waives that check
in `deploy-smoke.sh` where being down is the policy.

`default_locale` is `:nb`, with `:en` available and a switcher in the footer.
Chrome, empty states and every controller flash go through I18n. The app's own
copy is in `config/locales/nb.yml` and `en.yml` under `flash:`; the sentences the
shared engine owns, `not_authorized` and `rate_limited`, come from
`shared.flash.*`. `raise_on_missing_translations` is on in test, so a key that
does not resolve fails a run instead of rendering a span nobody reads.

### What each claim actually rests on

The declutter loop is complete: a joy score, challenges, last-chance outfits, and
a thirty-day box in `DeclutterHygieneJob`. The photo pipeline is
`WardrobeMediaJob` — variants, portrait polish, colour — and not an ML cut-out.
`RemoveBackgroundJob` and `SegmentGarmentImageJob` are deprecated shells that
remove nothing and segment nothing; they mark an honest status, no-op, and exist
only for queues still in flight. `EmbedGarmentJob` is an alias of
`FingerprintGarmentJob`, and there are no embeddings anywhere: a fingerprint is a
local `zlib` CRC over the image bytes, which finds a re-upload and never a
lookalike. `DuplicateDetector` follows from that — it groups on an exact
`duplicate_key`, so two similar shirts are not duplicates to it.

The intelligence is honest about being heuristic. Real AI runs through OpenRouter
on `google/gemini-2.0-flash-001` when `OPENROUTER_API_KEY` is set, and
deterministic heuristics run otherwise, with the UI saying which one answered.
`TasteRanker` combines declared `StylePreference` rows with joy, wear count,
recency and life phase at fixed weights — a model, not a learned one.
`StyleAssistant` produces the daily look deterministically per user and date,
weather-aware, and persists nothing until you save it. The weather itself is
open-meteo for Bergen alone, its latitude and longitude constants, cached fifteen
minutes with negative caching and bounded at two seconds to connect and three to
read, because it sits in front of the dashboard.

The scores are targets rather than judgements. `WardrobeGap` compares your closet
against fixed essentials counts per category. The sustainability score scales and
caps wear count and adds a bonus for sparking joy; it is not a lifecycle
assessment. Tips come from `WardrobeAnalytics` nudges and from
`ClosetOrganization`'s care, storage, zoning and restraint registers, each naming
the principle it is applying. Style sessions carry a calendar and a status and
nothing more. There are no store feeds at all: amber imports no product feed, and
`ShopTheLook` ranks the affiliate links you added yourself — its remote half
needs `TRADEDOUBLER_TOKEN`, which lives on brgen, and it says so when that half
is dark.

### Guests, and the gate that is not one

`User` carries a `guest` column, so an anonymous visitor gets a soft
`Current.user` and can use the product without signing up.
`allow_unauthenticated_access` is therefore a no-op here, and logs that it is in
development and test; `require_real_user` is the identity gate that means
anything. `Shared::PruneGuestUsersJob` prunes the guest rows nightly.

Two things are fragile. amber shares one 1 GB box with brgen, bsdports and
MASTER, and needs roughly twenty seconds to signal ready — under load Falcon
kills the worker before that window closes, which reads as a broken app and is
not one. And the Litestream replicas are on the same disk, so there is no
off-host copy of the database. That one is tracked, not solved.

`HEIR.md` covers what runs alone, the health checks, the env keys and the honesty
map. `ARCHITECTURE.md` has the components and layers, `DECISIONS.md` the shapes
that look like bugs and are not, and `RAILS/shared/WIRING_NOTES.md` the shared
tokens and concerns. The feature matrix is `RAILS/apps.yml` under `amber`.
