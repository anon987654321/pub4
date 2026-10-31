# brgen

**A social network with no global timeline, because the city you live in is the only feed that
ever mattered.** brgen is one Rails process that answers to many hosts, and the host you arrive
on decides which city you are in and which part of the network you are using. It is a Rails
8.2.0.alpha app on SQLite behind Falcon, with Hotwire, Solid Queue, Solid Cache and relayd, and
it listens on port 38182. RAILS/brgen/AGENTS.md is the agent map.

## Brand

brgen is the city-first network: one living local identity that spans conversation, commerce,
dating, food, maps, media and messaging. The missing vowel is the brand mechanic. It makes every
city apex recognisable and leaves the place itself in charge. The verticals borrow brgen's
identity and earn a visual dialect of their own only when the surface needs one. Design values
come from MASTER/data/tokens.yml through Master.tokens, and the shared stylesheet is
RAILS/__shared/README.md. The feature matrix is RAILS/apps.yml under brgen; work only the operator
can finish is listed in `MASTER/data/operator_seams.yml`.

## Cities

A city is an apex host, and the apex serves the social feed. The registry in
Brgen::DomainRegistry lists forty-three apexes, each the city's name with a vowel dropped:
brgen.no for Bergen, oshlo.no, lsangeles.com, lndon.uk, chcago.us. The footer links a smaller
public network of eleven, and the registry counts only seven of the forty-three as holding a
certificate on the box, so a link in the footer does not mean a city is served. The registry is
the only list of hosts, and a host that is not in it does not exist. Local requests to 127.0.0.1
or localhost resolve to Bergen.

Tenancy is acts_as_tenant on the city, taken from the Host header, so one deploy holds many
cities that share users and sessions but not content. The apps default to Norwegian. Every city
entry names its own language, but only two translations ship, nb and en, so the Nordic cities
get Norwegian and every other city gets English. brgen.no is nb and lsangeles.com is en-US. A
city that names Italian or Polish is still served in English, because a page with five
translated words reads worse than an honest page in one language.

## Verticals

The host app holds the feed, communities, events, stories, direct messages and moderation. Every
other part of the network is a mountable Rails engine in a directory beside RAILS/brgen, mounted
at the root of a subdomain of the city apex: dating.brgen.no, markedsplass.brgen.no,
tv.brgen.no, maps.brgen.no, radio.brgen.no, messenger.brgen.no. The same word works on every
apex, so dating.oshlo.no and dating.lsangeles.com exist on the same rule.

The engines are brgen_dating, brgen_maps, brgen_marketplace, brgen_messenger, and brgen_radio,
which holds two, tv and playlist. The playlist engine answers on radio.<apex>, and the public
name changed to radio with no alias kept, so playlist.<apex> is gone. The marketplace is the one
subdomain that is localised, because the word is part of the brand in each market: markedsplass
in Norway, marketplace in the United States and Britain, marktplatz in Germany. Food ordering is
the Takeaway engine, nested inside the marketplace engine and served at /food on the marketplace
host. The old takeaway.<apex> host still resolves, as a compatibility mount of the same engine.
Messenger is an engine whose routes are drawn in the host, under messenger.<apex>. ai.brgen.no
is MASTER, a separate application with its own service, and is not a vertical.

Each engine includes Shared::VerticalEngine, which gives it autoload paths, its own migrations,
views and JavaScript, and names its initializers after its namespace. Two details cost a boot
each to find. The Gemfile line for an engine needs require: with the engine's own entry file,
because Bundler would otherwise require the dashed gem name and the engine class would be
undefined when routes are drawn. And the mount in config/routes.rb must sit at the top level
with a constraints: keyword, never inside a constraints block, because a nested mount still
routes but Rails then drops the mounted helper that host code calls, as in tv.channel_url.
Applied migrations stay where they ran, and an engine owns its db/migrate only for new ones. The
shared models, authentication and design system live in the pub4-shared engine, and no vertical
redefines them.

## Product brief preserved from the original Brgen markdowns

The earlier product brief describes Brgen as a city-first social network rather than a collection of unrelated destination sites. The apex feed is the shared local meeting place; commerce, dating, audio and video are ways for the same community to participate. This remains the product direction, while the registry and mounted applications above define what the current code actually serves.

The original vertical briefs add useful intent that is easy to lose in an implementation-only README:

- **Dating** is local by default: help people meet within their own city, make local events part of discovery, and give members meaningful control over profile visibility and privacy. Match suggestions should assist discovery, not replace member choice. Premium filters, boosts and event revenue were proposed business models, not promises that those purchases are currently available.
- **Audio and playlists** are for local musicians, podcasters and residents to publish recordings, music, podcasts and spoken stories, then discover and share work from their city. The original Whyp.it-inspired brief also called for embeddable players, creator analytics, flexible privacy and expiry controls, and ways to support creators. Treat these as product requirements to verify against the playlist engine before describing them as shipped features. The public vertical name is **radio**; playlist subdomain hosts are not supported.
- **Marketplace** combines person-to-person listings with local shops. Discovery should support categories and useful filters, seller identity and reputation, buyer/seller communication, and nearby inventory. The original brief also proposed AI-assisted discovery and a mobile/PWA experience. The implementation details and live capabilities are defined by the Marketplace sections and engine, not by the old brief.
- **Local media and culture** include community video/TV and support for local artists and creators. The earlier umbrella description mentioned a record-label concept; that is product inspiration, not a separately mounted application or a claim that a label workflow is implemented.

The old markdowns also contain obsolete technology and capability claims (including PostgreSQL, generic live-chat/AI-chat integrations, and broad feature-completion language). Do not use those as architecture facts. This app currently uses the stack stated at the top of this README; feature status must be established from the relevant engine, routes, tests and RAILS/apps.yml.

## Marketplace

Every listing in brgen is a Marketplace::Listing, which belongs to a store only optionally. A
listing with a store is a shop's product, and one without is a person selling a chair. The host
app has no listing model. Only the shop half is built out, with seeds, storefront and chrome. A
listing has a kind, goods, job, housing or gig, and only goods require a price.

The marketplace host serves a Google Merchant Center product feed at /merchant-feed.xml. It
lists goods that are publicly visible, priced and photographed, up to ten thousand of them, and
it leaves affiliate inventory out on purpose. The listing pages carry Product structured data,
and the feed and the pages should change together.

Payments come from three providers. Stripe and Vipps webhooks are host routes at
/webhooks/stripe and /webhooks/vipps, and both end in Webhooks::PaymentPaid, which marks the
order paid and queues the Google conversion upload. Dintero lives inside the marketplace engine
so that its callback and its webhook share the engine's subdomain constraints. Dintero is the
source of truth for authorisation, capture and refund, and a browser redirect never settles
money. The checkout adapter stays off until the operator sets DINTERO_CHECKOUT_ENABLED=1, which
should wait until the test account has passed checkout, capture, refund, replay and
payout-destination checks. bin/rails dintero:hooks:create registers the hook subscription.

Solidus is an optional commerce kernel, staged and not live. Its gems enter the Gemfile only
when SOLIDUS_MARKETPLACE=1, and the engine mounts at /solidus under the marketplace hosts only
when the gems have loaded. The install, which creates the spree tables, belongs on a staging
host with more memory, and not on the one-gigabyte box while master, brgen and amber are all
running. Native Marketplace::* remains the public storefront until an explicit cutover, and the
retired solidus_marketplace gem is not to be installed.

## Seeding

Seeds draw curated fictional Bergen content from Brgen::BergenDemoSeeder and localized bulk
content from Brgen::PlausibleContent. Rich synthetic data belongs in development/test or an
explicitly disclosed demonstration deployment; it must not imply a genuine public audience.

In production-like environments, `db:seed` skips synthetic content by default. An explicit demo
seed requires both `BRGEN_DEMO_MODE=1` and `BRGEN_DEMO_NOTICE=1`; the application shows a
persistent, translated site-wide disclosure while both flags remain set. Keep these settings off
the public production service unless the whole deployment is intentionally a disclosed demo.
`brgen:demo_seed` uses the same guard. In development/test, set
`SKIP_BERGEN_DEMO=1` to omit the curated Bergen fixtures while retaining the bulk fixtures.

`bin/rails brgen:demo_audit` reports likely historical seed identities and linked content without
deleting anything. Review the candidates manually before changing existing records: username
and email patterns are clues, not proof. Seed runs no longer invent listing view counts or
playlist play counts.

The image catalog attaches tracked local media and explicitly credited remote sources. Unprocessed
images selected by the curated Bergen seeder pass through `Shared::PostproProcessor` at seed
time. Rows marked `graded: true` are not processed twice. The `random` preset selector is
deterministic per seed key, so repeated seed runs produce repeatable grading.

Do not scrape or bulk-download Unsplash to populate Brgen. Unsplash's license excludes compiling
images to replicate a similar or competing service, and its API requires hotlinking plus attribution.
Brgen is a social platform, so use generated assets, appropriately licensed local photography, or
sources whose licenses permit the particular use. Keep source and photographer credits in the
catalog whenever supplied.

Users in each city get names in that city's
language through Brgen::CityContent.with_faker_locale. Setting Faker::Config.locale alone gives
English, because Faker's data is tagged nb-NO while the app declares only bare locales. The
photographs the seeds attach are described in config/demo_media/README.md.

## Affiliate income

AffiliateProduct is the stored inventory, and the deals sidebar reads that table and does not
call out on every render. TradeDoubler import needs TRADEDOUBLER_TOKEN, which is issued only
after brgen.no is an approved publisher and each advertiser programme has accepted it, so until
then affiliate:import does nothing. affiliate:health reports counts, staleness and token status.
affiliate:seed_placeholders and affiliate:drop_placeholders work offline. A placeholder row
carries placeholder: true, is excluded from the real scope, is labelled in the interface, and is
never payable inventory. To let TradeDoubler verify ownership, the footer shows
TRADEDOUBLER_SITE_ID and SITE_CONTACT_EMAIL when they are set, whether or not the token exists.

Amazon works in two stages. Each storefront needs its own Associates tag, set in
AMAZON_ASSOCIATE_TAG_SE, _NL and _FR, and a tag from one storefront earns nothing on another's
link, so there is no global fallback. AMAZON_MARKET names the default storefront, and Norway,
which has no amazon.no, maps to Germany unless SE is chosen. With tags alone,
affiliate:amazon_seed writes rows for ASINs the operator picks, and they reach the sidebar
through the same Affiliate.deals path as TradeDoubler. The Creators API catalogue import waits
on AMAZON_CREATORS_CLIENT_ID and AMAZON_CREATORS_CLIENT_SECRET, which Amazon issues after ten
qualifying sales in thirty days. affiliate:amazon_status shows what is configured.

Google conversions travel server to server. GoogleEnhancedConversions posts to the Data Manager
API, the supported path since new adopters of the older upload service were blocked in June
2026. It runs only when GOOGLE_ENHANCED_CONVERSIONS=1 and the Ads customer and conversion-action
ids are set. Email and phone are hashed with SHA-256 and never sent raw, the order id is the
dedupe key, and unpaid orders are never uploaded. Consent is sent only when the answer is known,
and never assumed granted.

## IRC bridge

brgen can speak IRC. A pure-Ruby gateway maps the city channels onto the protocol, so someone on
a public IRC network can point a client at brgen and land in the same #brgen room that a phone
browser sees. Messages cross both ways, and the ops and voice modes and the roster map onto MODE
and NAMES. Brgen::Irc has a message parser, a session state machine with no sockets, a bridge to
the models, and a threaded socket server, and bin/irc-gateway boots it. test/lib/irc_test.rb
covers the protocol and the full session flows.

Channels are anonymous by design, so a web viewer sees an IRC poster as an anonymous handle,
while the nick survives on the IRC side. Only the known city channels can be joined, and a
guessed slug returns 403. The gateway binds 127.0.0.1:6667 and starts nothing on its own. To go
public the operator enables irc_gateway in rc.conf.local, using OPENBSD/etc/rc.d/irc_gateway,
and either terminates TLS on 6697 in relayd and forwards to the local port, or opens 6667 in pf
with IRC_HOST set, which is cleartext. DNS for irc.brgen.no is a separate step. The known limits
are real: there is no NickServ or SASL, web messages reach IRC by a two-second poll, direct
messages are not bridged, and each bridged nick leaves a user row that wants a sweep like guest
pruning.

## Account deletion and private messages

Account deletion has a 30-day grace period and is processed by the daily
`UserPurgeJob`. Private profile, identity, social-relationship and notification
records are removed; personal location fields are cleared from retained public
content. Messenger preserves message rows so replies and thread ordering do not
break, but messages authored by the erased account are unsent: text is cleared,
attachments are purged, the erased sender's conversation memberships are removed, and
message-targeted receipts, notifications, activity, reactions, votes and outbound-attribution
rows are removed. The sender's identity and associated activity references are removed as well. The regression tests in
`test/jobs/user_purge_job_test.rb` cover erasure behavior; runtime execution is
required before treating the full erasure path as verified.

## Bringing it up

```zsh
MASTER/bin/operator triangle up brgen
curl -fsS http://127.0.0.1:38182/up
doas zsh RAILS/brgen/brgen.sh
cd RAILS/brgen && bin/rails test
```
