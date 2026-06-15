# frozen_string_literal: true

module Master
  module Ground
    # CaMeL-style capability tag: wraps untrusted tool output (web_fetch, read_file of
    # external content) so privileged tool calls can refuse to act on tainted data — the
    # #1 defence against prompt injection (OWASP LLM01). Refs: Defeating Prompt Injections
    # by Design / CaMeL (arXiv:2503.18813).
    Tainted = Struct.new(:value, :source) do
      def tainted? = true
      def to_s = value.to_s
    end

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
