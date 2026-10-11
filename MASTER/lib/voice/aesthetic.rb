# frozen_string_literal: true

module Master
  module Voice
    module Aesthetic
      # Phosphor is the motion-led house face; wscons and brutalist remain explicit
      # low-distraction terminal profiles for operators who prefer them.
      MODES = %w[brutalist wscons phosphor].freeze

      module_function

      def mode
        raw = ENV["MASTER_AESTHETIC"].to_s.strip.downcase
        MODES.include?(raw) ? raw : "phosphor"
      end

      def brutalist? = mode == "brutalist"
      def wscons? = mode == "wscons"
      def phosphor? = mode == "phosphor"
    end
  end
end
