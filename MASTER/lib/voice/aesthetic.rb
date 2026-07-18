# frozen_string_literal: true

module Master
  module Voice
    module Aesthetic
      # brutalist = flat/minimalist (x.com-like), the house default. wscons (green
      # terminal) and phosphor (glow) are the legacy retro modes, opt-in only.
      MODES = %w[brutalist wscons phosphor].freeze

      module_function

      def mode
        raw = ENV["MASTER_AESTHETIC"].to_s.strip.downcase
        MODES.include?(raw) ? raw : "brutalist"
      end

      def brutalist? = mode == "brutalist"
      def wscons? = mode == "wscons"
      def phosphor? = mode == "phosphor"
    end
  end
end
