# brgen dating

Matchmaking vertical for brgen, served at `dating.<city>`
(`dating.brgen.no`, `dating.lsangeles.com`). A mountable Rails engine — see
[`../../ENGINES.md`](../../ENGINES.md). Topology: [`../../AGENTS.md`](../../AGENTS.md).

## What it is

Swipe-style dating: each user builds a `Profile`, then likes or dislikes others
one at a time (`home#next` serves the next candidate). A mutual like creates a
`Match`. This is the "matchmaking logic" the original brgen dating subapp
described, now its own engine.

## Models (`dating_*` tables)

`Profile`, `Like`, `Dislike`, `Match`.

## Routes

Drawn on `Dating::Engine`, mounted under `constraints(subdomain: DATING_SUBDOMAINS)`.
Root is the candidate feed; `GET next` advances it; `resource :profile` for the
user's own card; `likes`/`dislikes` record swipes; `matches#index` lists mutuals.

## Boundaries

Depends on `pub4-shared` for `User`, auth, tenancy, and the design system.
`isolate_namespace Dating` gives the `dating_` table prefix; the host reaches its
helpers as `dating.matches_url(…, subdomain: "dating")`.
