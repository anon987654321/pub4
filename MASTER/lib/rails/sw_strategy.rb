# frozen_string_literal: true

module Master
  module Rails
    module SwStrategy
      CACHE_FIRST_ONLY_SIGNAL = /caches\.match.*\|\|.*fetch(?!\s*\(request,\s*\{)/m

      module_function

      # Workbox bundles minify class names — detect NetworkFirst by behavior, not string literals.
      def modern_html_caching?(source)
        return true if source.match?(/network.?first|NetworkFirst/i)
        return true if source.match?(/networkTimeoutSeconds/)
        return true if source.match?(/setCatchHandler/)
        return true if source.match?(/mode\s*===?\s*["']navigate["']/) && source.match?(/registerRoute|register_route/i)

        false
      end

      def cache_first_only?(source)
        source.match?(CACHE_FIRST_ONLY_SIGNAL) && !modern_html_caching?(source)
      end
    end
  end
end