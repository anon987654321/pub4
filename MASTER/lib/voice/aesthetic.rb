# frozen_string_literal: true

module Master
  module Voice
    module Aesthetic
      MODES = %w[wscons phosphor].freeze

      module_function

      def mode
        raw = ENV["MASTER_AESTHETIC"].to_s.strip.downcase
        MODES.include?(raw) ? raw : "wscons"
      end

      def wscons? = mode == "wscons"
      def phosphor? = mode == "phosphor"
    end
  end
end