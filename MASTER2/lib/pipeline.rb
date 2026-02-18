# frozen_string_literal: true

require_relative "pipeline/repl"

module MASTER
  # Pipeline - Uses Executor with hybrid patterns
  class Pipeline
    DEFAULT_STAGES = %i[intake compress guard route council ask lint render].freeze
    ALLOWED_STAGES = %w[Intake Compress Guard Route Council Ask Lint Render Execute].freeze
    MAX_INPUT_LENGTH = 100_000 # ~25k tokens

    @current_pattern = :auto
    @current_pattern_mutex = Mutex.new

    class << self
      def current_pattern
        @current_pattern_mutex.synchronize { @current_pattern }
      end

      def current_pattern=(value)
        @current_pattern_mutex.synchronize { @current_pattern = value }
      end
    end

    def initialize(stages: DEFAULT_STAGES, mode: :executor)
      @mode = mode
      @stages = if mode == :executor
        []
      else
        stages.map do |stage|
          if stage.respond_to?(:call)
            stage
          else
            const_name = stage.to_s.capitalize
            unless ALLOWED_STAGES.include?(const_name)
              raise ArgumentError, "Invalid pipeline stage: #{stage}. Allowed: #{ALLOWED_STAGES.join(', ')}"
            end
            Stages.const_get(const_name.to_sym).new
          end
        end
      end
    end

    def call(input)
      Logging.dmesg_log('pipeline', message: 'ENTER pipeline.call')
      text = input.is_a?(Hash) ? input[:text] : input.to_s

      raw = case @mode
            when :executor
              # Default: Use autonomous executor with pattern selection
              Executor.call(text, pattern: self.class.current_pattern)
            when :stages
              # Legacy: Stage-based pipeline
              @stages.reduce(Result.ok(input)) do |result, stage|
                stage_name = stage.class.name&.split("::")&.last || stage.class.name
                result.and_then(stage_name) { |data| stage.call(data) }
              end
            when :direct
              # Simple: Direct LLM call with system context
              sys = ExecutionContext.build_system_message(include_commands: false) rescue nil
              if sys
                LLM.ask(text, messages: [{ role: "system", content: sys }], stream: true)
              else
                LLM.ask(text, stream: true)
              end
            else
              raise ArgumentError, "Unknown pipeline mode: #{@mode}"
            end

      normalize_result(raw, text)
    end

    private

    def normalize_result(result, input_text = nil)
      return result if result.err?

      v = result.value
      return result unless v.is_a?(Hash)

      # Normalize known keys
      normalized = {
        response: v[:response] || v[:answer] || v[:content],
        rendered: v[:rendered],
        model: v[:model],
        cost: v[:cost],
        tokens_in: v[:tokens_in],
        tokens_out: v[:tokens_out],
        pattern: v[:pattern],
        steps: v[:steps],
        history: v[:history],
      }.compact

      # Apply typography rendering if we have a response but no rendered version
      if normalized[:response] && !normalized[:rendered]
        normalized[:rendered] = strip_tool_blocks(normalized[:response])
      elsif normalized[:rendered]
        normalized[:rendered] = strip_tool_blocks(normalized[:rendered])
      end

      # Pressure-pass: structured adversarial questioning to harden final answer quality.
      pressure = run_pressure_pass(input_text, normalized[:rendered] || normalized[:response])
      if pressure
        normalized[:pressure_pass] = pressure
        normalized[:response] = pressure[:selected_answer] if pressure[:selected_answer]
        normalized[:rendered] = pressure[:selected_answer] if pressure[:selected_answer]
      end

      # Preserve any custom keys from the original value
      v.each do |key, val|
        normalized[key] = val unless normalized.key?(key)
      end

      Result.ok(normalized)
    end

    # Strip tool invocation blocks from LLM output so users see only the summary
    def strip_tool_blocks(text)
      return text unless text.is_a?(String)

      # Remove ```sh/```ruby blocks containing tool calls (file_read, file_write, shell_exec, etc)
      tool_names = "file_read|file_write|shell_exec|browse_page|analyze_code|fix_code|search_code"
      cleaned = text.gsub(/```(?:sh|ruby|bash|shell)?\n\s*(?:#{tool_names})\b.*?```/m, "")

      # Remove tool output blocks: bare ``` blocks immediately after a tool call removal (>10 lines)
      cleaned.gsub!(/```\n(?:[^\n]*\n){10,}```/m) { |block| lines = block.count("\n"); "[#{lines} lines omitted]" }

      # Remove standalone tool call lines
      cleaned.gsub!(/^\s*(?:#{tool_names})\s+["'].+$/m, "")

      # Collapse triple+ newlines to double
      cleaned.gsub!(/\n{3,}/, "\n\n")

      cleaned.strip
    end

    def run_pressure_pass(user_input, candidate_text)
      return nil unless pressure_pass_enabled?
      return nil unless defined?(LLM) && LLM.respond_to?(:configured?) && LLM.configured?
      return nil unless candidate_text.is_a?(String) && !candidate_text.strip.empty?
      return nil unless user_input.is_a?(String) && !user_input.strip.empty?

      schema = {
        type: "object",
        additionalProperties: false,
        required: %w[counterargument failure_modes alternatives selected_index selected_answer rationale],
        properties: {
          counterargument: { type: "string" },
          failure_modes: { type: "array", minItems: 2, items: { type: "string" } },
          alternatives: { type: "array", minItems: 2, items: { type: "string" } },
          selected_index: { type: "integer", minimum: 0 },
          selected_answer: { type: "string" },
          rationale: { type: "string" },
        },
      }

      prompt = <<~PROMPT
        You are an adversarial reviewer. Treat this as hostile scrutiny.
        The goal is stronger truthfulness and utility, not aggression for its own sake.

        User request:
        #{user_input.to_s[0, 4000]}

        Candidate answer:
        #{candidate_text.to_s[0, 6000]}

        Perform serial pressure testing:
        1) Strongest counterargument against the candidate answer.
        2) Concrete failure modes or risks.
        3) Produce at least 2 improved alternative answers.
        4) Choose the best one and explain why.

        Constraints:
        - Keep alternatives concise and actionable.
        - No markdown fences.
        - selected_answer must be the final answer to return to the user.
      PROMPT

      result = LLM.ask_json(prompt, schema: schema, tier: :strong, stream: false)
      return nil unless result&.ok?

      parsed = normalize_pressure_payload(result.value[:content])
      return nil unless parsed.is_a?(Hash)

      selected = parsed[:selected_answer].to_s.strip
      return nil if selected.empty?

      {
        counterargument: parsed[:counterargument].to_s,
        failure_modes: Array(parsed[:failure_modes]).map(&:to_s),
        alternatives: Array(parsed[:alternatives]).map(&:to_s),
        selected_index: parsed[:selected_index].to_i,
        selected_answer: selected,
        rationale: parsed[:rationale].to_s,
      }
    rescue StandardError
      nil
    end

    def normalize_pressure_payload(payload)
      case payload
      when Hash
        payload.transform_keys { |k| k.to_s.to_sym }
      when String
        parsed = JSON.parse(payload)
        parsed.is_a?(Hash) ? parsed.transform_keys { |k| k.to_s.to_sym } : nil
      else
        nil
      end
    rescue StandardError
      nil
    end

    def pressure_pass_enabled?
      val = ENV.fetch("MASTER_PRESSURE_PASS", "true").to_s.strip.downcase
      !%w[0 false off no].include?(val)
    end

    class << self
      include PipelineRepl

      def prompt
        begin
          segments = [
            "master",
            LLM.prompt_model_name,
            LLM.tier,
            git_info
          ].map { |s| s.to_s.strip }.reject(&:empty?)
          "#{segments.join(" ")} > "
        rescue StandardError
          "master > "
        end
      end

      def git_info
        # Detect git branch and dirty status
        require "timeout"
        branch = Timeout.timeout(2) do
          IO.popen(%w[git rev-parse --abbrev-ref HEAD], err: [:child, :out]) { |io| io.read.strip }
        end
        return nil if branch.empty? || $?.exitstatus != 0

        # Check for uncommitted changes
        status = Timeout.timeout(2) do
          IO.popen(%w[git status --porcelain], err: [:child, :out]) { |io| io.read }
        end
        dirty = !status.empty? && $?.exitstatus == 0

        dirty_indicator = dirty ? "*" : ""
        "#{branch}#{dirty_indicator}"
      rescue Timeout::Error, StandardError
        nil
      end

      def format_tokens(n)
        MASTER::Utils.format_tokens(n)
      end

      def format_meta(value)
        parts = []
        parts << "#{value[:tokens_in]}+#{value[:tokens_out]}tok" if value[:tokens_in]
        parts << UI.currency_precise(value[:cost]) if value[:cost]
        parts.join(" ")
      end

      def show_exit_summary(session)
        cost = session.total_cost
        msgs = session.message_count
        puts UI.dim("#{msgs}msg #{UI.currency(cost)}")
      end

      def pipe
        require "json"
        input = JSON.parse($stdin.read, symbolize_names: true)
        result = new.call(input)

        if result.ok?
          puts JSON.generate(result.value)
          exit 0
        else
          warn JSON.generate({ error: result.failure })
          exit 1
        end
      rescue JSON::ParserError => e
        warn JSON.generate({ error: "Invalid JSON: #{e.message}" })
        exit 1
      end
    end
  end
end
