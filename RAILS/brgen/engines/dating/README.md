# brgen dating

**Matchmaking for a city you already live in.** dating is a mountable Rails engine
served at `dating.<city>` — `dating.brgen.no`, `dating.lsangeles.com` — not a
separate app. `../../README.md` is the recipe; `../../AGENTS.md` is the topology.

Each user builds a `Profile`, then likes or dislikes others one at a time, with
`home#next` serving the next candidate. A mutual like creates a `Match`. Those
four models — `Profile`, `Like`, `Dislike`, `Match` — take the `dating_` table
prefix from `isolate_namespace Dating`.

Routes are drawn on `Dating::Engine` and mounted under `constraints(subdomain:
DATING_SUBDOMAINS)`. Root is the candidate feed and `GET next` advances it;
`resource :profile` is the user's own card, `likes` and `dislikes` record swipes,
and `matches#index` lists the mutuals.

Making or editing a profile asks for Vipps Login first, because a verified phone
number is what puts a real person behind a face shown to strangers. The gate
fails open. When `VIPPS_CLIENT_ID` is absent the Vipps provider never registers,
the check is skipped, and anyone signed in can put a profile in the deck; a
missing variable should not lock a whole city out of the vertical. Production
must therefore carry the Vipps keys in `/etc/brgen.env`, or dating runs with no
identity check at all.

The engine depends on `pub4-shared` for `User`, authentication, tenancy and the
design system. The host reaches its helpers namespaced, as
`dating.matches_url(…, subdomain: "dating")`.
