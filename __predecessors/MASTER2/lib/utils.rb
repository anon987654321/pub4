# frozen_string_literal: true

require "did_you_mean"

module MASTER
  module Utils
    module_function

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def valid_ruby?(code)
      # NOTE: CRuby-specific (RubyVM::InstructionSequence). Will raise on JRuby/TruffleRuby.
      RubyVM::InstructionSequence.compile(code)
      true
    rescue SyntaxError, NameError
      false
    end

    def levenshtein(a, b)
      DidYouMean::Levenshtein.distance(a.to_s, b.to_s)
    end

    def similarity(a, b)
      return 1.0 if a == b
      return 0.0 if a.empty? || b.empty?

      max_len = [a.length, b.length].max
      1.0 - (levenshtein(a, b).to_f / max_len)
    end

    # Format token count (k/M notation) - ONE_SOURCE
    def format_tokens(n)
      return n.to_s if n < 1000
      return "#{(n / 1000.0).round(1)}k" if n < 1_000_000

      "#{(n / 1_000_000.0).round(1)}M"
    end
  end
end
