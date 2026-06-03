# frozen_string_literal: true

require "ruby_llm"
require "digest"
require "json"
require "open3"
require "tempfile"
require "base64"
require "securerandom"

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
        record_provider_result(selected_model, result, started)
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

      # ReactToolLoop — emulates function calling for models that lack native tool support.
      # Injects a text-format tool schema into the system prompt; parses <tool_call> XML
      # from responses; executes tools directly; loops until no calls remain.
      def react_tool_loop(selected_model, messages, sys:, stream:, image: nil, &blk)
        react_sys = build_react_system(sys)
        history   = messages.dup
        last      = nil

        REACT_MAX_STEPS.times do |step|
          img = (step.zero? ? image : nil)
          result = send_ruby_llm(selected_model, history, sys: react_sys, stream: step.zero? ? stream : false, image: img, &(step.zero? ? blk : nil))
          return result if result.err?

          text  = result.to_s
          calls = parse_tool_calls(text)
          last  = result
          break if calls.empty?

          @bus&.publish("react:tool_calls", model: selected_model, step:, count: calls.size)
          history << { role: "assistant", content: text }
          tool_results = calls.map { |c| execute_react_tool(c["name"], c["args"] || {}) }
          history << { role: TOOL_RESULT_ROLE, content: tool_results.join("\n\n") }
        end

        last || Result.err("react: no response generated", category: :llm_call_failure)
      end

      def build_react_system(base_sys)
        schema = @tools.filter_map { |t|
          name = t.class.name.split("::").last
          meta = @tool_registry.fetch(name, {})
          desc = meta["description"] || name.gsub(/([A-Z])/, ' \1').strip
          "- #{name}: #{desc}"
        }.join("\n")

        react_instructions = <<~INST.strip
          You have access to these tools. Call a tool with:
          <tool_call>{"name": "ToolName", "args": {"param": "value"}}</tool_call>

          Available tools:
          #{schema}

          Reason step-by-step. When finished, give your final answer without any <tool_call> blocks.
        INST

        [base_sys, react_instructions].compact.join("\n\n")
      end

      def parse_tool_calls(text)
        text.scan(TOOL_CALL_RE).filter_map do |match|
          JSON.parse(match.first.strip)
        rescue JSON::ParserError
          nil
        end
      end

      def execute_react_tool(name, args)
        tool = @tools.find { |t| t.class.name.split("::").last == name }
        return "<tool_result name=\"#{name}\">error: tool not found</tool_result>" unless tool
        sym_args = args.transform_keys(&:to_sym)
        raw = tool.respond_to?(:call) ? tool.call(**sym_args) : "unsupported"
        out = Result.wrap(raw).value_or(raw.to_s)
        "<tool_result name=\"#{name}\">\n#{out}\n</tool_result>"
      rescue StandardError => e
        "<tool_result name=\"#{name}\">error: #{e.message}</tool_result>"
      end

      def text_prompt_for(messages)
        prompt  = messages.last[:content].to_s
        context = messages[0...-1].map { |m| "#{m[:role]}: #{m[:content]}" }.join("\n\n")
        context.empty? ? prompt : "#{context}\n\nuser: #{prompt}"
      end

      def send_ruby_llm(selected_model, messages, sys:, stream:, image: nil, &blk)
        chat_session = RubyLLM.chat(model: selected_model)
        final_sys = build_final_system(selected_model, sys)
        chat_session.with_instructions(final_sys) if final_sys

        # Add prior context as plain text (vision is typically only for the current user turn)
        messages[0...-1].each do |message_entry|
          chat_session.add_message(role: message_entry[:role].to_s, content: message_entry[:content].to_s)
        end

        last_entry = messages.last || {}
        last_text = last_entry[:content].to_s

        available_tools = llm_tools(selected_model)
        chat_session.with_tools(*available_tools) unless available_tools.empty?

        ask_arg = last_text
        temp_file = nil
        if image && ( (!image[:path].to_s.empty? && File.file?(image[:path])) || !image[:data].to_s.empty? )
          # Prefer disk :path from chat token meta (postpro'd uploads). Robust Tempfile fallback for direct data.
          # Always ensure cleanup with ensure. Unique temp name.
          if !image[:path].to_s.empty? && File.file?(image[:path])
            attachment = RubyLLM::Attachment.new(image[:path], filename: (image[:name].to_s.empty? ? File.basename(image[:path]) : image[:name].to_s))
          else
            ext = (image[:mime].to_s =~ /png/i ? ".png" : (image[:mime].to_s =~ /webp/i ? ".webp" : ".jpg"))
            temp_file = Tempfile.new(["master_vision_#{SecureRandom.hex(4)}", ext])
            temp_file.binmode
            temp_file.write(Base64.strict_decode64(image[:data]))
            temp_file.rewind
            temp_file.close
            attachment = RubyLLM::Attachment.new(temp_file.path, filename: (image[:name].to_s.presence || "photo#{ext}"))
          end
          content = RubyLLM::Content.new(text: last_text, attachments: [attachment])
          ask_arg = content
        end

        begin
          reply = if stream && blk
                    chat_session.ask(ask_arg) { |chunk| blk.call(chunk.content.to_s) if chunk.content }
          else
            chat_session.ask(ask_arg)
          end
          record_usage(reply, selected_model)
          res = Result.ok(extract_response(reply, selected_model))
          res
        ensure
          if temp_file
            begin
              temp_file.close unless temp_file.closed?
              temp_file.unlink if File.exist?(temp_file.path)
            rescue StandardError
              # best effort cleanup of vision temp
            end
          end
        end
      end

      def record_usage(reply, model)
        return unless @session
        input = reply.respond_to?(:input_tokens) ? reply.input_tokens.to_i : 0
        output = reply.respond_to?(:output_tokens) ? reply.output_tokens.to_i : 0
        cached = reply.respond_to?(:cached_tokens) ? reply.cached_tokens.to_i : 0
        cache_write = reply.respond_to?(:cache_creation_tokens) ? reply.cache_creation_tokens.to_i : 0
        tokens = input + output
        if tokens.zero? && reply.respond_to?(:content)
          tokens = Master::Trace::Session.estimate_tokens(reply.content)
          return if tokens.zero?
          @session.record_cost((tokens * COST_PER_TOKEN).round(6), model:, tokens:)
          return
        end
        return if tokens.zero?
        regular = [input - cached - cache_write, 0].max
        cost = ((regular * COST_PER_TOKEN) +
                (cached * COST_PER_TOKEN * CACHE_READ_RATIO) +
                (cache_write * COST_PER_TOKEN * CACHE_WRITE_RATIO) +
                (output * COST_PER_TOKEN)).round(6)
        @session.record_cost(cost, model:, tokens:)
        @bus&.publish("llm:cost", model:, cost:, tokens:, cached:, cache_write:)
        @bus&.publish("cache:hit", model:, cached:, cache_write:) if cached.positive? || cache_write.positive?
      rescue StandardError => e
        @bus&.publish("cost:record_error", error: e.message)
      end

      def breaker_for(model_id)
        @circuit_breaker.respond_to?(:for) ? @circuit_breaker.for(model_id) : @circuit_breaker
      end

      def extract_response(reply, selected_model)
        return reply.to_s unless reply.respond_to?(:content)
        content  = reply.content.to_s
        thinking = reply.respond_to?(:thinking) ? reply.thinking&.text.to_s.strip : ""
        if NEMOTRON3_RE.match?(selected_model) && !thinking.empty?
          return content.empty? ? thinking : "#{content}\n\n<think>\n#{thinking}\n</think>"
        end
        content.empty? && !thinking.empty? ? thinking : content
      end

      def nemotron_system_prompt(selected_model, base = nil)
        sys = base || system_prompt
        return sys unless LLAMA_NEMOTRON_RE.match?(selected_model)
        directive = @config["reasoning_mode"] != "none" ? "detailed thinking on" : "detailed thinking off"
        [directive, sys].compact.join("\n\n")
      end

      def build_final_system(selected_model, sys)
        return sys unless claude_model?(selected_model)
        raw = @system_prompt_proc.call
        if raw.is_a?(Hash) && raw[:static]
          static_text = nemotron_system_prompt(selected_model, raw[:static])
          blocks = [{ type: "text", text: static_text, cache_control: { type: "ephemeral" } }]
          blocks << { type: "text", text: raw[:dynamic] } if raw[:dynamic]
          RubyLLM::Content::Raw.new(blocks)
        else
          base = nemotron_system_prompt(selected_model, sys)
          return base unless base.is_a?(String)
          RubyLLM::Content::Raw.new([{ type: "text", text: base, cache_control: { type: "ephemeral" } }])
        end
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

      def record_provider_result(model, result, started)
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
      rescue StandardError => e
        @bus&.publish("provider_health:record_error", model:, error: e.message)
      end

      def llm_tools(selected_model)
        return [] unless tool_capable?(selected_model)
        return build_llm_tools(visitor: true) if Fiber[:master_visitor]
        @llm_tools ||= build_llm_tools
      end

      def build_llm_tools(visitor: false)
        tier = @model_router&.tier_for_model(@config.model).to_s
        @tools.filter_map do |tool|
          wrapper = LLM_TOOL_MAP[tool.class]
          next unless wrapper
          name = tool.class.name.split("::").last
          meta = @tool_registry.fetch(name, {})
          next if visitor && meta["visitor"] != true
          next if tier == "cheap" && meta["tier"] == "dangerous"
          wrapper.new(tool)
        end
      rescue StandardError => err
        @bus&.publish("agent:llm_tools_error", error: err.message)
        []
      end

      def load_tool_registry
        path = File.join(Master::ROOT, "data", "tools.yml")
        rows = Master.load_yaml(path)
        return {} unless rows.is_a?(Array)
        rows.each_with_object({}) { |row, h| h[row["name"].to_s] = row if row.is_a?(Hash) }
      end
    end
  end
end
