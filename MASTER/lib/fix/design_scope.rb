# frozen_string_literal: true

module Master
  module Fix
    # Which RAILS apps a /fix target names, for the design loop that /fix runs
    # after a verified fix. The loop measures one rendered app at a time, so a target that names
    # no single app (RAILS, a tree list, the shared layer) names none: guessing every app
    # would start an hours-long run nobody asked for.
    module DesignScope
      SEGMENT = %r{(?:\A|/)RAILS/([^/\s]+)}
      NOT_AN_APP = %w[__shared].freeze

      module_function

      def apps_for(target)
        target.to_s.split(/\s+/).filter_map do |token|
          name = token.match(SEGMENT)&.captures&.first
          name unless name.nil? || NOT_AN_APP.include?(name)
        end.uniq
      end
    end
  end
end
