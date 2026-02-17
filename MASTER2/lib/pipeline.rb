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
      @stages = stages.map do |stage|
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
              Executor.call(text, pattern: self.class.current_pattern)
            end

      normalize_result(raw)
    end

    private

    def normalize_result(result)
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

    class << self
      include PipelineRepl

      def prompt
        # Starship-inspired multi-segment prompt
        # Line 1: Info bar with context segments
        # Line 2: Simple input prompt
        begin
          pastel = UI.pastel

          # Gather context
          model = LLM.prompt_model_name
          tier = LLM.tier
          budget = LLM.budget_remaining rescue Float::INFINITY
          tokens = Session.current.message_count rescue 0
          tripped = LLM.model_tiers[tier]&.any? { |m| !LLM.circuit_closed?(m) }

          # Build segments
          segments = []

          # Ruby version segment
          ruby_version = RUBY_VERSION
          segments << pastel.cyan("ruby #{ruby_version}")

          # Model + tier segment
          tier_label = tier ? "(#{tier})" : ""
          segments << pastel.yellow("#{model} #{tier_label}".strip)

          # Turn count
          if tokens > 0
            segments << "^#{format_tokens(tokens)}"
          end

          # Budget
          if budget < 10.0
            segments << "$#{format('%.2f', budget)}"
          end

          # Circuit breaker status
          status_icon = tripped ? pastel.red("tripped") : pastel.green("ok")
          segments << status_icon

          # Git branch (if in repo)
          git_segment = git_info
          segments << git_segment if git_segment

          # Build prompt
          sep = pastel.dim(" . ")
          info_line = "+- #{segments.join(sep)}"
          input_line = "+- master >>"

          "#{info_line}\n#{input_line}"
        rescue StandardError => e
          # Fallback to simple prompt on any error
          "master$ "
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
        UI.pastel.blue("#{branch}#{dirty_indicator}")
      rescue Timeout::Error, StandardError => e
        nil
      end

      def format_tokens(n)
        return "#{n}" if n < 1000
        return "#{(n / 1000.0).round(1)}k" if n < 1_000_000
        "#{(n / 1_000_000.0).round(1)}M"
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
