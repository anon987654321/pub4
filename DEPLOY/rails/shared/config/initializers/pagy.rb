# frozen_string_literal: true

# Consolidated Pagy initializer (shared across all apps via deploy).
# See ruby_style.yml → stimulus_reflex_stack + infinite_scroll pattern.
# Recommended pairing for long lists: Pagy + Futurism (julianrubisch / stimulusreflex/futurism)
#   - Use futurize(@collection, partial: "...") with IntersectionObserver sentinel
#   - Or classic pagy_nav for simpler cases; switch to futurism for infinite scroll UX.
#
# Pagy extras loaded here so all apps get consistent defaults + overflow behavior.

require "pagy/extras/overflow"
require "pagy/extras/metadata" # useful for futurism / turbo responses

Pagy::DEFAULT[:items]    = 25
Pagy::DEFAULT[:overflow] = :last_page
Pagy::DEFAULT[:link_extra] = 'data-turbo-prefetch="false" rel="prefetch"'

# For Futurism + Pagy infinite scroll, controllers typically do:
# @pagy, @records = pagy(scope, items: 20)
# Then in view: futurize partial: "shared/record", collection: @records ...
