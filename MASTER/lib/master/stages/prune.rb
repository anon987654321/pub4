# frozen_string_literal: true

require "yaml"
require_relative "../../logging"

module Master
  module Stages
    # Prune — strip sycophancy and markdown formatting from LLM responses.
    # Rules loaded from data/strunk.yml. Fence-aware: prunes prose, leaves code blocks.
    class Prune
      DATA_PATH = File.join(Master::ROOT, "data", "strunk.yml").freeze
      FENCE_RE  = /(```.*?```)/m.freeze

      HEADER_RE     = %r{^\#{1,6}\s+}
      BOLD_RE       = /\*\*(.+?)\*\*/
      ITALIC_RE     = /(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)/
      BULLET_RE     = /^\s*[-*+]\s+/
      NUMBERED_RE   = /^\s*\d+\.\s+/
      HR_RE         = /^-{3,}\s*$/
      LINK_RE       = /\[([^\]]+)\]\([^)]+\)/
      SYCOPHANCY_RE = /\A\s*(?:certainly|of course|great question|absolutely|sure|happy to help|i(?:'d| would) be (?:happy|glad)|no problem)[!.,]*\s*/i

      def call(ctx)
        raw = ctx[:output]
        output = case raw
                 when ->(r) { r.respond_to?(:ok?) && r.ok? }
                   raw.value!.to_s
                 when String
                   raw
                 else
                   return Result.ok(ctx)
                 end
        return Result.ok(ctx) if output.empty?

        cleaned = prune_mixed(output)
        final = raw.respond_to?(:ok?) ? Result.ok(cleaned.strip) : cleaned.strip
        Result.ok(ctx.merge(output: final))
      end

      private

      def prune_mixed(text)
        segments = text.split(FENCE_RE)
        segments.map { |seg| seg.start_with?("```") ? seg : strip_all(seg) }.join
      end

      def strip_all(text)
        text = remove_sycophancy(text)
        text = remove_preambles_endings_hedges(text)
        text = remove_markdown_formatting(text)
        collapse_blank_lines(text)
      end

      def remove_sycophancy(text)
        text.sub(SYCOPHANCY_RE, "")
      end

      def remove_preambles_endings_hedges(text)
        cleaned = text
        rules.fetch("preambles", []).each { |p| cleaned = cleaned.sub(/\A\s*#{Regexp.escape(p)}\s*/i, "") }
        rules.fetch("endings",   []).each { |e| cleaned = cleaned.sub(/\s*#{Regexp.escape(e)}\s*\z/i, "") }
        rules.fetch("hedges",    []).each do |h|
          if h.is_a?(Hash)
            cleaned = cleaned.gsub(h["pattern"].to_s, h["replace"].to_s)
          else
            cleaned = cleaned.gsub(/\b#{Regexp.escape(h)}\b\s*/i, "")
          end
        end
        cleaned
      end

      def remove_markdown_formatting(text)
        cleaned = text
        cleaned = cleaned.gsub(HEADER_RE, "")
        cleaned = cleaned.gsub(BOLD_RE, '\1')
        cleaned = cleaned.gsub(ITALIC_RE, '\1')
        cleaned = cleaned.gsub(LINK_RE, '\1')
        cleaned = cleaned.gsub(HR_RE, "")
        cleaned = cleaned.gsub(BULLET_RE, "")
        cleaned = cleaned.gsub(NUMBERED_RE, "")
        cleaned
      end

      def collapse_blank_lines(text)
        text.gsub(/\n{3,}/, "\n\n")
      end

      def rules
        @rules ||= begin
          if File.exist?(DATA_PATH)
            YAML.safe_load_file(DATA_PATH)
          else
            {}
          end
        rescue StandardError => e
          Master::Logging.logger.error("Failed to load prune rules from #{DATA_PATH}: #{e.message}")
          {}
        end
      end
    end
  end
end