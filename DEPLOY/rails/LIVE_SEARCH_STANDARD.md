# Rails Live Search Standard

All Rails apps should provide live search on primary discovery surfaces.

Baseline reference:

https://www.colby.so/posts/live-search-with-rails-and-stimulusreflex

## Principle

Live search is a shared platform affordance, not a one-off page feature.

It should work across:

- Brgen
- markedsplass
- spilleliste
- tv
- takeaway
- blognet
- Foodielicious
- bsdports
- Hjerterom
- Amber examples

## Implementation modes

Preferred where StimulusReflex exists:

- Stimulus controller captures input
- Reflex performs server-side search
- server morphs result frame
- pagination or infinite scroll remains compatible

Fallback where StimulusReflex is absent:

- Stimulus captures input
- Turbo Frame receives search results
- controller renders partial result list
- basic query URL still works without JavaScript

## Required UX states

Every live-search surface must include:

- initial state
- loading state
- empty-query state
- no-results state
- result count
- keyboard-friendly input
- progressive fallback URL

## Required backend behavior

Every live-search endpoint should:

- debounce client input
- sanitize query parameters
- enforce visibility/moderation filters
- scope by product or vertical
- emit search analytics events
- avoid leaking private content

## Shared event

SearchPerformed

Fields:

- actor
- query
- app
- vertical
- result_count
- latency_ms
- filters
- locality

## Required surfaces

Brgen:

- root feed
- posts
- people/profiles
- local discovery

markedsplass:

- listings
- categories
- sellers

spilleliste:

- playlists
- tracks
- collaborators

tv:

- videos
- shows
- channels

takeaway:

- restaurants
- menu items
- cuisines

blognet:

- posts
- authors
- concepts
- tags

Foodielicious:

- recipes
- ingredients
- guides
- collections

bsdports:

- ports
- packages
- maintainers
- categories

Hjerterom:

- resources
- pages
- local content

Amber:

- baseline example search
- reusable demo controller

## Shared partial naming

Use predictable names:

- app/views/shared/_search_form.html.erb
- app/views/shared/_search_results.html.erb
- app/views/shared/_search_empty.html.erb
- app/views/shared/_search_loading.html.erb

## Shared Stimulus naming

Use:

- search_controller.js
- live_search_controller.js

Avoid app-specific JavaScript names unless the behavior is truly app-specific.

## Restore guidance

Old generator search code may be used as reference only.

Do not restore StimulusReflex code blindly into apps that no longer use StimulusReflex.

Port the interaction pattern, not stale implementation details.
