# frozen_string_literal: true

require "yaml"

module Master
  module Stages
    # Prune — strip AI throat-clearing from LLM responses.
    # Rules loaded from data/strunk.yml.
    #
    # Fence-aware: previously bailed entirely on any response containing a
    # triple-backtick. Now splits into prose/code segments, prunes prose,
    # leaves code blocks untouched.
    class Prune
      DATA_PATH = File.join(Master::ROOT, "data", "strunk.yml").freeze
      FENCE_RE  = /(```.*?```)/m.freeze

      def call(ctx)
        output = ctx[:output]
        return Result.ok(ctx) unless output.is_a?(String) && !output.empty?

        cleaned = prune_mixed(output)
        Result.ok(ctx.merge(output: cleaned.strip))
      end

      private

      # Split on fenced code blocks, prune only the prose segments.
      def prune_mixed(text)
        segments = text.split(FENCE_RE)
        segments.map { |seg|
          if seg.start_with?("```")
            seg
          else
            strip_rules(seg)
          end
        }.join
      end

      def strip_rules(text)
        cleaned = text
        rules.fetch("preambles", []).each { |p| cleaned = cleaned.sub(/\A#{Regexp.escape(p)}\s*/i, "") }
        rules.fetch("endings",   []).each { |e| cleaned = cleaned.sub(/\s*#{Regexp.escape(e)}\s*\z/i, "") }
        # Hedges are plain-string replacements, not regex patterns.
        rules.fetch("hedges",    []).each { |h| cleaned = cleaned.gsub(h["pattern"].to_s, h["replace"].to_s) }
        cleaned
      end

      def rules
        @rules ||= File.exist?(DATA_PATH) ? YAML.safe_load_file(DATA_PATH) : {}
      rescue StandardError
        @rules = {}
      end
    end
  end
end
