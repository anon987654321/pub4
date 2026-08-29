# brgen dating

**Matchmaking for a city you already live in.** dating is a mountable Rails engine
served at `dating.<city>` — `dating.brgen.no`, `dating.lsangeles.com` — not a
separate app. `../../ENGINES.md` is the recipe; `../../AGENTS.md` is the topology.

Each user builds a `Profile`, then likes or dislikes others one at a time, with
`home#next` serving the next candidate. A mutual like creates a `Match`. Those
four models — `Profile`, `Like`, `Dislike`, `Match` — take the `dating_` table
prefix from `isolate_namespace Dating`.

Routes are drawn on `Dating::Engine` and mounted under `constraints(subdomain:
DATING_SUBDOMAINS)`. Root is the candidate feed and `GET next` advances it;
`resource :profile` is the user's own card, `likes` and `dislikes` record swipes,
and `matches#index` lists the mutuals.

The engine depends on `pub4-shared` for `User`, authentication, tenancy and the
design system. The host reaches its helpers namespaced, as
`dating.matches_url(…, subdomain: "dating")`.
