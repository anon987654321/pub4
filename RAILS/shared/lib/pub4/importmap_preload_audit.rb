# frozen_string_literal: true

module Pub4
  # No pin may put a third-party host on the first-paint critical path.
  #
  # `pin` defaults to `preload: true`, and every preloaded pin becomes a
  # `<link rel="modulepreload">` in the head of every page — fetched eagerly
  # whether or not any code on that page imports it. Measured on live brgen.no
  # 2026-08-12: two external hosts preloaded on every request, jsDelivr and
  # ga.jspm.io, one of them for a module (morphdom) that no application code
  # imports directly at all.
  #
  # The morphdom one is why this has to read the *resolved* map rather than
  # grep importmap_baseline.rb. The pin was not ours: the cable_ready gem ships
  # its own config/importmap.rb pinning morphdom to ga.jspm.io, and gem paths
  # are drawn before the app's, so nothing in our source mentioned the host that
  # was on our critical path. A source scan cannot see a dependency's pins. The
  # drawn importmap can.
  #
  # Two separate facts, because they fail differently. An external preload is a
  # render-blocking request to someone else's server on every page. An external
  # pin that is merely lazy costs nothing until something imports it, but it is
  # still a runtime dependency on a third party — worth naming, not worth
  # forbidding, so the allowlist is explicit and short.
  module ImportmapPreloadAudit
    EXTERNAL = %r{\A(?:https?:)?//}

# Pinned to a CDN, deliberately not preloaded, and each one optional at
# runtime — nothing on any page breaks if the host is unreachable:
#
#   web-vitals          sampled at 1%, with a local PerformanceObserver
#                       fallback, so 99 visitors in 100 never fetch it
#   swiper/bundle       imported on demand by @stimulus-components/carousel,
#                       which appears on one surface in the whole family
#
# @tiptap/core and @tiptap/starter-kit were here and are not any more: they
# are vendored to shared/vendor/javascript/tiptap.js by
# shared/script/build_tiptap.sh. The note that stood here reasoned from
# date-fns, whose ESM build cross-references ~200 siblings by relative path
# so no single flattened file can work — Tiptap does not have that shape.
# esbuild resolves the whole ProseMirror tree into one 288KB module, which
# is pinned preload: false and fetched on first focus of a compose box, so
# the bytes are paid by people who write rather than by everyone who reads.
# That mattered more once the editor stopped being a brgen-only feature.
#
# date-fns remains the standing example of a pin that cannot be flattened.
ALLOWED_EXTERNAL_PINS = %w[
  web-vitals swiper/bundle
].freeze

    module_function

    # [[specifier, resolved_url], ...] for every pin that emits a
    # <link rel="modulepreload"> pointing off-site.
    def external_preloads(importmap, resolver:)
      importmap.preloaded_module_packages(resolver:)
               .filter_map { |path, package| [ package.name, path ] if path.to_s.match?(EXTERNAL) }
    end

    # [[specifier, resolved_url], ...] for every pin resolving off-site at all,
    # preloaded or not.
    def external_pins(importmap, resolver:)
      JSON.parse(importmap.to_json(resolver:))
          .fetch("imports", {})
          .filter_map { |name, path| [ name, path ] if path.to_s.match?(EXTERNAL) }
    end

    def unexpected_external_pins(importmap, resolver:)
      external_pins(importmap, resolver:)
        .reject { |name, _path| ALLOWED_EXTERNAL_PINS.include?(name) }
    end
  end
end
