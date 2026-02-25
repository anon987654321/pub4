# frozen_string_literal: true

require_relative "mode"

module MASTER
  # Classifies the intent of user input into a Mode constant.
  # Cheap, deterministic, no LLM required.
  class IntentClassifier
    SHELLISH = [
      /^\w+@[\w.-]+.*\$\s+/,
      /\bLast login:\b/i,
      /\bOpenBSD\b/i,
      /\bgit (?:pull|push|fetch|clone)\b/i,
      /^\s*From https?:\/\//i,
    ].freeze

    DIFFISH = [
      /^\s*diff --git\b/,
      /^\s*\+\+\+\s+/,
      /^\s*---\s+/,
      /^\s*@@\s+/,
    ].freeze

    def self.detect(text, explicit: nil)
      return explicit if explicit && Mode.valid?(explicit)

      t = text.to_s
      return Mode::OPS      if SHELLISH.any? { |p| t.match?(p) }
      return Mode::REFACTOR if DIFFISH.any?  { |p| t.match?(p) }

      Mode::CHAT
    rescue StandardError
      Mode::CHAT
    end
  end
end
