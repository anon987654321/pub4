# frozen_string_literal: true

require_relative "mode"

module MASTER
  # Classifies the intent of user input into a Mode constant.
  # Uses NLU signals (LLM with deterministic fallback).
  class IntentClassifier
    def self.detect(text, explicit: nil)
      return explicit if explicit && Mode.valid?(explicit)

      signals = defined?(NLU) ? NLU.classify_signals(text.to_s) : Set.new

      return Mode::OPS      if signals.include?(:shell_paste)
      return Mode::REFACTOR if signals.include?(:diff_paste)

      Mode::CHAT
    rescue StandardError
      Mode::CHAT
    end
  end
end
