# frozen_string_literal: true

require "json"
require_relative "../ai/orientation"

module Master
  module Fix
    class Reflection
      MAX_CONTEXT_BYTES = 24_000
      MAX_FIELD_BYTES = 1_000
      MIN_REMAINING_SECONDS = 120
      VERDICTS = %w[KEEP REPAIR INVESTIGATE HUMAN INCONCLUSIVE].freeze

      Result = Data.define(:verdict, :summary, :law, :anchor, :evidence, :next_action) do
        def repair? = verdict == "REPAIR"
        def actionable? = %w[REPAIR INVESTIGATE HUMAN].include?(verdict)
      end

      def initialize(agent:, root:, bus: nil)
        @agent = agent
        @root = File.expand_path(root)
        @bus = bus
      end

      def call(target:, state:, files:, history:, changed_paths: [], remaining_seconds: nil)
        return result("INCONCLUSIVE", "reflection unavailable — no model") unless @agent.respond_to?(:ask)
        return result("INCONCLUSIVE", "reflection skipped — insufficient run budget") if remaining_seconds && remaining_seconds.to_f < MIN_REMAINING_SECONDS

        orientation = Master::AI::Orientation.render(root: @root, target:, depth: 3, max_entries: 120)
        answer = @agent.ask(prompt(target:, state:, files:, history:, changed_paths:, orientation:), operation: :reflection).to_s
        parsed = parse(answer)
        publish(parsed, target:, state:)
        parsed
      rescue StandardError => e
        @bus&.publish("fix_loop:reflection_error", target:, state:, error: "#{e.class}: #{e.message}")
        Master::Trace::Dmesg.status("reflect0", "inconclusive, #{e.class}: #{e.message}")
        result("INCONCLUSIVE", "reflection inconclusive — #{e.class}")
      end

      private

      def prompt(target:, state:, files:, history:, changed_paths:, orientation:)
        metrics = {
          state:,
          files: Array(files).size,
          changed_paths: Array(changed_paths).first(40).map { |path| relative(path) },
          history: Array(history).last(6).map { |row| row.to_h.slice(:pass, :score, :progressed) },
          structural_mode: ENV["MASTER_FIX_STRUCTURAL"] == "1" ? "enabled" : "disabled",
          semantic_mode: ENV.fetch("MASTER_SCAN_SEMANTIC_SAMPLE", "0"),
        }

        text = <<~PROMPT
          Fresh-eyes reflection after MASTER /fix.

          This is not another repair pass. Reassess the current result from first principles.
          Look for the most important thing the repair loop may have missed, overfit to, or
          mistaken for completion. Prefer a concrete evidence-linked defect over preference.
          Ask whether ownership is singular, the current structure is simpler, exclusions are
          honest, and the proof actually supports the terminal state.

          Never invent measurements, callers, incidents, requirements, or law ids.
          Never edit source during reflection.

          Return exactly:
          VERDICT: KEEP | REPAIR | INVESTIGATE | HUMAN | INCONCLUSIVE
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
        text.byteslice(0, MAX_CONTEXT_BYTES)
      end

      def parse(answer)
        fields = answer.lines.each_with_object({}) do |line, out|
          key, value = line.split(":", 2)
          out[key.strip.upcase] = value.strip if key && value
        end
        verdict = fields["VERDICT"].to_s.upcase
        verdict = "INCONCLUSIVE" unless VERDICTS.include?(verdict)
        law = normalize(fields["LAW"])
        anchor = valid_anchor(fields["ANCHOR"])
        evidence = normalize(fields["EVIDENCE"])
        next_action = normalize(fields["NEXT"])
        summary = normalize(fields["SUMMARY"]) || "reflection returned no summary"

        unless law && anchor && evidence && next_action && known_law?(law)
          verdict = "INVESTIGATE" if verdict == "REPAIR"
          law = nil unless known_law?(law)
        end

        Result.new(verdict:, summary: summary.to_s.byteslice(0, MAX_FIELD_BYTES),
                   law:, anchor:, evidence:, next_action:)
      end

      def known_law?(law_id)
        return false if law_id.nil? || law_id.empty?
        return false unless File.file?(File.join(Master::ROOT, "law", "law.rb"))

        require File.join(Master::ROOT, "law", "law") unless defined?(::Law)
        ::Law.load_all(File.join(Master::ROOT, "law")) if ::Law.definitions.empty?
        ::Law.definitions.values.any? { |definition| definition.id.to_s.casecmp?(law_id.to_s) }
      rescue StandardError
        false
      end

      def valid_anchor(value)
        path, line = value.to_s.split(":", 2)
        return unless line.to_s.match?(/\A\d+\z/)
        absolute = File.expand_path(path.to_s, @root)
        return unless absolute.start_with?("#{@root}#{File::SEPARATOR}")
        return unless File.file?(absolute)
        "#{relative(absolute)}:#{line}"
      end

      def normalize(value)
        value = value.to_s.strip
        return nil if value.empty? || value.casecmp?("NONE")
        value.byteslice(0, MAX_FIELD_BYTES)
      end

      def result(verdict, summary)
        Result.new(verdict:, summary:, law: nil, anchor: nil, evidence: nil, next_action: nil)
      end

      def publish(result, target:, state:)
        @bus&.publish("fix_loop:reflection", target: relative(target), state:, verdict: result.verdict,
                      law: result.law, anchor: result.anchor, summary: result.summary, actionable: result.actionable?)
        Master::Trace::Dmesg.status("reflect0", "#{result.verdict.downcase} #{result.summary}".strip)
      end

      def relative(path)
        full = File.expand_path(path.to_s)
        return path.to_s unless full == @root || full.start_with?("#{@root}#{File::SEPARATOR}")
        full.delete_prefix("#{@root}#{File::SEPARATOR}")
      end
    end
  end
end
