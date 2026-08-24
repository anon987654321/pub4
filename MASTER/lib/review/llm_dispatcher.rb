# frozen_string_literal: true

require "ruby_llm"
require "digest"
require "json"
require "open3"
require "timeout"
require_relative "llm_dispatcher/react_loop"
require_relative "llm_dispatcher/ruby_llm_sender"
require_relative "llm_dispatcher/tool_registry"

module Master
  module Review
    class LLMDispatcher
      COST_PER_TOKEN = 0.000_015
      CACHE_READ_RATIO = 0.10
      CACHE_WRITE_RATIO = 1.25
      CACHE_WINDOW = 4
      REACT_MAX_STEPS = 8
      MS_PER_SECOND = 1000
      # 60 was below the floor for the work the council does — not tight, but
      # unreachable. Measured 2026-07-31 on this machine, `claude --print
      # --model sonnet` against a 5KB code-review prompt (a SMALL one by council
      # standards, 120 lines and no persona system prompt):
      #
      #   one call, nothing else running   134s, 115s, 114s
      #   two concurrent                   118s, both finished
      #   four concurrent (MAX_CONCURRENT) 203s wall, one call still unfinished
      #                                    when a 200s outer timeout killed it
      #
      # A single persona could not answer inside 60s with the machine otherwise
      # idle, so every council was decided by whichever two personas the
      # scheduler happened to favour. That is what "quorum not reached (2/26)"
      # was: not disagreement, not an outage, just a stopwatch set below the
      # length of the task.
      #
      # 300 covers the four-concurrent case with headroom. MASTER_CLAUDE_CLI_TIMEOUT
      # still overrides it. Note the shape of those numbers if this needs tuning
      # again: going from two concurrent to four roughly doubles per-call
      # latency for the same total throughput, so MAX_CONCURRENT buys nothing
      # here and costs margin.
      CLAUDE_CLI_TIMEOUT_S = 300
      CLAUDE_RE = /\Aclaude-|anthropic\/claude/i.freeze
      VISION_RE = /gemini-[12]|claude|gpt-4o|gpt-4\.1|llama-4|qwen.*vl|pixtral|gemma-[34]|vision/i.freeze
      NON_VISION_RE = /glm|nemotron|deepseek(?!.*vl)|qwen3-next|gpt-oss|phi-4/i.freeze
      NEMOTRON3_RE = /nemotron-3/i.freeze
      LLAMA_NEMOTRON_RE = /llama.*nemotron|nemotron.*llama/i.freeze
      TOOL_CALL_RE = /<tool_call>(.*?)<\/tool_call>/m.freeze
      TOOL_RESULT_ROLE = "user"
      LLM_TOOL_MAP = {
        Io::ReadFile => Io::LLM::ReadFile,
        Io::WriteFile => Io::LLM::WriteFile,
        Io::StrReplace => Io::LLM::StrReplace,
        Io::ListDir => Io::LLM::ListDir,
        Io::SearchFiles => Io::LLM::SearchFiles,
        Io::Shell => Io::LLM::Shell,
        Io::WebSearch => Io::LLM::WebSearch,
        Io::WebFetch => Io::LLM::WebFetch,
        Io::AskLlm => Io::LLM::AskLlm,
        Io::GitContext => Io::LLM::GitContext,
        Io::AstEdit => Io::LLM::AstEdit,
        Io::SearchKnowledge => Io::LLM::SearchKnowledge,
        Io::FeedbackRecord => Io::LLM::FeedbackRecord,
        Io::MemoryRecord => Io::LLM::MemoryRecord,
        Io::SubdomainOrchestrator => Io::LLM::SubdomainOrchestrator,
        Io::DynamicHttp => Io::LLM::DynamicHttp,
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

      # Every LLM call in the tree arrives here — ideation, the council, the
      # semantic rules, the fix loop. With no provider key each one fails slowly
      # somewhere below, so a /through pass sat at "crit0 deliberation" for ten
      # minutes and printed nothing. One refusal, at the one door.
      def send_with_cache(selected_model, messages, system: nil, stream: false, image: nil, temperature: nil, &blk)
        return Result.err(Master.no_api_key_message, category: :no_api_key) unless Master.any_api_key_present?

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        selected_model = forced_model || selected_model
        selected_model = vision_model_for(selected_model) if image_present?(image)
        cache_key = cache_key_for(messages.last[:content], messages[0...-1], selected_model, system, temperature)
        result = breaker_for(selected_model).call(estimate_cost(messages.last[:content])) do
          @cache.fetch(cache_key, selected_model) do
            send_llm_request(selected_model, messages, system:, stream:, image:, temperature:, &blk)
          end
        end
        # The circuit breaker returns provider failures as Err(:provider_error)
        # rather than raising, so the rescue below never sees them — and
        # :provider_error is deliberately not failover-eligible (a transient
        # 5xx wants in-place retry). Billing and rate refusals are not
        # transient; measured 2026-08-20: an out-of-credit call arrives here
        # as :provider_error and no lane ever walked.
        result = reclassify_provider_error(result)
        record_provider_result(model: selected_model, result:, started:)
        result
      rescue Io::CircuitBreaker::CircuitError => err
        record_provider_outcome(selected_model, err.category, latency_ms: elapsed_ms(started), error: err.message)
        Result.err(redact_secrets(err.message), category: err.category)
      rescue StandardError => err
        record_provider_outcome(selected_model, :llm_call_failure, latency_ms: elapsed_ms(started), error: err.message)
        classified_call_failure(err)
      end

      # Ground::Redactor owns the pattern list. It was copied here verbatim, and
      # a redaction list that exists twice is a list where the next pattern
      # added to one copy leaves the other still printing the key.
      def redact_secrets(text) = Ground::Redactor.text(text)

      # One model for every lane, for one run. Set MASTER_MODEL and the router's
      # choice is overridden at the single door every request passes through —
      # cheap, default, strong, vision, the council's personas and the fix
      # loop's consensus alike.
      #
      # It exists for the case where the machine running MASTER has credit with
      # one provider and not another. On vm23 and ai.brgen.no it is unset and
      # routing is unchanged; from a workstation with a Claude subscription,
      # `MASTER_MODEL=claude-cli:claude-opus-4-8` sends everything through the
      # local claude binary instead of OpenRouter.
      #
      # Deliberately not a config key: a setting that silently redirects every
      # model call belongs to a shell session, not to a file that deploys.
      def forced_model
        value = ENV["MASTER_MODEL"].to_s.strip
        return nil if value.empty?

        unless @forced_announced
          Master::Trace::Dmesg.status("llm0", "MASTER_MODEL=#{value} — every lane forced to this model")
          @forced_announced = true
        end
        value
      end

      def claude_cli_model?(model_id) = model_id.to_s.start_with?("claude-cli:")
      def web_chat_model?(model_id)   = model_id.to_s.start_with?("web-chat:")
      def tool_capable?(model_id)     = TOOL_CAPABLE_RE.match?(model_id.to_s.downcase)
      def claude_model?(model_id)     = CLAUDE_RE.match?(model_id.to_s)
      def vision_capable?(model_id)
        id = model_id.to_s
        return false if NON_VISION_RE.match?(id)
        VISION_RE.match?(id)
      end

      private

      # A billing or rate-limit refusal cannot succeed on an in-place retry,
      # and :llm_call_failure is not in fallback_policy.on — classified as
      # :budget / :rate_limit, the chain and the single-shot hop walk on.
      def classified_call_failure(err)
        return Result.err(Master.no_api_key_message, category: :no_api_key) if missing_key_error?(err)
        return Result.err(redact_secrets(err.message.to_s), category: :budget) if billing_error?(err)
        return Result.err(redact_secrets(err.message.to_s), category: :rate_limit) if rate_limit_error?(err)

        Result.err(redact_secrets(err.message.to_s), category: :llm_call_failure)
      end

      def reclassify_provider_error(result)
        return result unless result.is_a?(Master::Result::Err) && result.category == :provider_error
        return Master::Result.err(result.message, category: :budget) if billing_error?(result)
        return Master::Result.err(result.message, category: :rate_limit) if rate_limit_error?(result)

        result
      end

      def billing_error?(err)
        err.message.to_s.match?(/insufficient credits|credit balance|payment required|\b402\b|billing/i)
      end

      def rate_limit_error?(err)
        err.message.to_s.match?(/rate.?limit|too many requests|\b429\b/i)
      end

      def missing_key_error?(err)
        return false if Master.keyless_llm_enabled?
        error_message = err.message.to_s
        error_message.match?(/missing configuration/i) ||
          error_message.match?(/api[_\- ]?key/i) ||
          error_message.match?(/unauthorized/i) ||
          error_message.match?(/401/) ||
          !Master.any_api_key_present?
      end

      def image_present?(image)
        return false if image.nil?
        return !image.empty? if image.respond_to?(:empty?)
        image != ""
      end

      def vision_model_for(current)
        return current if vision_capable?(current)
        @model_router&.preferred(task_type: :vision) || current
      end

      def system_prompt
        result = @system_prompt_proc.call
        return result unless result.is_a?(Hash)
        [result[:static], result[:dynamic]].compact.join("\n\n").then { |s| s.empty? ? nil : s }
      end

      def send_llm_request(selected_model, messages, system: nil, stream: false, image: nil, temperature: nil, &blk)
        sys = system || system_prompt
        return send_claude_cli(selected_model.delete_prefix("claude-cli:"), messages, sys:) if claude_cli_model?(selected_model)
        return send_web_chat(selected_model.delete_prefix("web-chat:"), messages, sys:)     if web_chat_model?(selected_model)
        if !tool_capable?(selected_model) && @tools.any?
          return react_tool_loop(selected_model, messages, sys:, stream:, image:, &blk)
        end
        send_ruby_llm(selected_model, messages, sys:, stream:, image:, temperature:, &blk)
      end

      # At most two claude subprocesses at once, process-wide. The latency
      # table above CLAUDE_CLI_TIMEOUT_S measured it: two concurrent finish
      # together, four roughly double per-call latency for the same total
      # throughput — and the fix loop runs rule groups in threads, so the
      # 2026-08-20 proof run showed CLI calls dying empty-stderr under
      # four-way contention, opening the circuit. Callers block for a slot;
      # waiting beats thrashing.
      CLI_SLOTS = SizedQueue.new(2).tap { |queue| 2.times { queue << true } }

      def send_claude_cli(model_alias, messages, sys:)
        CLI_SLOTS.pop
        args = ["claude", "--print", "--model", model_alias]
        args += ["--system-prompt", sys] if sys && !sys.empty?
        timeout_s = claude_cli_timeout_s
        out, err, status = capture3_with_timeout(timeout_s, *args, stdin_data: text_prompt_for(messages))
        return Result.err("claude-cli: #{err.strip}", category: :provider_error) unless status.success?
        Result.ok(out.strip)
      rescue Timeout::Error
        Result.err("claude-cli: timed out after #{timeout_s}s", category: :timeout)
      rescue StandardError => e
        Result.err("claude-cli: #{e.message}", category: :provider_error)
      ensure
        CLI_SLOTS << true
      end

      def capture3_with_timeout(timeout_s, *cmd, stdin_data: nil)
        Open3.popen3(*cmd) do |stdin, stdout, stderr, wait_thr|
          stdin.write(stdin_data) if stdin_data
          stdin.close
          out_reader = Thread.new { stdout.read }
          err_reader = Thread.new { stderr.read }
          if wait_thr.join(timeout_s)
            [out_reader.value, err_reader.value, wait_thr.value]
          else
            terminate_subprocess(wait_thr)
            [stdout, stderr].each(&:close)
            out_reader.kill
            err_reader.kill
            raise Timeout::Error
          end
        end
      end

      def terminate_subprocess(wait_thr)
        return unless signal_process(wait_thr, "TERM")
        return if wait_thr.join(0.5)
        signal_process(wait_thr, "KILL", log_context: "LLMDispatcher.terminate_subprocess")
      end

      def signal_process(wait_thr, signal, log_context: nil)
        Process.kill(signal, wait_thr.pid)
        true
      rescue Errno::ESRCH => e
        Master::Ground::Swallow.log(e, context: log_context) if log_context
        false
      end

      def claude_cli_timeout_s
        Integer(ENV.fetch("MASTER_CLAUDE_CLI_TIMEOUT", CLAUDE_CLI_TIMEOUT_S.to_s))
      rescue ArgumentError
        CLAUDE_CLI_TIMEOUT_S
      end

      def send_web_chat(provider, messages, sys:)
        Result.ok(Io::WebChat.call(provider:, prompt: text_prompt_for(messages), system: sys))
      rescue StandardError => e
        Result.err("web-chat: #{e.message}", category: :provider_error)
      end

      def breaker_for(model_id)
        @circuit_breaker.respond_to?(:for) ? @circuit_breaker.for(model_id) : @circuit_breaker
      end

      # system must be part of the key: two calls can share the same message
      # text (e.g. Enhance's ask_once and the real turn's chat both receive
      # the identical user message) but mean entirely different requests
      # under different instructions — omitting it let one call's cached
      # completion serve back as the other's answer.
      def cache_key_for(message, context, model = nil, system = nil, temperature = nil)
        parts = model ? "#{model}\n#{message}" : message
        parts = "#{parts}\nsys:#{system}" if system
        parts = "#{parts}\ntemp:#{temperature}" if temperature
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
        Ground::ModelQuota.record(model) if status == :success
        unless status == :success
          Ground::ModelSkipCache.skip!(model, reason: error || status.to_s, category: status)
        end
        @model_router&.record_provider_outcome(model:, status:, latency_ms:, error:)
        @bus&.publish("llm:provider_outcome", model:, status:, latency_ms:, error:)
        Ground::KeyRotator.rotate_for(model) if %i[rate_limit quota_exceeded].include?(status)
      rescue StandardError => e
        @bus&.publish("provider_health:record_error", model:, error: e.message)
      end

    end
  end
end
