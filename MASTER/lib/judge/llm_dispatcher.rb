# frozen_string_literal: true

require "ruby_llm"
require "digest"
require "json"
require "open3"

module Master
  module Judge
    class LLMDispatcher
      COST_PER_TOKEN = 0.000_015
      CACHE_WINDOW = 4
      REACT_MAX_STEPS = 8
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
        Reach::MemoryRecord => Reach::LLM::MemoryRecord
      }.freeze

      def self.build_tool_capable_re
        yml_path = File.join(Master::ROOT, "data", "models.yml")
        prefixes = Master.load_yaml(yml_path).fetch("tool_capable_prefixes", [])
        escaped  = prefixes.map { |p| Regexp.escape(p) }
        Regexp.new("\\A(?:#{escaped.join("|")})(?:[:\\/@\\-.].+)?\\z", Regexp::IGNORECASE).freeze
      end

      TOOL_CAPABLE_RE = build_tool_capable_re.freeze

      def initialize(deps:, system_prompt:)
        @config, @cache, @circuit_breaker = deps.config, deps.cache, deps.circuit_breaker
        @tools, @bus, @system_prompt_proc = deps.tools, deps.bus, system_prompt
        @model_router  = deps.model_router
        @session       = deps.session
        @tool_registry = load_tool_registry
      end

      def send_with_cache(selected_model, messages, system: nil, stream: false, &blk)
        cache_key = cache_key_for(messages.last[:content], messages[0...-1], selected_model)
        breaker_for(selected_model).call(estimate_cost(messages.last[:content])) {
          @cache.fetch(cache_key, selected_model) {
            send_llm_request(selected_model, messages, system:, stream:, &blk)
          }
        }
      rescue Reach::CircuitBreaker::CircuitError => err
        Result.err(redact_secrets(err.message), category: err.category)
      rescue StandardError => err
        return Result.err(Master.no_api_key_message, category: :no_api_key) if missing_key_error?(err)
        Result.err(redact_secrets(err.message.to_s), category: :llm_call_failure)
      end

      def redact_secrets(text)
        out = text.to_s
        KEY_PATTERNS.each { |re| out = out.gsub(re, "[REDACTED]") }
        out
      end

      def missing_key_error?(err)
        msg = err.message.to_s
        msg.match?(/missing configuration/i) ||
          msg.match?(/api[_\- ]?key/i) ||
          msg.match?(/unauthorized/i) ||
          msg.match?(/401/) ||
          !Master.any_api_key_present?
      end

      def claude_cli_model?(model_id) = model_id.to_s.start_with?("claude-cli:")
      def web_chat_model?(model_id)   = model_id.to_s.start_with?("web-chat:")
      def tool_capable?(model_id)     = TOOL_CAPABLE_RE.match?(model_id.to_s.downcase)

      private

      def system_prompt = @system_prompt_proc.call

      def send_llm_request(selected_model, messages, system: nil, stream: false, &blk)
        sys = system || system_prompt
        return send_claude_cli(selected_model.delete_prefix("claude-cli:"), messages, sys:) if claude_cli_model?(selected_model)
        return send_web_chat(selected_model.delete_prefix("web-chat:"), messages, sys:)     if web_chat_model?(selected_model)
        if !tool_capable?(selected_model) && @tools.any?
          return react_tool_loop(selected_model, messages, sys:, stream:, &blk)
        end
        send_ruby_llm(selected_model, messages, sys:, stream:, &blk)
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
      def react_tool_loop(selected_model, messages, sys:, stream:, &blk)
        react_sys = build_react_system(sys)
        history   = messages.dup
        last      = nil

        REACT_MAX_STEPS.times do |step|
          result = send_ruby_llm(selected_model, history, sys: react_sys, stream: step.zero? ? stream : false, &(step.zero? ? blk : nil))
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

      def send_ruby_llm(selected_model, messages, sys:, stream:, &blk)
        chat_session = RubyLLM.chat(model: selected_model)
        final_sys    = nemotron_system_prompt(selected_model, sys)
        chat_session.with_instructions(final_sys) if final_sys
        messages.each { |msg| chat_session.add_message(role: msg[:role].to_s, content: msg[:content].to_s) }

        available_tools = llm_tools(selected_model)
        chat_session.with_tools(*available_tools) unless available_tools.empty?

        reply = if stream && blk
          chat_session.ask(messages.last[:content]) { |chunk| blk.call(chunk.content.to_s) if chunk.content }
        else
          chat_session.ask(messages.last[:content])
        end
        record_usage(reply, selected_model)
        Result.ok(extract_response(reply, selected_model))
      end

      def record_usage(reply, model)
        return unless @session
        input  = reply.respond_to?(:input_tokens)  ? reply.input_tokens.to_i  : 0
        output = reply.respond_to?(:output_tokens) ? reply.output_tokens.to_i : 0
        tokens = input + output
        if tokens.zero? && reply.respond_to?(:content)
          tokens = Master::Trace::Session.estimate_tokens(reply.content)
        end
        return if tokens.zero?
        @session.record_cost((tokens * COST_PER_TOKEN).round(6), model:, tokens:)
      rescue StandardError => e
        @bus&.publish("cost:record_error", error: e.message)
      end

      def breaker_for(model_id)
        @circuit_breaker.respond_to?(:for) ? @circuit_breaker.for(model_id) : @circuit_breaker
      end

      def extract_response(reply, selected_model)
        return reply.to_s unless reply.respond_to?(:content)
        if NEMOTRON3_RE.match?(selected_model) && reply.respond_to?(:reasoning_content)
          thinking = reply.reasoning_content.to_s.strip
          content  = reply.content.to_s
          return thinking.empty? ? content : "#{content}\n\n<think>\n#{thinking}\n</think>"
        end
        reply.content.to_s
      end

      def nemotron_system_prompt(selected_model, base = nil)
        sys = base || system_prompt
        return sys unless LLAMA_NEMOTRON_RE.match?(selected_model)
        directive = @config["reasoning_mode"] != "none" ? "detailed thinking on" : "detailed thinking off"
        [directive, sys].compact.join("\n\n")
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

      def llm_tools(selected_model)
        return [] unless tool_capable?(selected_model)
        return build_llm_tools(visitor: true) if Fiber[:master_visitor]
        @llm_tools ||= build_llm_tools
      end

      def build_llm_tools(visitor: false)
        tier = @model_router&.tier_for_model(@config.model).to_s
        @tools.filter_map do |tool|
          wrapper  = LLM_TOOL_MAP[tool.class]
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
