# frozen_string_literal: true

module Master
  module Stages
    # Infer — promote natural-language messages to :command intent via data/infer_patterns.yml.
    class Infer
      # Heuristic task-type detection — used by ModelRouter for tiered model selection.
      PRESSURE_PATTERN = /\b(?:urgent|asap|immediately|critical|now|hurry|fast|quick(?:ly)?|emergency|sos)\b/i.freeze

      VAGUE_STUBS = /\A(?:help(?:\s+me)?|hmm+|idk|ugh|ok+|yeah|yep|nope?|hi+|hey|hello|good\s+\w+|test(?:ing)?|please)\z/i.freeze

      ELICIT_QUESTIONS = {
        implement: "which file, which method, and what change exactly?",
        refactor:  "which file, which method, and what change exactly?",
        design:    "what interface — inputs, outputs, constraints?",
        discover:  "what problem, and how will you measure success?",
      }.freeze
      GREETING_STUBS = /\A(?:hi+|hey|hello|good\s+\w+)\z/i.freeze
      ELICIT_DEFAULT = "be specific: which file or function, and what should change?".freeze

      TASK_TYPE_PATTERNS = {
        architecture: /\b(?:restructur|reorganiz|hierarch|layout|folder|director|module\s+boundar|decouple|extract\s+(?:a\s+)?(?:module|class|layer|service)|where\s+should|how\s+should\s+(?:we|i)\s+organiz|split\s+(?:this\s+)?(?:into|across)|consolidat)/i,
        coding:       /\b(?:def |class |module |require |\.rb\b|fix\s+(?:the\s+)?(?:bug|error|issue)|refactor|implement|write\s+(?:a\s+)?(?:method|class|function|test)|add\s+(?:a\s+)?(?:method|feature)|```(?:ruby|python|js|javascript|bash))/i,
        research:     /\b(?:search|find\s+(?:all|every|info)|research|look\s+up|what\s+is|explain\s+(?:how|what|why)|tell\s+me\s+about)\b/i,
        qa:           /\?(?:\s*$|\s+[A-Z])/m,
      }.freeze

      PATTERNS_PATH = File.join(Master::ROOT, "data", "infer_patterns.yml").freeze

      def initialize
        @patterns = load_patterns
      end

      def call(ctx)
        return Result.ok(ctx) unless ctx[:intent] == :llm

        msg = ctx[:message].to_s.strip
        @patterns.each do |cmd, entry|
          entry[:regexes].each do |pattern|
            next unless (m = msg.match(pattern))
            return Result.ok(ctx.merge(intent: :command, command: cmd, args: extract_args(cmd,
              entry[:capture], m, msg)))
          end
        end

        if vague?(msg)
          if msg.match?(GREETING_STUBS)
            return Result.ok(ctx.merge(intent: :clarify, clarifying_question: "ready. what are you working on?"))
          end
          q = ELICIT_QUESTIONS[ctx[:phase]&.to_sym] || ELICIT_DEFAULT
          return Result.ok(ctx.merge(intent: :clarify, clarifying_question: q))
        end

        pressure = msg.match?(PRESSURE_PATTERN)
        Result.ok(ctx.merge(task_type: infer_task_type(msg), pressure: pressure || ctx[:pressure]))
      end

      private

      def load_patterns
        return {} unless File.exist?(PATTERNS_PATH)
        data = Master.load_yaml(PATTERNS_PATH) || {}
        commands = data["commands"] || {}
        commands.each_with_object({}) do |(name, spec), out|
          regexes = (spec["patterns"] || []).map { |src| Regexp.new(src, Regexp::IGNORECASE | Regexp::EXTENDED) }
          out[name.to_s] = { regexes: regexes, capture: spec["capture"].to_s }
        end
      rescue StandardError => _e
        {}
      end

      def vague?(msg) = msg.match?(VAGUE_STUBS)

      def infer_task_type(msg)
        TASK_TYPE_PATTERNS.each { |type, pat| return type if msg.match?(pat) }
        :general
      end

      def extract_args(cmd, capture, match, msg)
        case capture
        when "path"
          path = match[1]&.strip
          path = nil if path&.match?(/\A(?:all|everything|the|code|codebase)\z/i)
          path.to_s
        when "cycles"
          (match[1] || msg[/\b(\d+)\s*(?:time|cycle|iteration|gang|syklus)/i, 1]).to_s
        when "on_off"
          msg.match?(/\b(?:off|disable|stop|av|skru\s+av)\b/i) ? "off" : "on"
        when "first_group"
          match.captures.compact.first.to_s.strip
        when "persona_name"
          (match[1] || match[2] || match[3]).to_s.strip
        when "soul_subcmd"
          msg[/\b(version|changelog|diff|approve|reject|rollback|propose.{0,60})/i].to_s.strip
        when "orders_subcmd"
          msg.match?(/\blist|show\b/i) ? "list" : ""
        when "scan_depth"
          match[1]&.strip.to_s
        else
          ""
        end
      end
    end
  end
end
