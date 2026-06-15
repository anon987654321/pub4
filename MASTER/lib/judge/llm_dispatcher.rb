# frozen_string_literal: true

require "ruby_llm"
require "digest"
require "json"
require "open3"
require_relative "llm_dispatcher/react_loop"
require_relative "llm_dispatcher/ruby_llm_sender"
require_relative "llm_dispatcher/tool_registry"

module Master
  module Judge
    class LLMDispatcher
      COST_PER_TOKEN = 0.000_015
      CACHE_READ_RATIO = 0.10
      CACHE_WRITE_RATIO = 1.25
      CACHE_WINDOW = 4
      REACT_MAX_STEPS = 8
      MS_PER_SECOND = 1000
      CLAUDE_RE = /\Aclaude-|anthropic\/claude/i.freeze
      NEMOTRON3_RE = /nemotron-3/i.freeze
      LLAMA_NEMOTRON_RE = /llama.*nemotron|nemotron.*llama/i.freeze
      TOOL_CALL_RE = /<tool_call>(.*?)<\/tool_call>/m.freeze
      TOOL_RESULT_ROLE = "user"
      KEY_PATTERNS = [
        /sk-[A-Za-z0-9_\-]{16,}/,
        /sk-ant-[A-Za-z0-9_\-]{16,}/,
        /Bearer\s+[A-Za-z0-9_\-\.]{16,}/i,
        /\b[A-Za-z0-9]{32,}\b/
      ].freeze

      LLM_TOOL_MAP = {
        Reach::ReadFile => Reach::LLM::ReadFile,
        Reach::WriteFile => Reach::LLM::WriteFile,
        Reach::StrReplace => Reach::LLM::StrReplace,
        Reach::ListDir => Reach::LLM::ListDir,
        Reach::SearchFiles => Reach::LLM::SearchFiles,
        Reach::Shell => Reach::LLM::Shell,
        Reach::WebSearch => Reach::LLM::WebSearch,
        Reach::AskLlm => Reach::LLM::AskLlm,
        Reach::GitContext => Reach::LLM::GitContext,
        Reach::AstEdit => Reach::LLM::AstEdit,
        Reach::SearchKnowledge => Reach::LLM::SearchKnowledge,
        Reach::FeedbackRecord => Reach::LLM::FeedbackRecord,
        Reach::MemoryRecord => Reach::LLM::MemoryRecord,
        Reach::Repligen => Reach::LLM::Repligen,
        Reach::Postpro => Reach::LLM::Postpro
      }.freeze

      def self.build_tool_capable_re
        yml_path = File.join(Master::ROOT, "data", "models.yml")
        prefixes = Master.load_yaml(yml_path).fetch("tool_capable_prefixes", [])
        escaped = prefixes.map { |p| Regexp.escape(p) }
        Regexp.new("\\A(?:#{escaped.join("|")})(?:[:\\/@\\-.].+)?\\z", Regexp::IGNORECASE).freeze
      end

      TOOL_CAPABLE_RE = build_tool_capable_re.freeze

      include ReactLoop
      include RubyLLMSender
      include ToolRegistry

      def initialize(deps:, system_prompt:)
        @config, @cache, @circuit_breaker = deps.config, deps.cache, deps.circuit_breaker
        @tools, @bus, @system_prompt_proc = deps.tools, deps.bus, system_prompt
        @model_router = deps.model_router
        @session = deps.session
        @tool_registry = load_tool_registry
      end

      def send_with_cache(selected_model, messages, system: nil, stream: false, image: nil, &blk)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        if !image.nil? && image != ""
          # auto bias to vision free models (e.g. gemini-2.0-flash-exp:free) when image in ctx
          unless selected_model.to_s =~ /gemini|vision|claude-3|gpt-4o/
            selected_model = "z-ai/glm-4.5-air:free"
          end
        end
        cache_key = cache_key_for(messages.last[:content], messages[0...-1], selected_model)
        result = breaker_for(selected_model).call(estimate_cost(messages.last[:content])) do
          @cache.fetch(cache_key, selected_model) do
            send_llm_request(selected_model, messages, system:, stream:, image: image, &blk)
          end
        end
        record_provider_result(model: selected_model, result:, started:)
        result
      rescue Reach::CircuitBreaker::CircuitError => err
        record_provider_outcome(selected_model, err.category, latency_ms: elapsed_ms(started), error: err.message)
        Result.err(redact_secrets(err.message), category: err.category)
      rescue StandardError => err
        record_provider_outcome(selected_model, :llm_call_failure, latency_ms: elapsed_ms(started), error: err.message)
        return Result.err(Master.no_api_key_message, category: :no_api_key) if missing_key_error?(err)
        Result.err(redact_secrets(err.message.to_s), category: :llm_call_failure)
      end

      def redact_secrets(text)
        out = text.to_s
        KEY_PATTERNS.each { |re| out = out.gsub(re, "[REDACTED]") }
        out
      end

      def missing_key_error?(err)
        error_message = err.message.to_s
        error_message.match?(/missing configuration/i) ||
          error_message.match?(/api[_\- ]?key/i) ||
          error_message.match?(/unauthorized/i) ||
          error_message.match?(/401/) ||
          !Master.any_api_key_present?
      end

      def claude_cli_model?(model_id) = model_id.to_s.start_with?("claude-cli:")
      def web_chat_model?(model_id)   = model_id.to_s.start_with?("web-chat:")
      def tool_capable?(model_id)     = TOOL_CAPABLE_RE.match?(model_id.to_s.downcase)
      def claude_model?(model_id)     = CLAUDE_RE.match?(model_id.to_s)

      private

      def system_prompt
        result = @system_prompt_proc.call
        return result unless result.is_a?(Hash)
        [result[:static], result[:dynamic]].compact.join("\n\n").then { |s| s.empty? ? nil : s }
      end

      def send_llm_request(selected_model, messages, system: nil, stream: false, image: nil, &blk)
        sys = system || system_prompt
        return send_claude_cli(selected_model.delete_prefix("claude-cli:"), messages, sys:) if claude_cli_model?(selected_model)
        return send_web_chat(selected_model.delete_prefix("web-chat:"), messages, sys:)     if web_chat_model?(selected_model)
        if !tool_capable?(selected_model) && @tools.any?
          return react_tool_loop(selected_model, messages, sys:, stream:, image: image, &blk)
        end
        send_ruby_llm(selected_model, messages, sys:, stream:, image: image, &blk)
      end

      def send_claude_cli(model_alias, messages, sys:)
        args = ["claude", "--print", "--model", model_alias]
        args += ["--system-prompt", sys] if sys && !sys.empty?
        out, err, status = Open3.capture3(*args, stdin_data: text_prompt_for(messages))
        return Result.err("claude-cli: #{err.strip}", category: :provider_error) unless status.success?
        Result.ok(out.strip)
      rescue StandardError => e
        Result.err("claude-cli: #{e.message}", category: :provider_error)
      end

      def send_web_chat(provider, messages, sys:)
        Result.ok(WebChat.call(provider:, prompt: text_prompt_for(messages), system: sys))
      rescue StandardError => e
        Result.err("web-chat: #{e.message}", category: :provider_error)
      end

      def breaker_for(model_id)
        @circuit_breaker.respond_to?(:for) ? @circuit_breaker.for(model_id) : @circuit_breaker
      end

      def cache_key_for(message, context, model = nil)
        parts = model ? "#{model}\n#{message}" : message
        return Digest::SHA256.hexdigest(parts) if context.empty?
        window = context.last(CACHE_WINDOW).map { |msg| "#{msg[:role]}:#{msg[:content]}" }.join("\n")
        Digest::SHA256.hexdigest("#{parts}\n#{window}")
      end

      def estimate_cost(prompt)
        Master::Trace::Session.estimate_tokens(prompt) * COST_PER_TOKEN
      end

      def elapsed_ms(started)
        return 0 unless started
        ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * MS_PER_SECOND).round
      end

      def record_provider_result(model:, result:, started:)
        latency_ms = elapsed_ms(started)
        if Result.wrap(result).ok?
          record_provider_outcome(model, :success, latency_ms:)
        else
          record_provider_outcome(model, failure_status(result), latency_ms:,
                                  error: result.respond_to?(:message) ? result.message : result.to_s)
        end
      end

      def failure_status(result)
        cat = result.respond_to?(:category) ? result.category : :provider_error
        case cat
        when :rate_limit then :rate_limit
        when :timeout then :timeout
        when :budget then :quota_exceeded
        when :provider_error then :provider_error
        else :failure
        end
      end

      def record_provider_outcome(model, status, latency_ms: nil, error: nil)
        @model_router&.record_provider_outcome(model:, status:, latency_ms:, error:)
        @bus&.publish("llm:provider_outcome", model:, status:, latency_ms:, error:)
      rescue StandardError => e
        @bus&.publish("provider_health:record_error", model:, error: e.message)
      end

    end
  end
end
