# frozen_string_literal: true

module Master
  module Now
    module Stages
      # Prune — strip sycophancy and markdown formatting from LLM responses.
      # Rules loaded from data/rules.yml (voice.strunk). Fence-aware: prunes prose, leaves code blocks.
      class Prune
        FENCE_RE = /(```.*?```)/m.freeze

        HEADER_RE = %r{^\#{1,6}\s+}.freeze
        BOLD_RE = /\*\*(.+?)\*\*/
        ITALIC_RE = /(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)/
        BULLET_RE = /^\s*[-*+]\s+/
        NUMBERED_RE = /^\s*\d+\.\s+/
        HR_RE = /^-{3,}\s*$/
        LINK_RE = /\[([^\]]+)\]\([^)]+\)/
        CLAIM_RE = /\b(?:completed|done|fixed|implemented|changed|updated|edited|modified|created|deleted|removed)\b/i.freeze
        DIFF_EVIDENCE_RE = /^(?:diff --git|---\s|\+\+\+\s|@@\s)/.freeze
        COMMAND_EVIDENCE_RE = /\b(?:command output|exit code|process exited|ran:|verification:|test(?:s)?\s+(?:passed|failed))\b/i.freeze
        SYCOPHANCY_RE = /\A\s*(?:
          certainly|of[ ]course|great[ ]question|absolutely|sure|
          happy[ ]to[ ]help|i(?:'d|[ ]would)[ ]be[ ](?:happy|glad)|no[ ]problem
        )[!.,]*\s*/ix

        def call(ctx)
          raw = ctx.respond_to?(:output) ? ctx.output : ctx[:output]
          output = if raw.respond_to?(:ok?) && raw.ok?
                     raw.value!.to_s
                   elsif raw.is_a?(String)
                     raw
                   else
                     return Result.ok(ctx)
                   end
          return Result.ok(ctx) if output.empty?

          cleaned = require_evidence(prune_mixed(output).strip)
          final = raw.respond_to?(:ok?) ? Result.ok(cleaned) : cleaned
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

        def require_evidence(text)
          return text unless unsupported_claim?(text)

          [text, evidence_requirement].join("\n")
        end

        def unsupported_claim?(text)
          text.match?(CLAIM_RE) && !evidence_present?(text)
        end

        def evidence_present?(text)
          text.each_line.any? { |line| line.match?(DIFF_EVIDENCE_RE) } ||
            text.match?(COMMAND_EVIDENCE_RE)
        end

        def evidence_requirement
          "evidence required: show unified diff for modifications or command output for completion claims."
        end

        def rules
          @rules ||= begin
            data = File.exist?(Master::RULES_PATH) ? Master.load_yaml(Master::RULES_PATH) : {}
            data.dig("voice", "strunk") || {}
          end
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "Prune.rules")
          @rules = {}
        end
      end
    end
  end
end
