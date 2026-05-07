# frozen_string_literal: true

module Master
  module Scan
    module Rules
      class NPlusOneRule < Rule
        EACH_WITH_ASSOC = /\.\s*(?:each|map|select|filter_map)\s*(?:do\s*\|[^|]+\||\{\s*\|[^|]+\|).*?\.\w+\.\w+/m.freeze
        FIND_IN_LOOP    = /\.\s*(?:each|map)\s*(?:do\s*\|[^|]+\||\{\s*\|[^|]+\|).*?(?:\.find|\.where|\.first)\(/m.freeze

        def initialize
          super
          @id          = "n_plus_one"
          @description = "Likely N+1 query — eager-load with includes/preload"
          @severity    = :warning
          @axiom_tags  = %i[PERFORMANCE]
        end

        def check(code, path:)
          return [] unless rails_app?(path)
          findings = []
          code.each_line.with_index(1) do |line, num|
            next if line.strip.start_with?("#")
            findings << finding(line: num,
              message: "iter accesses associated record — preload/includes the assoc to avoid N+1") if line.match?(EACH_WITH_ASSOC)
            findings << finding(line: num,
              message: "find/where inside iter — move query outside loop or batch with where(id: ids)") if line.match?(FIND_IN_LOOP)
          end
          findings
        end

        private

        def rails_app?(path)
          path.include?("/app/") || path.include?("/lib/") && File.exist?(File.join(File.dirname(path), "..", "..", "config", "application.rb"))
        end
      end
    end
  end
end
