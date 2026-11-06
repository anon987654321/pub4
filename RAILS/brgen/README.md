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
brgen.no for Bergen, oshlo.no, lsangeles.com, lndon.uk, chcago.us. The public
network has eleven members, while LIVE_DOMAINS records the seven apexes with
verified TLS in the deployment contract. Footer, search palette and mobile city
navigation show only CITY_NETWORK_DOMAINS intersected with LIVE_DOMAINS; the four
pending network domains are omitted until DNS and certificates are ready.
Membership, registry support and live deployment are separate facts. The registry is
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

**Vertical product briefs:** [Dating](../brgen_dating/README.md) ·
[Marketplace](../brgen_marketplace/README.md) ·
[Takeaway / food](../brgen_marketplace/engines/takeaway/README.md) ·
[Radio](../brgen_radio/playlist/README.md) ·
[TV](../brgen_radio/tv/README.md) ·
[Maps](../brgen_maps/README.md) ·
[Messenger](../brgen_messenger/README.md).

These briefs preserve the distinct product promises while treating the active engine,
routes and tests as the authority for what is actually available.

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


## Marketplace integration

The Marketplace engine owns listings, stores, orders and its storefront; the Brgen host owns
city identity and the webhook entry points shared with the other verticals. The host has no
listing model. The engine's product and feature status lives in
[the Marketplace README](../brgen_marketplace/README.md) and `RAILS/apps.yml`.

The host serves `/merchant-feed.xml` with up to 10,000 publicly visible, priced and photographed
goods; affiliate inventory is excluded. Stripe and Vipps enter through host routes at
`/webhooks/stripe` and `/webhooks/vipps`, then settle through the shared payment service.
Google conversion delivery follows the paid-order event. Dintero checkout, webhook verification
and the optional staging-only Solidus kernel are documented with the engine.

## Seeding

Development/test `db:seed` first builds a per-city baseline for every entry in
`Brgen::DomainRegistry::ENTRIES` after the replant wipe. Each city receives its own
admin, users, communities and posts. A curated `CityContent` bank is used when one
exists; other cities fall back to locale-appropriate names and city-named
`PlausibleContent` copy. Non-Bergen Norwegian cities use the neutral `lokalt`
community rather than a Bergen-branded one.

The remaining bulk vertical catalogue is deliberately Bergen-specific: its
addresses, coordinates, dating bios and local fixture copy belong to
`brgen.no`, which the seed now requires explicitly. The curated
`BergenDemoSeeder` remains a separate disclosed-demo path. Rich synthetic data
belongs in development/test or an explicitly disclosed demonstration deployment;
it must not imply a genuine public audience.

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

The gateway is a limited channel bridge, not a general IRC server. It supports
registration (`NICK`/`USER`), `PING`/`PONG`, `JOIN`, `PART`,
channel `PRIVMSG`, `NAMES` and `QUIT`. Unknown channels return 403.
`NAMES` displays the read-only role prefixes supplied by Brgen's roster;
clients cannot change them because `MODE` is not implemented. `CAP` is
ignored: no capabilities are negotiated. Direct messages, NickServ and SASL
are not supported. The focused tests cover this subset, not the full IRC
protocol.

The socket server polls web-side messages every two seconds and relays them to
joined IRC clients. It binds to `127.0.0.1:6667` by default and starts only
when `bin/irc-gateway` is invoked. To expose it, the operator enables
`irc_gateway` in `rc.conf.local` using `OPENBSD/etc/rc.d/irc_gateway`,
then either terminates TLS on 6697 in relayd and forwards to the local port,
or opens 6667 in pf with `IRC_HOST` set (cleartext). DNS for
`irc.brgen.no` is a separate step.

Web viewers see IRC posters as anonymous handles while the IRC-side nick is
retained. Direct messages are not bridged, and each bridged nick leaves a user
row that still needs the same review/pruning discipline as guest identities.
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
