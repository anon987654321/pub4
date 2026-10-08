# frozen_string_literal: true

require "yaml"

module Master
  module Voice
    # Speech respellings, applied to TTS text only.
    #
    # rb_edge_tts takes plain text — there is no SSML path through it, so there
    # is no <phoneme> and no lexicon the engine will honour. Respelling the
    # written form is the only pronunciation control available: the table maps
    # what is written to what should be said, and the engine pronounces the
    # substitute correctly because it is an ordinary English word.
    #
    # That makes this a blunt instrument, so the table is deliberately narrow.
    # An entry earns its place by being *wrong* when read literally, not merely
    # unusual: acronyms a voice runs together into a syllable, daemon names that
    # end in a silent-looking d, and product names whose spelling is not their
    # sound. A wrong respelling is worse than none.
    #
    # Applied at the tail of Speech.clean_text, which is the one chokepoint every
    # synthesis entry point already passes through.
    module Lexicon
      PATH = "lexicon.yml"

      module_function

      def table
        @table ||= load_table
      end

      def reload!
        @table = nil
        @pattern = nil
        table
      end

      def load_table
        path = Master.data_path(PATH)
        return {} unless File.exist?(path)

        raw = YAML.safe_load(File.read(path))
        entries = raw.is_a?(Hash) ? raw.fetch("respellings", {}) : {}
        entries.to_h { |written, spoken| [written.to_s, spoken.to_s] }.reject { |k, v| k.empty? || v.empty? }
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Voice::Lexicon.load_table")
        {}
      end

      # Longest first, so "DNSSEC" is not consumed by "DNS". \b does not anchor
      # against a leading or trailing non-word character, which is why entries
      # like "i18n" are matched with explicit lookarounds instead.
      def pattern
        @pattern ||= begin
          keys = table.keys.sort_by { |k| -k.length }
          keys.empty? ? nil : Regexp.new("(?<![\\w-])(#{keys.map { |k| Regexp.escape(k) }.join('|')})(?![\\w-])", Regexp::IGNORECASE)
        end
      end

      def apply(text)
        re = pattern
        return text.to_s if re.nil?

        text.to_s.gsub(re) { |match| lookup(match) || match }
      end

      # Exact case first: an entry written in caps is an acronym and should not
      # be reached by a lowercase word that happens to spell it.
      def lookup(match)
        return table[match] if table.key?(match)

        key = table.keys.find { |k| k.casecmp?(match) }
        key && table[key]
      end
    end
  end
end
