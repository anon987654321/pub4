# frozen_string_literal: true

require "yaml"

module Master
  module Stages
    # Prune — strips AI throat-clearing from LLM responses.
    # Rules loaded from data/strunk.yml. Skips code blocks entirely.
    class Prune
      DATA_PATH = File.join(Master::ROOT, "data", "strunk.yml").freeze

      def call(ctx)
        output = ctx[:output]
        return Result.ok(ctx) unless output.is_a?(String)
        return Result.ok(ctx) if output.empty?
        return Result.ok(ctx) if output.include?("```")  # never mangle code blocks

        cleaned = output
        rules.fetch("preambles", []).each { |p| cleaned = cleaned.sub(/\A#{Regexp.escape(p)}\s*/i, "") }
        rules.fetch("endings",   []).each { |e| cleaned = cleaned.sub(/\s*#{Regexp.escape(e)}\s*\z/i, "") }
        rules.fetch("hedges",    []).each do |h|
          cleaned = cleaned.gsub(h["pattern"].to_s, h["replace"].to_s)
        end

        Result.ok(ctx.merge(output: cleaned.strip))
      end

      private

      def rules
        @rules ||= File.exist?(DATA_PATH) ? YAML.safe_load_file(DATA_PATH) : {}
      rescue StandardError
        @rules = {}
      end
    end
  end
end
