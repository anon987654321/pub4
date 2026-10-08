# frozen_string_literal: true

require "json"
require_relative "../ai/orientation"

module Master
  module Fix
    # Fresh-eyes review at the end of a repair run. Reflection is deliberately
    # read-only: it may queue one evidence-backed next action, but it never edits
    # source and never converts model taste into a convergence claim.
    class Reflection
      MAX_CONTEXT_BYTES = 24_000
      MAX_SUMMARY_BYTES = 1_000
      MIN_REMAINING_SECONDS = 120
      VERDICTS = %w[KEEP REPAIR INVESTIGATE HUMAN].freeze

      Result = Data.define(:verdict, :summary, :law, :anchor, :evidence, :next_action) do
        def actionable? = %w[REPAIR INVESTIGATE HUMAN].include?(verdict.to_s)
        def repair? = verdict.to_s == "REPAIR"
      end

      def initialize(agent:, root:, bus: nil)
        @agent = agent
        @root = File.expand_path(root)
        @bus = bus
      end

      def call(target:, state:, files:, history:, changed_paths: [], remaining_seconds: nil)
        return Result.new(verdict: "KEEP", summary: "reflection unavailable — no model", law: nil, anchor: nil, evidence: nil, next_action: nil) unless @agent.respond_to?(:ask)
        if remaining_seconds && remaining_seconds.to_f < MIN_REMAINING_SECONDS
          return Result.new(verdict: "KEEP", summary: "reflection skipped — insufficient run budget", law: nil, anchor: nil, evidence: nil, next_action: nil)
        end

        orientation = Master::AI::Orientation.render(root: @root, target:, depth: 3, max_entries: 120)
        prompt = build_prompt(target:, state:, files:, history:, changed_paths:, orientation:)
        answer = @agent.ask(prompt, operation: :reflection).to_s
        result = parse(answer)
        publish(result, target:, state:)
        result
      rescue StandardError => e
        @bus&.publish("fix_loop:reflection_error", target:, error: "#{e.class}: #{e.message}")
        Master::Trace::Dmesg.status("reflect0", "inconclusive, #{e.class}: #{e.message}")
        Result.new(verdict: "KEEP", summary: "reflection inconclusive — #{e.class}", law: nil, anchor: nil, evidence: nil, next_action: nil)
      end

      private

      def build_prompt(target:, state:, files:, history:, changed_paths:, orientation:)
        metrics = {
          state:,
          file_count: Array(files).size,
          changed_paths: Array(changed_paths).first(40).map { |path| relative(path) },
          history: Array(history).last(6).map do |row|
            row.to_h.slice(:pass, :score, :snapshot_digest, :captured_files, :progressed)
          end,
          structural_mode: ENV["MASTER_FIX_STRUCTURAL"] == "1" ? "enabled" : "separate campaign only",
          semantic_mode: ENV.fetch("MASTER_SCAN_SEMANTIC_SAMPLE", "0"),
        }

        prompt = <<~PROMPT
          Fresh-eyes reflection after MASTER /fix.

          This is not another repair pass. Reassess the repository from first principles.
          Look for the most important thing the preceding repair loop may have missed,
          overfit to, or mistaken for completion. Prefer a concrete, evidence-linked
          problem over stylistic preference. Ask whether the current structure is simpler,
          whether ownership is singular, whether exclusions are honest, and whether the
          proof actually supports the terminal state.

          Do not propose a redesign merely because you prefer another design.
          Do not invent measurements, callers, incidents, or requirements.
          Do not edit source. Return exactly:

          VERDICT: KEEP | REPAIR | INVESTIGATE | HUMAN
          SUMMARY: one concise sentence
          LAW: existing law id, or NONE
          ANCHOR: repository-relative path:line, or NONE
          EVIDENCE: one sentence grounded in supplied evidence
          NEXT: one concrete next action, or NONE

          Current state:
          #{JSON.generate(metrics)}

          Orientation:
          #{orientation}
        PROMPT
        prompt.byteslice(0, MAX_CONTEXT_BYTES)
      end

      def parse(answer)
        fields = answer.to_s.lines.each_with_object({}) do |line, out|
          key, value = line.split(":", 2)
          next unless key && value

          out[key.strip.upcase] = value.strip
        end

        verdict = fields["VERDICT"].to_s.upcase
        verdict = "KEEP" unless VERDICTS.include?(verdict)
        anchor = valid_anchor(fields["ANCHOR"])
        law = fields["LAW"].to_s.strip
        law = nil if law.empty? || law.casecmp?("NONE")
        evidence = fields["EVIDENCE"].to_s.strip
        next_action = fields["NEXT"].to_s.strip
        next_action = nil if next_action.empty? || next_action.casecmp?("NONE")

        unless verdict == "REPAIR" && anchor && !law.nil? && !evidence.empty? && next_action
          verdict = "INVESTIGATE" if verdict == "REPAIR"
        end

        Result.new(
          verdict:,
          summary: fields["SUMMARY"].to_s.byteslice(0, MAX_SUMMARY_BYTES).to_s,
          law:,
          anchor:,
          evidence: evidence.empty? ? nil : evidence.byteslice(0, MAX_SUMMARY_BYTES),
          next_action: next_action&.byteslice(0, MAX_SUMMARY_BYTES),
        )
      end

      def valid_anchor(value)
        path, line = value.to_s.split(":", 2)
        return unless path && line.to_s.match?(/\A\d+\z/)

        absolute = File.expand_path(path, @root)
        return unless absolute == @root || absolute.start_with?("#{@root}#{File::SEPARATOR}")
        return unless File.file?(absolute)

        "#{relative(absolute)}:#{line}"
      end

      def publish(result, target:, state:)
        @bus&.publish(
          "fix_loop:reflection",
          target: relative(target),
          state:,
          verdict: result.verdict,
          law: result.law,
          anchor: result.anchor,
          summary: result.summary,
          actionable: result.actionable?,
        )
        Master::Trace::Dmesg.status(
          "reflect0",
          "#{result.verdict.downcase} #{result.summary}".strip,
        )
      end

      def relative(path)
        full = File.expand_path(path.to_s)
        return path.to_s unless full == @root || full.start_with?("#{@root}#{File::SEPARATOR}")

        full.delete_prefix("#{@root}#{File::SEPARATOR}")
      end
    end
  end
end
