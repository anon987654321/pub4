# frozen_string_literal: true

module Master
  module Stages
    # Prune — strip sycophancy and markdown formatting from LLM responses.
    # Rules loaded from data/rules.yml (voice.strunk). Fence-aware: prunes prose, leaves code blocks.
    class Prune
      RULES_PATH = File.join(Master::ROOT, "data", "rules.yml").freeze
      FENCE_RE  = /(```.*?```)/m.freeze

      HEADER_RE     = %r{^\#{1,6}\s+}.freeze
      BOLD_RE       = /\*\*(.+?)\*\*/
      ITALIC_RE     = /(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)/
      BULLET_RE     = /^\s*[-*+]\s+/
      NUMBERED_RE   = /^\s*\d+\.\s+/
      HR_RE         = /^-{3,}\s*$/
      LINK_RE       = /\[([^\]]+)\]\([^)]+\)/
      SYCOPHANCY_RE = /\A\s*(?:certainly|of course|great question|absolutely|sure|happy to help|i(?:'d| would) be (?:happy|glad)|no problem)[!.,]*\s*/i

      def call(ctx)
        raw = ctx[:output]
        output = if raw.respond_to?(:ok?) && raw.ok?
                   raw.value!.to_s
                 elsif raw.is_a?(String)
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
        segments.map { |seg|
          seg.start_with?("```") ? seg : strip_all(seg)
        }.join
      end

      def strip_all(text)
        cleaned = text
        cleaned = cleaned.sub(SYCOPHANCY_RE, "")

        rules.fetch("preambles", []).each { |p| cleaned = cleaned.sub(/\A\s*#{Regexp.escape(p)}\s*/i, "") }
        rules.fetch("endings",   []).each { |e| cleaned = cleaned.sub(/\s*#{Regexp.escape(e)}\s*\z/i, "") }
        rules.fetch("hedges",    []).each do |h|
          if h.is_a?(Hash)
            cleaned = cleaned.gsub(h["pattern"].to_s, h["replace"].to_s)
          else
            cleaned = cleaned.gsub(/\b#{Regexp.escape(h)}\b\s*/i, "")
          end
        end

        cleaned = cleaned.gsub(HEADER_RE, "")
        cleaned = cleaned.gsub(BOLD_RE, '\1')
        cleaned = cleaned.gsub(ITALIC_RE, '\1')
        cleaned = cleaned.gsub(LINK_RE, '\1')
        cleaned = cleaned.gsub(HR_RE, "")
        cleaned = cleaned.gsub(BULLET_RE, "")
        cleaned = cleaned.gsub(NUMBERED_RE, "")
        cleaned = cleaned.gsub(/\n{3,}/, "\n\n")
        cleaned
      end

      def rules
        @rules ||= begin
          data = File.exist?(RULES_PATH) ? Master.load_yaml(RULES_PATH) : {}
          data.dig("voice", "strunk") || {}
        end
      rescue StandardError
        @rules = {}
      end
    end
  end
end
