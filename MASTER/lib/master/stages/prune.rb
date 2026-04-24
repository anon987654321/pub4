# frozen_string_literal: true

require "yaml"

module Master
  module Stages
    # Prune — strip AI throat-clearing AND markdown formatting from LLM responses.
    # Rules loaded from data/strunk.yml.
    #
    # Fence-aware: splits into prose/code segments, prunes prose,
    # leaves code blocks untouched.
    class Prune
      DATA_PATH = File.join(Master::ROOT, "data", "strunk.yml").freeze
      FENCE_RE  = /(```.*?```)/m.freeze

      # Markdown patterns to strip from prose (outside code fences)
      HEADER_RE     = Regexp.new('^\#{1,6}\s+')       # ## Header
      BOLD_RE       = /\*\*(.+?)\*\*/                 # **bold**
      ITALIC_RE     = /(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)/ # *italic*
      BULLET_RE     = /^\s*[-*+]\s+/                  # - bullet or * bullet
      NUMBERED_RE   = /^\s*\d+\.\s+/                  # 1. numbered
      HR_RE         = /^-{3,}\s*$/                     # ---
      LINK_RE       = /\[([^\]]+)\]\([^)]+\)/          # [text](url) -> text

      # Sycophantic openers the LLM loves to add
      SYCOPHANCY_RE = /\A\s*(?:certainly|of course|great question|absolutely|sure|happy to help|i(?:'d| would) be (?:happy|glad)|no problem)[!.,]*\s*/i

def call(ctx)
  raw = ctx[:output]
  # Unwrap Result to get the actual text
  output = if raw.respond_to?(:ok?) && raw.ok?
             raw.value!.to_s
           elsif raw.is_a?(String)
             raw
           else
             return Result.ok(ctx)
           end
  return Result.ok(ctx) if output.empty?

  cleaned = prune_mixed(output)
  # Re-wrap as Result if original was a Result
  final = raw.respond_to?(:ok?) ? Result.ok(cleaned.strip) : cleaned.strip
  Result.ok(ctx.merge(output: final))
end

      private

      def prune_mixed(text)
        segments = text.split(FENCE_RE)
        segments.map { |seg|
          seg.start_with?("```") ? seg : strip_all(seg)
        }.join
      end

      def strip_all(text)
        cleaned = text

        # Sycophancy
        cleaned = cleaned.sub(SYCOPHANCY_RE, "")

        # Strunk rules
        rules.fetch("preambles", []).each { |p| cleaned = cleaned.sub(/\A\s*#{Regexp.escape(p)}\s*/i, "") }
        rules.fetch("endings",   []).each { |e| cleaned = cleaned.sub(/\s*#{Regexp.escape(e)}\s*\z/i, "") }
        rules.fetch("hedges",    []).each do |h|
          if h.is_a?(Hash)
            cleaned = cleaned.gsub(h["pattern"].to_s, h["replace"].to_s)
          else
            cleaned = cleaned.gsub(/\b#{Regexp.escape(h)}\b\s*/i, "")
          end
        end

        # Markdown formatting
        cleaned = cleaned.gsub(HEADER_RE, "")
        cleaned = cleaned.gsub(BOLD_RE, '\1')
        cleaned = cleaned.gsub(ITALIC_RE, '\1')
        cleaned = cleaned.gsub(LINK_RE, '\1')
        cleaned = cleaned.gsub(HR_RE, "")
        cleaned = cleaned.gsub(BULLET_RE, "")
        cleaned = cleaned.gsub(NUMBERED_RE, "")

        # Collapse excessive blank lines
        cleaned = cleaned.gsub(/\n{3,}/, "\n\n")

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
