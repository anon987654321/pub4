# frozen_string_literal: true

module Master
  module Fix
    # Language defects read off a surface captured in each shipped locale: a
    # key shown as text, a missing-translation marker, and a control or chrome
    # label that is word for word the same in nb and en when a translator would
    # have written two. The apps default to nb, so an English literal in a
    # template is a defect, and it only shows when the page is rendered both ways.
    module VisualI18n
      MISSING = /translation[ _]missing/i
      KEY = /\A[a-z][a-z0-9_]*(\.[a-z0-9_]+){2,}\z|\A[a-z]+(_[a-z0-9]+)+\.[a-z0-9_]+\z/
      TLD = /\.(no|com|org|net|io|art|dev|app)\z/
      # Labels a translator owns. Body copy, headings and links in lists are
      # user content that reads the same in both locales, so they are not held
      # to the identical-text check.
      UI_TAGS = %w[button label legend th summary option].freeze
      CHROME = /\A(header|nav|footer)(\.|\z)/
      LIMIT = 50

      module_function

      def broken?(text, key = "")
        text = text.to_s.strip
        key.to_s.include?("translation_missing") || text.match?(MISSING) || (text.match?(KEY) && !text.match?(TLD))
      end

      # Rows shaped like the quality gate's other offenders: {"key" => label}.
      def rows(payload)
        locales = payload["locales"]
        return [] unless locales.is_a?(Hash)

        live = locales.select { |_, v| v.is_a?(Hash) && v["texts"].is_a?(Hash) }
        (broken_rows(live) + identical_rows(live)).first(LIMIT)
      end

      def broken_rows(live)
        live.flat_map do |code, entry|
          entry["texts"].filter_map { |key, (text, _tag)| { "key" => "#{key} [#{code}]" } if broken?(text, key) }
        end
      end

      def identical_rows(live)
        nb, en = live.values_at("nb", "en")
        return [] unless nb && en

        (nb["texts"].keys & en["texts"].keys).filter_map do |key|
          text, tag = nb["texts"][key]
          next unless text == en["texts"][key][0] && ui?(key, tag) && translatable?(text)

          { "key" => "#{key} [nb=en #{text[0, 30].inspect}]" }
        end
      end

      def ui?(key, tag) = UI_TAGS.include?(tag) || key.to_s.split(">").any? { |part| part.match?(CHROME) }

      # A phrase with a lowercase word, or a lone lowercase word, is language.
      # Capitalised words only, digits, addresses and short tokens are names,
      # numbers and symbols that no translator changes.
      def translatable?(text)
        return false if text.length < 4 || text.match?(/[@\d]|https?:|www\./) || text.match?(TLD)

        text.split.any? { |word| word.match?(/\A[[:lower:]]{3,}/) }
      end
    end
  end
end
