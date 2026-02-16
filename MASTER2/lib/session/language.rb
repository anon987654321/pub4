# frozen_string_literal: true

module MASTER
  class Session
    # Language detection and style checking
    module Language
      extend self

      # Language detection and multi-language support
      def detect_language(text)
        # Norwegian indicators
        norwegian_words = %w[og men er på av til fra med som den det]
        norwegian_count = norwegian_words.count { |word| text.downcase.include?(word) }

        # English indicators
        english_words = %w[the and but are on of to from with as that this]
        english_count = english_words.count { |word| text.downcase.include?(word) }

        # Safety: avoid division by zero
        total_indicators = norwegian_count + english_count
        return Result.ok(language: :english, confidence: 0.0) if total_indicators == 0

        if norwegian_count > english_count
          Result.ok(language: :norwegian, confidence: norwegian_count.to_f / (norwegian_count + english_count))
        else
          Result.ok(language: :english, confidence: english_count.to_f / (norwegian_count + english_count))
        end
      end

      def norwegian_style_check(text)
        issues = []

        # Load anglicisms from constitution.yml
        constitution_file = File.join(MASTER.root, "data", "constitution.yml")
        anglicisms = if File.exist?(constitution_file)
          constitution = YAML.safe_load_file(constitution_file, symbolize_names: true)
          constitution.dig(:language, :norwegian, :anglicisms) || {
            "meeting" => "møte",
            "deal" => "avtale",
            "deadline" => "frist",
            "feedback" => "tilbakemelding"
          }
        else
          {
            "meeting" => "møte",
            "deal" => "avtale",
            "deadline" => "frist",
            "feedback" => "tilbakemelding"
          }
        end

        anglicisms.each do |english, norwegian|
          if text.downcase.include?(english.to_s)
            issues << "Replace '#{english}' with '#{norwegian}'"
          end
        end

        Result.ok(issues: issues)
      end
    end
  end
end
