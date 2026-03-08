# frozen_string_literal: true

require "English"
require_relative "pipeline/repl"
require_relative "pipeline/context"
require_relative "pressure_pass"

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
      Logging.dmesg_log("pipeline", message: "ENTER pipeline.call")
      text = input.is_a?(Hash) ? (input[:text] || input["text"]).to_s : input.to_s

      Logging.with_request_id do
        raw = case @mode
              when :executor then call_executor(text)
              when :stages
                # DEPRECATED: :stages mode will be removed in wave 3.
                # Use :executor mode (the default). This path is no longer tested.
                Logging.warn("pipeline: :stages mode is deprecated; switch to :executor",
                             subsystem: "Pipeline") if defined?(Logging)
                call_stages(input)
              when :direct   then call_direct(text)
              else call_executor(text)  # degrade to executor rather than raise
              end

        normalize_result(raw, text)
      end
    rescue StandardError => e
      Logging.dmesg_log("pipeline", message: "unhandled: #{e.message}")
      Result.err(e.message)
    end

    private

    def call_executor(text)
      # Guard must run even in executor mode to prevent dangerous ops
      guard_result = Stages::Guard.new.call({ text: text })
      return guard_result if guard_result.err?

      # Default: Use autonomous executor with pattern selection
      exec_result = Executor.call(text, pattern: self.class.current_pattern)

      # Gist #3: Lint post-flight so axiom violations are caught in executor mode too
      if exec_result.ok?
        response_text = exec_result.value[:answer] || exec_result.value[:response].to_s
        lint_result = Stages::Lint.new.call({ text: text, response: response_text })
        if lint_result.ok?
          lv = lint_result.value
          Logging.dmesg_log("pipeline",
                            message: "executor_lint violations=#{lv[:axiom_violations]&.size || 0}") if lv[:axiom_violations]&.any?

          # Security veto: check if any executor council_review step vetoed on security grounds
          steps = exec_result.value[:steps]
          steps = [] unless steps.is_a?(Array)
          security_veto = steps.any? do |s|
            s[:tool] == "council_review" &&
              s[:result].to_s.match?(/security|auth|injection|unsafe/i) &&
              s[:result].to_s.match?(/REJECT|veto/i)
          end

          exec_result = Result.ok(exec_result.value.merge(
                                    axiom_violations:      lv[:axiom_violations],
                                    zsh_violations:        lv[:zsh_violations],
                                    council_security_veto: security_veto,
                                  ))
        end
      end

      exec_result
    end

    def call_stages(input)
      # Legacy: Stage-based pipeline
      @stages.reduce(Result.ok(input)) do |result, stage|
        stage_name = stage.class.name&.split("::")&.last || stage.class.name
        result.and_then(stage_name) { |data| stage.call(data) }
      end
    end

    def call_direct(text)
      # Simple: Direct LLM call with system context
      sys = begin
        ExecutionContext.build_system_message(include_commands: false)
      rescue StandardError
        nil
      end
      if sys
        LLM.ask(text, messages: [{ role: "system", content: sys }], stream: true)
      else
        LLM.ask(text, stream: true)
      end
    end

    public

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

      # Pressure-pass: delegate to extracted PressurePass module
      pressure = PressurePass.review(user_input: input_text, candidate: normalized[:rendered] || normalized[:response])
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
      cleaned.gsub!(/```\n(?:[^\n]*\n){10,}```/m) do |block|
        lines = block.count("\n")
        UI.dim("[#{lines} lines omitted]")
      end

      # Remove standalone tool call lines
      cleaned.gsub!(/^\s*(?:#{tool_names})\s+["'].+$/m, "")

      # Collapse triple+ newlines to double
      cleaned.gsub!(/\n{3,}/, "\n\n")

      cleaned.strip
    end

    class << self
      include PipelineRepl

      def prompt(phase: nil)
        p = MASTER::UI.pastel
        parts = [p.bold.white("master")]
        git = git_info
        parts << git if git
        model = LLM.prompt_model_name.to_s.strip
        parts << p.blue(model) unless model.empty?
        parts << p.bright_black(phase) if phase
        cost = Session.current.total_cost
        parts << p.bright_black("$#{format('%.2f', cost)}") if cost && cost > 0
        "#{parts.join(p.bright_black(' · '))} #{p.bold.white('❯')} "
      rescue StandardError
        "master ❯ "
      end

      def git_info
        require "timeout"
        p = MASTER::UI.pastel
        branch = Timeout.timeout(2) do
          IO.popen(%w[git rev-parse --abbrev-ref HEAD], err: [:child, :out]) { |io| io.read.strip }
        end
        return nil if branch.empty? || $CHILD_STATUS.exitstatus != 0

        status = Timeout.timeout(2) do
          IO.popen(%w[git status --porcelain], err: [:child, :out], &:read)
        end
        dirty = !status.empty? && $CHILD_STATUS.exitstatus == 0

        dirty ? p.yellow("#{branch}✗") : p.white(branch)
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
        msgs = session.message_count
        return if msgs == 0

        cost = session.total_cost
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
