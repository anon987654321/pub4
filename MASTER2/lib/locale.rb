# frozen_string_literal: true

module MASTER
  # Locale - Language detection, style checking, and persona management
  module Locale
    SUPPORTED_LANGUAGES = %i[english norwegian].freeze
    SUPPORTED_PERSONAS = %i[ronin lawyer hacker architect sysadmin trader medic].freeze

    NORWEGIAN_RULES = [
      "Use bokmål, not nynorsk",
      "Prefer short sentences",
      "Avoid anglicisms when Norwegian words exist",
      "Match user's formality level"
    ].freeze

    ANGLICISMS = {
      "meeting" => "møte",
      "deal" => "avtale",
      "deadline" => "frist",
      "feedback" => "tilbakemelding"
    }.freeze

    class << self
      def detect_language(text)
        norwegian_words = %w[og men er på av til fra med som den det]
        norwegian_count = norwegian_words.count { |word| text.downcase.include?(word) }

        english_words = %w[the and but are on of to from with as that this]
        english_count = english_words.count { |word| text.downcase.include?(word) }

        if norwegian_count > english_count
          Result.ok(language: :norwegian, confidence: norwegian_count.to_f / (norwegian_count + english_count))
        else
          Result.ok(language: :english, confidence: english_count.to_f / (norwegian_count + english_count))
        end
      end

      def norwegian_style_check(text)
        issues = []
        ANGLICISMS.each do |english, norwegian|
          issues << "Replace '#{english}' with '#{norwegian}'" if text.downcase.include?(english)
        end
        Result.ok(issues: issues)
      end

      def set_persona(persona)
        persona = persona.to_sym
        return Result.err("Unknown persona: #{persona}") unless SUPPORTED_PERSONAS.include?(persona)
        Session.current.write_metadata(:persona, persona)
        Result.ok(persona: persona)
      end

      def current_persona
        Session.current.metadata_value(:persona) || :ronin
      end
    end
  end
end
