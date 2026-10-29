# frozen_string_literal: true

module Master
  module Voice
    class Narrator
      # The prose and patterns of data/narration.yml, compiled once. Nothing the
      # narrator says or filters is written in Ruby: change the file, not this.
      class Script
        UNIT_PREFIX = /\A[-\s]*[\w.\-]+\d+(?: at [\w.\-]+)?:\s*/

        # Layers, later over earlier: a path that adds to the factual script (the bard) replaces the
        # keys it names and merges the maps `beats` and `templates` beat by beat.
        def self.load(*paths)
          paths = [Master.data_path("narration.yml")] if paths.empty?
          layers = paths.map { |path| Master.load_yaml(path, default: {}) || {} }
          new(layers.reduce { |base, overlay| merge(base, overlay) })
        end

        def self.merge(base, overlay)
          base.merge(overlay) do |key, old, new|
            %w[beats templates].include?(key) ? old.merge(new) : new
          end
        end

        def initialize(data)
          @data = data
          @redact = (data["redact"] || {}).transform_values { |source| Regexp.new(source) }
          @spoken = data["spoken_replacements"] || {}
        end

        attr_reader :redact, :spoken

        def system_prompt = @data.fetch("system", "").to_s
        def register_words = Array(@data["register_words"]).map { |word| word.to_s.downcase }
        def prompt_template = @data.fetch("prompt", "").to_s
        def beat_instruction(kind) = @data.dig("beats", kind.to_s).to_s

        def closing?(text) = match_any?(@data["closing_events"], text)
        def incomplete?(text) = match_any?(@data["incomplete_events"], text)
        def finding?(text) = match_any?(@data["finding_events"], text)
        def ignored?(text) = match_any?(@data["ignore_events"], text)

        # The line with its dmesg unit ("scan0:", "check1 at master0:") removed.
        def gist_of(text)
          text.to_s.sub(UNIT_PREFIX, "").strip.sub(/[.:;,\s]+\z/, "")
        end

        # One template for the beat, chosen by the beat's number so a run of
        # beats does not repeat itself. Nil when the file offers none.
        def template(kind, number, gist)
          lines = Array(@data.dig("templates", kind.to_s))
          return if lines.empty? || gist.to_s.empty?

          line = lines[number % lines.size]
          at = line.index("%{gist}")
          lead = at && at.positive? ? line[0...at].rstrip : ""
          fitted = lead.empty? || lead.end_with?(".", ":", "?", "!") ? gist : gist.sub(/\A([A-Z])([a-z])/) { "#{$1.downcase}#{$2}" }
          format(line, gist: fitted)
        end

        private

        def match_any?(sources, text)
          Array(sources).any? { |source| Regexp.new(source, Regexp::IGNORECASE).match?(text.to_s) }
        end
      end
    end
  end
end
