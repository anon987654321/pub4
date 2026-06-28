# frozen_string_literal: true

module Master
  module Ground
    # CaMeL-style capability tag helpers — see tainted.rb for the wrapper struct.
    module Taint
      module_function

      def wrap(value, source:)
        value.is_a?(Tainted) ? value : Tainted.new(value, source).freeze
      end

      def tainted?(value)
        return true if value.is_a?(Tainted)
        return value.any? { |element| tainted?(element) } if value.is_a?(Array)
        return value.values.any? { |element| tainted?(element) } if value.is_a?(Hash)

        false
      end

      def clean(value)
        value.is_a?(Tainted) ? value.value : value
      end

      # Privileged tool calls consult this: deny if any argument carries taint.
      def safe_for_privileged?(args)
        !tainted?(args)
      end
    end
  end
end
