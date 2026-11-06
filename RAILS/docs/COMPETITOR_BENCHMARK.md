# Competitor benchmark - RAILS screenshots, November 2026

**The same 36 screenshots committed on 2026-11-05 (78fa005) that
`SCREENSHOT_LAW_ADHERENCE.md` judged against MASTER's Laws are judged here
against each app's named competitor.** The question is no longer "does the
surface keep the house rules" but "does it hold its own against the product a
real user would open side by side with it": reddit and X for the brgen feed,
bol.com and kaufland.de for the marketplace, tinder and happn for dating,
doordash and foodora for takeaway (mrdamascy), and Facebook Messenger, irssi
and discord for the messenger. The yardsticks are the competitors' shipped
2026 surfaces, read from their public product surfaces and release notes, not
from memory of an older web.

Method: rendered evidence first (the screenshot sets), source second (routes,
models, seeds, locales), competitor third. Where a claim about a competitor
rests on a public page, the page is named. Where the capture cannot decide -
lazy-loaded regions, motion - the finding says INCONCLUSIVE, as the
law-adherence audit does.

## The scorecard

| Surface | Competitor yardstick | Holds against it | Falls short of it | Verdict |
|---|---|---|---|---|
| brgen feed | reddit, X | Local identity neither has; calmer paint than both | Comment depth, mod tools (reddit), media density (X) | 3.5/5 |
| brgen_marketplace | bol.com, kaufland.de | Local-only selling, honest utility copy | PDP depth, trust machinery, cart maturity | 3/5 |
| brgen_dating | tinder, happn | "Krysset spor" is happn's concept, local; profile prompts | Re-seeded decks, photo polish, map view | 2.5/5 |
| mrdamascy (takeaway) | doordash, foodora | Best state coverage in the family; Vipps + bokmål fit | Tracking map, group ordering, menu breadth | 4/5 |
| brgen_messenger | Messenger, irssi, discord | Ambient geo rooms neither has; honest empty state | Bare "#" rail, reactions, requests flow | 3/5 |
| amber | (no named competitor) | - | Login wall vs brgen parity - fixed this pass | 2.5/5 |

## brgen feed vs reddit and X

Reddit's feed is a community instrument: join first, then read; the vote rail
is the product's spine, and moderation tooling is half the surface. X is a
follow instrument: reverse-chron and ranked tabs, a reply/repost/quote rail,
and media so dense the text has to fight for it. The brgen screenshot holds a
third position that neither competitor can take: **the city is the tenant**.
The nav carries the verticals (AI, Radio, Markedsplass, Takeaway, Messenger,
Kart, TV) as one local switchboard; the "Nabolag" dropdown scopes the feed to
a neighbourhood; "Lokal aktivitet" pairs marketplace and radio events into one
panel; posts render under anon handles by default. That is a product reddit
and X structurally cannot ship, and it is visible in the chrome without
reading a word.

Against reddit the gap is conversation: the capture shows the vote rail and a
post body, but reddit's collapsed-thread depth and its mod tools have no
answer here yet. Against X the gap is media density: the mediaeggs tab exists,
but the default feed reads text-first where X's wall carries images at every
scroll position. The audit's defects stand and matter more next to these
yardsticks, because both competitors fill their viewport: brgen's desktop
capture shows two posts and then blank ground, which no competitor would
ship, and the seven icon-only taps of the mobile bottom bar sit below
tinder-class labelling discipline. The "Logg inn" pill's trailing arrow is the
same defect the audit named.

## brgen_marketplace vs bol.com and kaufland.de

bol.com is the Dutch benchmark for system-driven retail: a design system
carried across web and app, a product detail page the company calls its
commercial heartbeat, checkout work measured in conversion, and a 2026 brand
push ("Effe bollen") about carefree, trustworthy shopping - plus a DSA
transparency report as the trust instrument of record. kaufland.de competes on
offer density: a red-accented, promotion-led grid where the deal is the
unit. The brgen marketplace hero is, as the audit said, the best pure
hierarchy in the family - category label, two-line display heading, a held
two-sentence promise, price, one action - and its premise ("Ting fra folk som
bor i nærheten. Ingen frakt over hele landet, ingen mellomledd") is a
positioning neither competitor can copy, because both are national
logistics machines.

The shortfalls are the machinery behind the promise. bol's PDP carries
seller ratings, delivery promises and buyer protection; the brgen capture
stops at the hero and a "B" placeholder tile where a product image should be -
the exact missing-asset fallback the audit flagged, and next to bol it reads
as a trust failure, not a stub. The red offer price collides with the shared
`color_danger` (audit defect 3's cousin); on kaufland.de red is a brand
decision with a system behind it, here it is an unexplained state. The cart
exists ("Kurv 0") but the capture cannot show checkout maturity -
INCONCLUSIVE, and the next capture pass should walk a full order.

## brgen_dating vs tinder and happn

Happn's whole concept is the crossed path: profiles of people you actually
passed within a few kilometres, a secret like, a mutual crush, a conversation
(tinder needs no description; the deck and the double opt-in are the genre's
default). The brgen dating surface is remarkable in one respect: **"Krysset
spor" is happn's concept, spelled in bokmål, wired to a real recorder**
(`Dating::PathCrossingRecorder`, location pings, a `path_crossings` index) -
not a label. On local ground brgen is the only one of the three whose
crossed-paths are backed by a city the size of Bergen rather than a metro
region; happn's own recent history (users report the local radius dissolving
into national match pools) is exactly the drift brgen's architecture makes
unnecessary.

The defects are content and trust. The discovery cards under the fold render
Latin filler ("Provident vitae exercitationem..."), which the repo's own
`brgen/db/seeds.rb` calls a scam sign - tinder and happn never show a first
user a filler profile, and neither can brgen after the next seed pass. The
pills read slightly clipped at capture scale (INCONCLUSIVE without
measurement). Verification exists in code (`dating/verifications`) but is
invisible in the capture, and verification is table stakes next to tinder's
photo verification. The nav flip to light chrome (audit note 8) reads as a
different product inside the family shell.

## mrdamascy (takeaway) vs doordash and foodora

Doordash and foodora are logistics brands with menus attached; mrdamascy is a
kitchen with a delivery vertical attached, and the screenshot set proves it:
menu with origin chips and heat dots, item sheet, cart bar, checkout, tracking,
loyalty stamps, offline state ("Du er offline..."), Vipps login mock that says
it is a mock, staff board, courier runs. State coverage per pixel is the
strongest in the family - the audit's 4.5/5 - and against the yardsticks it
keeps a lead neither competitor holds in this market: **Vipps as a first-class
payment and bokmål microcopy that is local, not translated**. doordash in
Norway is an interface translated into Norwegian; mrdamascy is written in it.

The gaps are the logistics layer's depth: neither capture shows a live map
view of the courier (doordash's and foodora's signature surface; the tracking
page here is a state list - INCONCLUSIVE whether a map exists behind it), and
group or scheduled ordering has no surface. The audit's defects also land
harder against professionals: dot-separated meta strings
("Kurv - %{count} - %{total}") read as placeholder work next to doordash's
tokenised order lines, and "Drikkegis" is not bokmål ("drikkepenger") - a
menu word a competitor's copyeditor would catch.

## brgen_messenger vs Messenger, irssi and discord

Three yardsticks, three eras of the same idea: Messenger is the private
thread list with receipts and reactions; discord is channels plus roles plus
presence; irssi is channels, topics and nick lists in a terminal. The brgen
messenger screenshot shows the honest empty state the audit praised - one
truth ("Ingen samtaler ennå"), one verb ("Send en melding for å starte"), one
action - which all three competitors would endorse. The channel concept is
IRC's, and the ambient geo rooms the family ships (the widget joins a ~10 km
grid-cell room, NearbyController) are something none of the three carries:
**location-scoped group chat without signup is the family's own invention**,
and it is the messenger's best card against discord's servers and Messenger's
threads alike.

The defects are the unfinished rails: the left channel rail renders bare "#"
glyphs where discord renders names and presence - the single worst edge in
the set, because discord sets the expectation that a channel list is
legible. The helper line repeats "Logg inn" twice in one sentence, and the
page title sits in a grey slab that reads as a selected row. Message requests
exist (the nearby stranger chat opens as a request), which matches Messenger's
request inbox; reactions on messages are not visible in the capture -
INCONCLUSIVE.

## amber: the parity pass, shipped

Amber has no competitor in the user's list, because its yardstick is internal:
**brgen itself**. The audit scored amber 2.5/5 for dialect drift; the
structural complaint behind this pass was that amber walled itself where brgen
stays open, so "most screenshots from amber are just the login page". This
pass restores the Craigslist shape Shared::Authentication already documents:

- `live_streams#index/#show` open to everyone; scheduling stays an owner's
  tool, so a guest watches and reads but does not broadcast.
- The ambient chat widget renders for everyone, as brgen's does; a guest's
  soft identity carries the messages widget without an account.
- A random pairing (`encounters`) accepts a connection between two strangers,
  guests included; the accepted connection - not the public directory - is
  what lets the thread continue, so the inbox listing never grows by accident.
- Amber borrows brgen's post format and live chat, and both were already
  guest-usable (public feed, anonymous posting via `Shared::AnonymousPost`);
  what was missing was everything around them.

## Chatroulette-type fun, shipped for brgen and amber

Chatroulette's own product definition is one sentence: it "pairs random users
for one-on-one webcam conversations", no sign-up required. The family gets
the honest version of that, on its own machinery:

- **One ask, one stranger, one conversation.** `POST /encounters` either pairs
  with the oldest live wait from someone else or joins the queue; the pairing
  opens a direct conversation (brgen, on the messenger's
  `Conversation.find_or_create_direct`) or a message thread under an accepted
  connection (amber). Both sides asked for a stranger, so the ask is the
  consent - no invitation step, no signup.
- **Guests play.** Soft guests are the identity path, as in the geo rooms;
  the pairing is ephemeral bookkeeping, the conversation is where anything
  said lives.
- **Abuse-shaped.** Rate-limited (10 asks / 5 minutes, the nearby rule), one
  live wait per person, waits expire after 90 seconds instead of pairing
  ghosts, and brgen's block list is honoured on both sides of the pairing.
- **Honest waiting.** The waiting page states one truth ("Leter etter en
  fremmed å prate med …"), refreshes with the shared morph cadence, and walks
  its reader into the thread the moment the pairing lands; a leave button
  closes the wait. Entry is the ambient chat widget's header (brgen) and the
  home surface (amber).
- **Not yet video.** Chatroulette's medium is webcam; this pass ships the
  pairing, the room and the safety rails in text. WebRTC over the existing
  ActionCable is the next increment and is deliberately not half-shipped here
  - a camera that only sometimes connects is a dishonest state, and the Laws
  do not carry those.

## Sources for the competitor side

- happn, "The concept" (crossed paths, secret like, mutual crush):
  support.happn.fr/hc/en-us/articles/15722747928349-The-concept
- Chatroulette's pairing definition: en.wikipedia.org/wiki/Chatroulette;
  "no sign-up required": chatroulette.com
- bol.com's design-system and PDP practice, and the 2026 "Effe bollen" brand
  platform and DSA transparency report: over.bol.com/en/about-bol
- doordash/foodora surface conventions (item sheets, cart bar, courier map)
  read from their shipped consumer apps; no page cited because none of the
  comparison rests on a specific published document.
