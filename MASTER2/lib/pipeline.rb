# frozen_string_literal: true

require "English"
require "digest"
require_relative "ui/repl"
require_relative "pipeline/context"
require_relative "refinement"
require_relative "pressure_pass"   # legacy alias (depends on Refinement)
require_relative "intent_classifier"
require_relative "output_guard"
require_relative "policy/enforcer"
require_relative "policy/profile"

module MASTER
  # Pipeline - Uses Executor with hybrid patterns
  class Pipeline
    DEFAULT_STAGES = %i[intake compress guard route council ask strunk lint render].freeze
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
      text = input.is_a?(Hash) ? input[:text] : input.to_s

      if text.bytesize > MAX_INPUT_LENGTH
        fp = Digest::SHA256.hexdigest(text)[0, 12]
        Logging.dmesg_log("pipeline", message: "input_too_large bytes=#{text.bytesize} fp=#{fp}")
        return Result.err("Input too large (#{text.bytesize} bytes). Please send a smaller chunk.", category: :input)
      end

      @intent = IntentClassifier.detect(text)
      @profile = Policy::Profile.apply(@intent)

      Logging.with_request_id do
        Thread.current[:master_intent] = @intent
        detect_context_shift(text)
        raw = if input.is_a?(Hash) && input[:image_data]
                call_with_image(text, input[:image_data], input[:image_mime], input[:image_name])
              else
                case @mode
                when :executor then call_executor(text)
                when :stages   then call_stages(input)
                when :direct   then call_direct(text)
                else call_executor(text)
                end
              end

        track_task(text)
        normalize_result(raw, text)
      end
    rescue StandardError => err
      Logging.dmesg_log("pipeline", message: "unhandled: #{err.message}")
      Result.err(err.message)
    end

    private

    def detect_context_shift(text)
      session = Session.current
      return unless session.active_task

      signals = defined?(NLU) ? NLU.classify_signals(text) : Set.new
      return unless signals.include?(:context_shift)

      session.set_task(nil)
      Logging.dmesg_log("session", message: "context shift detected -- task cleared") if defined?(Logging)
    end

    def track_task(text)
      session = Session.current
      return if session.active_task # already have one
      return if text.strip.length < 8

      # Use first 60 chars of input as the working task label
      session.set_task(text.strip.slice(0, 60))
    rescue StandardError
      nil
    end

    def call_executor(text)
      # Guard must run even in executor mode to prevent dangerous ops
      $stderr.print UI.dim("guard ") if defined?(UI)
      guard_result = Stages::Guard.new.call({ text: text })
      return guard_result if guard_result.err?

      # Default: Use autonomous executor with pattern selection
      $stderr.print UI.dim("→ llm ") if defined?(UI)
      exec_result = Executor.call(text, pattern: self.class.current_pattern)

      # Gist #3: Lint post-flight so axiom violations are caught in executor mode too
      if exec_result.ok?
        $stderr.print UI.dim("→ lint ") if defined?(UI)
        response_text = exec_result.value[:answer] || exec_result.value[:response].to_s
        lint_result = Stages::Lint.new.call({ text: text, response: response_text })
        if lint_result.ok?
          lv = lint_result.value
          lv_violations = lv[:axiom_violations]
          Thread.current[:last_axiom_violations] = lv_violations&.any? ? lv_violations : nil
          Logging.dmesg_log("pipeline",
                            message: "executor_lint violations=#{lv_violations&.size || 0}") if lv_violations&.any?

          # Security veto: check if any executor council_review step vetoed on security grounds
          steps = exec_result.value[:steps]
          steps = [] unless steps.is_a?(Array)
          security_veto = steps.any? do |s|
            next false unless s[:tool] == "council_review"
            review_signals = defined?(NLU) ? NLU.classify_signals(s[:result].to_s) : Set.new
            review_signals.include?(:security_concern) && s[:result].to_s.match?(/REJECT|veto/i)
          end

          exec_result = Result.ok(exec_result.value.merge(
                                    axiom_violations:      lv[:axiom_violations],
                                    zsh_violations:        lv[:zsh_violations],
                                    council_security_veto: security_veto,
                                  ))
        end

        # Auto-scan all code touched by this response
        exec_result = ReviewGate.run(exec_result, input: text)
      end

      exec_result
    end

    def call_with_image(text, image_data, image_mime, image_name)
      require "base64"
      require "stringio"
      raw_bytes = Base64.strict_decode64(image_data)
      io = StringIO.new(raw_bytes)
      io.instance_variable_set(:@path, image_name.to_s)
      def io.path; @path; end
      attachment = RubyLLM::Attachment.new(io, filename: image_name.to_s)
      LLM.ask_with_files(text, files: [attachment])
    rescue StandardError => err
      Logging.dmesg_log("pipeline", message: "image call failed: #{err.message}")
      LLM.ask(text, stream: true)
    end

    def call_stages(input)
      # Legacy: Stage-based pipeline
      @stages.reduce(Result.ok(input)) do |result, stage|
        stage_name = stage.class.name&.split("::")&.last || stage.class.name
        result.and_then(stage_name) { |data| stage.call(data) }
      end
    end

    def call_direct(text)
      # Direct LLM call with system context + session history
      sys = begin
        ExecutionContext.build_system_message(include_commands: false, depth: ExecutionContext.current_depth)
      rescue StandardError
        nil
      end
      prior = Session.current.context_for_llm(max_messages: 12)
      prior = prior.reject { |m| m[:role].to_s == "user" && m[:content].to_s.strip == text.strip }
      messages = sys ? [{ role: "system", content: sys }] + prior : prior
      LLM.ask(text, messages: messages, stream: true)
    end

    public

    def normalize_result(result, input_text = nil)
      return result if result.err?

      payload = result.value
      return result unless payload.is_a?(Hash)

      # Normalize known keys
      normalized = {
        response: payload[:response] || payload[:answer] || payload[:content],
        rendered: payload[:rendered],
        model: payload[:model],
        cost: payload[:cost],
        tokens_in: payload[:tokens_in],
        tokens_out: payload[:tokens_out],
        pattern: payload[:pattern],
        steps: payload[:steps],
        history: payload[:history],
      }.compact

      # Apply typography rendering if we have a response but no rendered version
      $stderr.print UI.dim("→ render") if defined?(UI)
      if normalized[:response] && !normalized[:rendered]
        cleaned = Stages::Strunk.new.call({ response: normalized[:response] })
        normalized[:response] = cleaned.ok? ? cleaned.value[:response] : normalized[:response]
        normalized[:rendered] = strip_tool_blocks(normalized[:response])
      elsif normalized[:rendered]
        cleaned = Stages::Strunk.new.call({ response: normalized[:rendered] })
        normalized[:rendered] = strip_tool_blocks(cleaned.ok? ? cleaned.value[:response] : normalized[:rendered])
      end

      # Refinement pass (was PressurePass)
      pressure = Refinement.review(user_input: input_text, candidate: normalized[:rendered] || normalized[:response])
      if pressure
        normalized[:refinement] = pressure
        normalized[:response] = pressure[:selected_answer] if pressure[:selected_answer]
        normalized[:rendered] = pressure[:selected_answer] if pressure[:selected_answer]
      end

      # Adversarial pass: question any code blocks in the response
      if defined?(AdversarialPass)
        candidate_text = normalized[:rendered] || normalized[:response]
        if candidate_text.is_a?(String) && candidate_text.match?(/```(?:ruby|sh|zsh)?\n/)
          code_blocks = candidate_text.scan(/```\w*\n(.+?)```/m).flatten
          code_blocks.each do |block|
            check = AdversarialPass.quick_check(block)
            if check[:critical]&.any?
              normalized[:adversarial_warnings] ||= []
              normalized[:adversarial_warnings].concat(check[:critical])
            end
          end
        end
      end

      # Preserve any custom keys from the original value
      payload.each do |key, val_item|
        normalized[key] = val_item unless normalized.key?(key)
      end

      # OutputGuard + PolicyEnforcer on the final human-facing text
      candidate = normalized[:rendered] || normalized[:response]
      if candidate.is_a?(String) && @intent
        guard_result = OutputGuard.check(mode: @intent, candidate_text: candidate)
        return guard_result if guard_result.err?

        enforcement = Policy::Enforcer.new.evaluate(mode: @intent, input: input_text, output: candidate)
        if enforcement.ok? && enforcement.value.is_a?(Hash)
          violations = enforcement.value[:policy_violations] || []
          normalized[:policy_violations] = violations unless violations.empty?
          unless enforcement.value[:ok]
            ids = violations.select { |v| v[:severity] == :hard }.map { |v| v[:id] }.join(", ")
            return Result.err("Policy violation(s): #{ids}", category: :policy)
          end
        end
      end

      $stderr.puts if defined?(UI) # end phase progress line
      Result.ok(normalized)
    end

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
      include Repl

      def prompt(phase: nil)
        p     = MASTER::UI.pastel
        model = LLM.prompt_model_name.to_s.strip
        model = model.empty? ? "?" : model
        badge = PlatformCheck.compute_badge
        hw    = badge ? p.bright_black("*#{badge}") : ""
        cost  = Session.current.total_cost
        cost_str = cost && cost > 0 ? p.bright_black("*#{format('%.0fc', cost * 100)}") : ""
        name  = Session.current.metadata_value(:name)
        ctx   = name ? p.bright_black("[#{name}]") : ""
        "#{p.bold.white('master')}#{p.bright_black('@')}#{p.cyan(model)}#{hw}#{cost_str}#{ctx}#{p.bold.white('$')} "
      rescue StandardError
        "master$ "
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

        dirty ? p.yellow("#{branch}!!") : p.white(branch)
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
      rescue JSON::ParserError => err
        warn JSON.generate({ error: "Invalid JSON: #{err.message}" })
        exit 1
      end
    end
  end
end
