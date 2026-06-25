# frozen_string_literal: true

module Master
  module Ground
    module ToolProtocol
      CLAIM_WORDS = /\b(read|fetched|opened|searched|ran|executed|wrote|created|updated|
                         deleted|patched|committed|verified)\b/xi.freeze
      COMMAND_BLOCK = /```(?:bash|sh|zsh|python|ruby|powershell|shell)\b/i.freeze

      REQUIREMENTS = [
        "Never claim a command, file read, web fetch, or repo write happened unless a tool result proves it.",
        "Prefer action over narration when a tool can do the work.",
        "Do not output shell/code blocks as pretend execution.",
        "After tool use, provide a final text response that separates landed work from failures.",
        "For repo work, name the changed file, exposed symbol, caller, and verification result.",
      ].freeze

      module_function

      def fake_execution_risk?(text)
        text.to_s.match?(COMMAND_BLOCK)
      end

      def operational_claim?(text)
        text.to_s.match?(CLAIM_WORDS)
      end

      def final_report(landed:, failed: [], next_steps: [])
        sections = []
        sections << ["Landed", Array(landed)] unless Array(landed).empty?
        sections << ["Not landed", Array(failed)] unless Array(failed).empty?
        sections << ["Next", Array(next_steps).first(3)] unless Array(next_steps).empty?
        sections.map { |title, rows| "#{title}:\n" + rows.map { |row| "- #{row}" }.join("\n") }.join("\n\n")
      end

      def brief
        "Tool protocol:\n- #{REQUIREMENTS.join("\n- ")}"
      end
    end
  end
end
