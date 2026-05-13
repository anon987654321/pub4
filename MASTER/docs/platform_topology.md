# Platform Topology

## Primary platform

### brgen.no

Primary runtime surface and application umbrella.

Responsibilities:

- orchestration surface
- runtime observability
- MASTER integration
- authentication/session coordination
- shared search/indexing
- PWA shell
- dashboard and replay UI
- subapp routing
- SEO authority consolidation

Design direction:

- Rails 8
- Hotwire
- Turbo streams
- Stimulus
- pure SCSS
- semantic HTML
- offline-first PWA shell
- runtime-event-driven UI

brgen.no should mimic the interaction model of X/Twitter where useful:

- dense feed-first layout
- persistent left navigation on desktop
- mobile bottom navigation
- sticky composer/search where appropriate
- infinite or cursor-paginated timelines
- inline media/cards
- fast optimistic interactions
- keyboard shortcuts
- minimal modal friction
- profile/community surfaces
- notification and activity streams

But it must not copy X branding, visual chrome, or dark-pattern engagement mechanics.

brgen.no should feel like:

- civic/social operating surface
- fast timeline application
- local/community graph
- observability-aware PWA

Not:

- AI toy
- startup dashboard
- engagement casino
- decorative social clone

## Shared Rails visual baseline

### bsdports.org SCSS baseline

bsdports.org should define the standard SCSS baseline for all Rails apps.

Shared baseline qualities:

- OpenBSD-inspired restraint
- semantic HTML defaults
- typographic rhythm
- low-noise navigation
- minimal chrome
- sparse color
- high contrast
- grepable/printable content
- fast static-first rendering
- responsive without framework dependency

All Rails apps should inherit:

- tokens
- reset/base
- typography
- layout grid
- forms
- buttons
- tables
- flash/status messages
- navigation
- code/log rendering
- accessibility states
- print styles

Application-specific styling should layer above the bsdports baseline.

## Subapps

Subapps should inherit:

- bsdports SCSS baseline
- typography system
- runtime event schema
- PWA shell
- auth/session conventions
- accessibility rules
- SCSS tokens
- observability contracts

But remain operationally separable.

## Separate applications

### bsdports.org

Identity:

- BSD/OpenBSD influenced
- ports/packages/research focus
- operational minimalism
- grepable/searchable information architecture

UI direction:

- terminal-informed
- sparse color
- typography-first
- documentation-heavy
- fast/static-first where possible

bsdports.org is the source of truth for shared SCSS architecture.

### Hjerterom

Identity:

- community-oriented
- Åsane/Bergen context
- calmer and warmer tone than MASTER
- accessibility and mobile-first focus

Should still retain:

- semantic HTML
- restrained design
- bsdports SCSS baseline
- accessibility discipline
- SSR-first rendering
- offline capability where useful

### Amber

Identity:

- experimental/research/runtime sandbox
- lower operational guarantees
- rapid iteration allowed

Rules:

- isolate experiments
- do not leak instability into core runtime
- preserve replay and telemetry discipline
- inherit shared SCSS baseline unless experiment requires isolation

### Blogger aggregate + SEO booster

Identity:

- indexing
- aggregation
- summarization
- SEO reinforcement
- content graph construction

Architecture direction:

- canonical metadata
- structured data/schema.org
- sitemap automation
- RSS/Atom ingestion
- deduplication
- semantic tagging
- replayable ingestion pipeline
- bsdports baseline for rendering and readability

## Shared platform principles

All applications should share:

- semantic HTML
- pure SCSS
- bsdports SCSS baseline
- Hotwire-first interaction
- accessibility-first design
- PWA capability where appropriate
- replayable runtime telemetry
- restrained operational aesthetics
- OpenBSD-inspired clarity

## Shared anti-patterns

Avoid across all apps:

- Tailwind sprawl
- hydration-heavy SPA architecture
- decorative dashboards
- utility-class soup
- fake activity animations
- hidden runtime state
- frontend-derived truth
- excessive JS frameworks
- engagement dark patterns
