# frozen_string_literal: true

require "ruby_llm"
require "digest"

module Master
  class Agent
    DEFAULT_MESSAGE_WINDOW_SIZE = 16
    COST_PER_TOKEN              = 0.000_015
    CACHE_WINDOW                = 4
    VISITOR_ALLOWED_TOOLS       = %w[AskLlm WebSearch].freeze

    def self.build_tool_capable_re
      yml_path = File.join(Master::ROOT, "data", "models.yml")
      prefixes = Master.load_yaml(yml_path).fetch("tool_capable_prefixes", [])
      escaped = prefixes.map { |p| Regexp.escape(p) }
      Regexp.new("\\A(?:#{escaped.join("|")})(?:[:\\/@\\-.].+)?\\z", Regexp::IGNORECASE).freeze
    end

    TOOL_CAPABLE_RE   = build_tool_capable_re.freeze
    NEMOTRON3_RE      = /nemotron-3/i.freeze
    LLAMA_NEMOTRON_RE = /llama.*nemotron|nemotron.*llama/i.freeze

    LLM_TOOL_MAP = {
      Tools::ReadFile        => Tools::LLM::ReadFile,
      Tools::WriteFile       => Tools::LLM::WriteFile,
      Tools::StrReplace      => Tools::LLM::StrReplace,
      Tools::ListDir         => Tools::LLM::ListDir,
      Tools::SearchFiles     => Tools::LLM::SearchFiles,
      Tools::Shell           => Tools::LLM::Shell,
      Tools::WebSearch       => Tools::LLM::WebSearch,
      Tools::AskLlm          => Tools::LLM::AskLlm,
      Tools::GitContext      => Tools::LLM::GitContext,
      Tools::AstEdit         => Tools::LLM::AstEdit,
      Tools::SearchKnowledge => Tools::LLM::SearchKnowledge,
      Tools::FeedbackRecord  => Tools::LLM::FeedbackRecord,
      Tools::Postpro         => Tools::LLM::Postpro,
      Tools::Repligen        => Tools::LLM::Repligen
    }.freeze

    def initialize(config:, session:, tools:, circuit_breaker:, cache:,
                   event_bus: nil, model_router: nil, reasoning_modes: nil,
                   memory: nil, personality: nil, code_index: nil, context_window: nil,
                   homeostat: nil)
      @config, @session, @tools          = config, session, tools
      @circuit_breaker, @cache, @bus     = circuit_breaker, cache, event_bus
      @model_router, @reasoning_modes    = model_router, reasoning_modes
      @memory, @personality, @code_index = memory, personality, code_index
      @context_window, @homeostat        = context_window, homeostat
    end

    def chat(message, stream: true, escalation_depth: 0, &blk)
      prepare_chat_turn(message)
      candidate_models = routed_models
      prompt   = apply_reasoning_mode(message)
      context  = conversation_context
      @bus&.publish("llm:request", model: candidate_models.first, tokens: message.bytesize / Session::TOKENS_PER_CHAR)

      rate_err = check_rate_limit
      return rate_err if rate_err

      response = attempt_chat_with_fallbacks(candidate_models:, prompt:, context:, stream:, &blk)
      return response if response.respond_to?(:err?) && response.err?
      response = maybe_escalate(response, message, stream:, escalation_depth:, &blk)

      text = response.to_s
      @session.add_message(role: :assistant, content: text)
      Result.ok(text)
    rescue StandardError => chat_error
      Result.err("agent: #{chat_error.message}", category: :handler_exception)
    end

    def prepare_chat_turn(message)
      @context_window&.check_and_compact!
      @tools.each { |t| t.reset! if t.respond_to?(:reset!) }
      @session.add_message(role: :user, content: message)
    end

    def check_rate_limit
      @circuit_breaker.check_rate!
      nil
    rescue CircuitBreaker::CircuitError => err
      Result.err(err.message, category: err.category)
    end

    def ask(prompt, context: nil, operation: nil)
      messages = Array(context) + [{ role: "user", content: apply_reasoning_mode(prompt) }]
      selected_model = operation ? model_for(operation:) : routed_models.first
      result = send_with_cache(selected_model, messages, stream: false)
      raise result.message if result.respond_to?(:err?) && result.err?
      result.to_s
    end

    def ask_once(prompt, system: nil, model: nil)
      result = send_with_cache(model || self.model, [{ role: "user", content: prompt.to_s }], system:, stream: false)
      result.ok? ? result.value!.to_s : ""
    end

    def call(ctx)
      on_chunk = ctx[:on_chunk]
      task_type = ctx[:task_type]&.to_s
      with_task_type(task_type) do
        on_chunk ? chat(ctx[:message].to_s, stream: true, &on_chunk) : chat(ctx[:message].to_s)
      end
    end

    def model = routed_models.first
    def model=(val)
      @config["model"] = val
    end

    def model_for(operation:)
      @model_router&.constrained_for(operation:) || model
    end

    def wire_context_window(ctx_window)
      @context_window = ctx_window
    end

    private

    def with_task_type(type)
      return yield unless type && !type.empty?
      old = @config["task_type"]
      @config["task_type"] = type
      yield
    ensure
      @config["task_type"] = old
    end

    def apply_reasoning_mode(message)
      return message unless @reasoning_modes
      @reasoning_modes.wrap(message, mode: @config.reasoning_mode)
    end

    def system_prompt
      parts = []
      parts << @personality.system_prompt if @personality
      parts << @code_index.summary if @code_index&.built?
      parts << @memory.context_summary if @memory&.context_summary
      parts.empty? ? nil : parts.join("\n\n")
    end

    def conversation_context(max_messages: DEFAULT_MESSAGE_WINDOW_SIZE)
      messages = @session.messages
      return [] unless messages.respond_to?(:each)
      messages.last(max_messages + 1)[0...-1] || []
    end

    def attempt_chat_with_fallbacks(candidate_models:, prompt:, context:, stream:, &blk)
      capable = select_capable_models(candidate_models)
      return capable if capable.respond_to?(:err?) && capable.err?

      last_response = nil
      capable.each_with_index do |selected_model, index|
        response = send_with_cache(
          selected_model,
          context + [{ role: "user", content: prompt }],
          stream:, &blk
        )
        last_response = response
        publish_llm_success(selected_model, response) if response.respond_to?(:ok?) && response.ok?
        break response unless response.respond_to?(:err?) && response.err? && index < capable.length - 1
      end
      last_response
    end

    def select_capable_models(candidates)
      capable = candidates.select { |m| claude_cli_model?(m) || tool_capable?(m) }
      return Result.err("no tool-capable model available", category: :validation) if capable.empty?
      capable
    end

    def publish_llm_success(model, response)
      @bus&.publish("llm:response", model:, success: true, tokens_approx: response.to_s.bytesize / Session::TOKENS_PER_CHAR)
    end

    def maybe_escalate(last_response, original_message, stream:, escalation_depth:, &blk)
      return last_response unless @model_router
      return last_response if escalation_depth >= 2

      current = routed_models.first
      escalation_model = @model_router.escalate_if_low_confidence(
        last_response.to_s,
        current_model: current,
        task_type: @config.task_type.to_sym
      )
      return last_response unless escalation_model

      @bus&.publish("llm:escalation", from: current, to: escalation_model)
      escalated = chat(
        original_message, stream: stream,
        escalation_depth: escalation_depth + 1, &blk
      )
      escalated.respond_to?(:err?) && escalated.err? ? last_response : escalated
    end

    def send_with_cache(selected_model, messages, system: nil, stream: false, &blk)
      cache_key = cache_key_for(messages.last[:content], messages[0...-1])
      breaker_for(selected_model).call(estimate_cost(messages.last[:content])) {
        @cache.fetch(cache_key, selected_model) {
          send_llm_request(selected_model, messages, system: system, stream: stream, &blk)
        }
      }
    rescue CircuitBreaker::CircuitError => err
      Result.err(err.message, category: err.category)
    rescue StandardError => err
      Result.err("llm_request: #{err.message}", category: :llm_call_failure)
    end

    def send_llm_request(selected_model, messages, system: nil, stream: false, &blk)
      if claude_cli_model?(selected_model)
        return send_claude_cli(selected_model.delete_prefix("claude-cli:"), messages, sys: system || system_prompt)
      end
      if web_chat_model?(selected_model)
        return send_web_chat(selected_model.delete_prefix("web-chat:"), messages, sys: system || system_prompt)
      end
      send_ruby_llm(selected_model, messages, sys: system || system_prompt, stream:, &blk)
    end

    def send_claude_cli(model_alias, messages, sys:)
      require "open3"
      args = ["claude", "--print", "--model", model_alias]
      args += ["--system-prompt", sys] if sys && !sys.empty?
      out, err, status = Open3.capture3(*args, stdin_data: text_prompt_for(messages))
      return Result.err("claude-cli: #{err.strip}", category: :provider_error) unless status.success?
      Result.ok(out.strip)
    rescue StandardError => e
      Result.err("claude-cli: #{e.message}", category: :provider_error)
    end

    def send_web_chat(provider, messages, sys:)
      Result.ok(WebChat.call(provider: provider, prompt: text_prompt_for(messages), system: sys))
    rescue StandardError => e
      Result.err("web-chat: #{e.message}", category: :provider_error)
    end

    def text_prompt_for(messages)
      prompt  = messages.last[:content].to_s
      context = messages[0...-1].map { |m| "#{m[:role]}: #{m[:content]}" }.join("\n\n")
      context.empty? ? prompt : "#{context}\n\nuser: #{prompt}"
    end

    def send_ruby_llm(selected_model, messages, sys:, stream:, &blk)
      chat_session = RubyLLM.chat(model: selected_model)
      final_sys = nemotron_system_prompt(selected_model, sys)
      chat_session.with_instructions(final_sys) if final_sys
      messages.each { |msg|
        chat_session.add_message(role: msg[:role].to_s, content: msg[:content].to_s)
      }

      available_tools = llm_tools(selected_model)
      chat_session.with_tools(*available_tools) unless available_tools.empty?

      reply = if stream && blk
        chat_session.ask(messages.last[:content]) { |chunk|
          blk.call(chunk.content.to_s) if chunk.content
        }
      else
        chat_session.ask(messages.last[:content])
      end
      Result.ok(extract_response(reply, selected_model))
    end

    def routed_models
      return [@config.model] unless @model_router
      @model_router.fallback_chain(task_type: @config.task_type.to_sym)
    rescue StandardError => e
      @bus&.publish("llm:route_error", error: e.message)
      [@config.model]
    end

    def breaker_for(model_id)
      @circuit_breaker.respond_to?(:for) ? @circuit_breaker.for(model_id) : @circuit_breaker
    end

    def claude_cli_model?(model_id) = model_id.to_s.start_with?("claude-cli:")
    def web_chat_model?(model_id) = model_id.to_s.start_with?("web-chat:")

    def tool_capable?(model_id)
      TOOL_CAPABLE_RE.match?(model_id.to_s.downcase)
    end

    def extract_response(reply, selected_model)
      return reply.to_s unless reply.respond_to?(:content)
      if NEMOTRON3_RE.match?(selected_model) && reply.respond_to?(:reasoning_content)
        thinking = reply.reasoning_content.to_s.strip
        content = reply.content.to_s
        return thinking.empty? ? content : "#{content}\n\n<think>\n#{thinking}\n</think>"
      end
      reply.content.to_s
    end

    def nemotron_system_prompt(selected_model, base = nil)
      sys = base || system_prompt
      return sys unless LLAMA_NEMOTRON_RE.match?(selected_model)
      thinking_on = @config["reasoning_mode"] != "none"
      directive = thinking_on ? "detailed thinking on" : "detailed thinking off"
      [directive, sys].compact.join("\n\n")
    end

    def cache_key_for(message, context)
      return Digest::SHA256.hexdigest(message) if context.empty?
      window = context.last(CACHE_WINDOW).map { |msg|
        "#{msg[:role]}:#{msg[:content]}"
      }.join("\n")
      Digest::SHA256.hexdigest("#{message}\n#{window}")
    end

    def estimate_cost(prompt)
      (prompt.bytesize / Session::TOKENS_PER_CHAR) * COST_PER_TOKEN
    end

    def llm_tools(selected_model = model)
      return [] unless tool_capable?(selected_model)
      return build_llm_tools(visitor: true) if Thread.current[:master_visitor]
      @llm_tools ||= build_llm_tools
    end

    def build_llm_tools(visitor: false)
      @tools.filter_map do |tool|
        wrapper = LLM_TOOL_MAP[tool.class]
        next nil unless wrapper
        next nil if visitor && !VISITOR_ALLOWED_TOOLS.include?(tool.class.name.split("::").last)
        wrapper.new(tool)
      end
    rescue StandardError => err
      @bus&.publish("agent:llm_tools_error", error: err.message)
      []
    end
  end
end
