# frozen_string_literal: true

require "ruby_llm"

module Master
  class Agent
    DEFAULT_CONTEXT_SIZE = 16
    COST_PER_TOKEN       = 0.000_015

    # Replicate native API — these owner prefixes route through Bridges::Replicate.
    REPLICATE_OWNERS = %w[deepseek-ai mistralai xai meta-replicate].freeze

    # Tool-capable model whitelist — non-matching models raise at call time.
    TOOL_CAPABLE_MODELS = %w[
      claude gpt-4 gpt-4o gemini mistral mixtral
      llama-3.1 llama-3.3 qwen command-r deepseek
      meta/meta-llama anthropic/claude openai/gpt google/gemini
    ].freeze

    MAX_TOOL_TURNS    = 5
    TOOL_CALL_RE      = /(?:<use_tool>\s*(.*?)\s*<\/use_tool>|^ACTION:\s*(\{.*?\})\s*$|^TOOL:\s*(\{.*?\})\s*$)/m.freeze

    NEMOTRON3_RE      = /nemotron-3/i.freeze
    LLAMA_NEMOTRON_RE = /llama.*nemotron|nemotron.*llama/i.freeze

    def initialize(config:, session:, tools:, circuit_breaker:, cache:,
                   event_bus: nil, model_router: nil, reasoning_modes: nil,
                   memory: nil, personality: nil, code_index: nil)
      @code_index      = code_index
      @config          = config
      @session         = session
      @tools           = tools
      @circuit_breaker = circuit_breaker
      @cache           = cache
      @bus             = event_bus
      @model_router    = model_router
      @reasoning_modes = reasoning_modes
      @memory          = memory
      @personality     = personality
      configure_ruby_llm
    end

    def chat(message, stream: true, &blk)
      @session.add_message(role: :user, content: message)
      candidate_models = routed_models
      prompt           = apply_reasoning_mode(message)
      context          = conversation_context
      @bus&.publish("llm:request", model: candidate_models.first, tokens: message.bytesize / 4)

      last_response = attempt_chat_with_fallbacks(candidate_models, prompt, context, stream, &blk)

      return last_response if last_response.respond_to?(:err?) && last_response.err?

      last_response = maybe_escalate(last_response, prompt, context, message, stream, &blk)

      text = last_response.to_s
      @session.add_message(role: :assistant, content: text)
      Result.ok(text)
    rescue StandardError => chat_error
      Result.err("agent: #{chat_error.message}", category: :unknown)
    end

    def ask(prompt, context: nil)
      messages = Array(context) + [{ role: "user", content: apply_reasoning_mode(prompt) }]
      chat_direct(messages)
    end

    # One-shot chat with a custom system prompt. No session, no circuit breaker.
    # Routes through Replicate bridge when model owner is in REPLICATE_OWNERS.
    def ask_once(prompt, system: nil)
      if replicate_model?(model)
        reply = Bridges::Replicate.new.chat(
          model:    model,
          messages: [{ role: "user", content: prompt.to_s }],
          system:   system
        )
        return reply.content.to_s
      end
      raw_chat = RubyLLM.chat(model: model)
      raw_chat.with_instructions(system) if system
      reply = raw_chat.ask(prompt.to_s)
      reply.respond_to?(:content) ? reply.content.to_s : reply.to_s
    rescue StandardError => ask_error
      raise "chat_raw: #{ask_error.message}"
    end

    def call(ctx)
      on_chunk = ctx[:on_chunk]
      if on_chunk
        chat(ctx[:message].to_s, stream: true, &on_chunk)
      else
        chat(ctx[:message].to_s)
      end
    end

    def model = routed_models.first

    private

    def attempt_chat_with_fallbacks(candidate_models, prompt, context, stream, &blk)
      last_response = nil
      candidate_models.each_with_index do |selected_model, index|
        assert_tool_capable!(selected_model)
        cache_key = cache_key_for("#{selected_model}:#{prompt}", context)
        response  = @circuit_breaker.call(estimate_cost(prompt)) {
          @cache.fetch(cache_key, selected_model) { chat_with(prompt, selected_model, context:, stream:, &blk) }
        }
        last_response = response
        next if response.respond_to?(:err?) && response.err? && index < candidate_models.length - 1
        break response
      end
      last_response
    end

    def maybe_escalate(last_response, prompt, context, original_message, stream, &blk)
      return last_response unless @model_router && !@escalation_done

      escalation_model = @model_router.escalate_if_low_confidence(
        last_response.to_s,
        current_model: routed_models.first,
        task_type: @config.task_type.to_sym
      )
      return last_response unless escalation_model

      @escalation_done = true
      @bus&.publish("llm:escalation", from: routed_models.first, to: escalation_model)
      esc_cache_key    = cache_key_for("#{escalation_model}:#{prompt}", context)
      escalated_result = @circuit_breaker.call(estimate_cost(original_message)) {
        @cache.fetch(esc_cache_key, escalation_model) {
          chat_with(prompt, escalation_model, context: context, stream: stream, &blk)
        }
      }
      @escalation_done = false
      escalated_result.respond_to?(:err?) && escalated_result.err? ? last_response : escalated_result
    end

    def routed_models
      return [@config.model] unless @model_router
      @model_router.fallback_chain(task_type: @config.task_type.to_sym)
    rescue StandardError
      [@config.model]
    end

    def replicate_model?(model_id)
      return false unless ENV["REPLICATE_API_KEY"].to_s.length > 10
      REPLICATE_OWNERS.include?(model_id.to_s.split("/").first)
    end

    def assert_tool_capable!(selected_model)
      return if replicate_model?(selected_model)
      return if tool_capable?(selected_model)
      raise "Model '#{selected_model}' does not support function calling. " \
            "Set REPLICATE_API_KEY, ANTHROPIC_API_KEY, or OPENROUTER_API_KEY."
    end

    def tool_capable?(model_id)
      TOOL_CAPABLE_MODELS.any? { |pattern| model_id.to_s.downcase.include?(pattern.downcase) }
    end

    def apply_reasoning_mode(message)
      return message unless @reasoning_modes
      @reasoning_modes.wrap(message, mode: @config.reasoning_mode)
    end

    def system_prompt
      parts = []
      parts << @personality.system_prompt if @personality
      parts << @code_index.summary        if @code_index&.built?
      parts << @memory.context_summary    if @memory&.context_summary
      parts.empty? ? nil : parts.join("\n\n")
    end

    def configure_ruby_llm
      RubyLLM.configure do |config|
        config.anthropic_api_key  = ENV["ANTHROPIC_API_KEY"]  if ENV["ANTHROPIC_API_KEY"].to_s.length > 10
        config.openai_api_key     = ENV["OPENAI_API_KEY"]     if ENV["OPENAI_API_KEY"].to_s.length > 10
        config.gemini_api_key     = ENV["GEMINI_API_KEY"]     if ENV["GEMINI_API_KEY"].to_s.length > 10
        config.openrouter_api_key = ENV["OPENROUTER_API_KEY"] if ENV["OPENROUTER_API_KEY"].to_s.length > 10
      end
    end

    def chat_with(message, selected_model, context:, stream:, &blk)
      return chat_via_ferrum(selected_model, message) if selected_model.start_with?("ferrum:webchat:")
      return chat_via_replicate(selected_model, message, context, stream, &blk) if replicate_model?(selected_model)

      chat_via_ruby_llm(selected_model, message, context, stream, &blk)
    end

    def chat_via_ferrum(selected_model, message)
      alias_name = selected_model.split(":", 3).last
      response   = Bridges::FerrumWebChat.new.ask(model_alias: alias_name, prompt: message)
      response.respond_to?(:value!) ? response.value! : response.to_s
    end

    def chat_via_replicate(selected_model, message, context, stream, &blk)
      messages  = context + [{ role: "user", content: message }]
      do_stream = stream && blk ? true : false
      reply     = Bridges::Replicate.new.chat(
        model: selected_model, messages: messages, system: system_prompt,
        stream: do_stream, &(do_stream ? blk : nil)
      )
      blk&.call(reply.content.to_s) unless do_stream
      reply.content.to_s
    end

    def chat_via_ruby_llm(selected_model, message, context, stream, &blk)
      chat_session = RubyLLM.chat(model: selected_model)
      chat_session.with_instructions(nemotron_system_prompt(selected_model)) if system_prompt
      context.each { |msg| chat_session.add_message(role: msg[:role].to_s, content: msg[:content].to_s) }

      available_tools = llm_tools(selected_model)
      chat_session.with_tools(*available_tools) unless available_tools.empty?

      reply = if stream && blk
        chat_session.ask(message) { |chunk| blk.call(chunk.content.to_s) if chunk.content }
      else
        chat_session.ask(message)
      end
      extract_response(reply, selected_model)
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

    def nemotron_system_prompt(selected_model)
      base = system_prompt
      return base unless LLAMA_NEMOTRON_RE.match?(selected_model)
      thinking_on = @config["reasoning_mode"] != "none"
      directive   = thinking_on ? "detailed thinking on" : "detailed thinking off"
      [directive, base].compact.join("\n\n")
    end

    def conversation_context(max_messages: DEFAULT_CONTEXT_SIZE)
      messages = @session.messages
      return [] unless messages.respond_to?(:each)
      messages.last(max_messages + 1)[0...-1] || []
    end

    def cache_key_for(message, context)
      return message if context.empty?
      condensed = context.map { |msg| "#{msg[:role]}:#{msg[:content]}" }.join("\n")
      "#{message}\n\n[context]\n#{condensed}"
    end

    def chat_direct(messages)
      if replicate_model?(model)
        reply = Bridges::Replicate.new.chat(model: model, messages: messages, system: system_prompt)
        return reply.content.to_s
      end
      chat_session = RubyLLM.chat(model: model)
      chat_session.with_instructions(system_prompt) if system_prompt
      messages.each { |msg| chat_session.add_message(role: msg[:role].to_s, content: msg[:content].to_s) }
      chat_session.complete
    end

    def estimate_cost(prompt) = (prompt.bytesize / 4) * COST_PER_TOKEN

    LLM_TOOL_MAP = {
      Tools::ReadFile    => Tools::LLM::ReadFile,
      Tools::WriteFile   => Tools::LLM::WriteFile,
      Tools::StrReplace  => Tools::LLM::StrReplace,
      Tools::ListDir     => Tools::LLM::ListDir,
      Tools::SearchFiles => Tools::LLM::SearchFiles,
      Tools::Shell       => Tools::LLM::Shell,
      Tools::WebSearch   => Tools::LLM::WebSearch,
      Tools::AskLlm      => Tools::LLM::AskLlm,
      Tools::GitContext  => Tools::LLM::GitContext,
      Tools::AstEdit          => Tools::LLM::AstEdit,
      Tools::SearchKnowledge  => Tools::LLM::SearchKnowledge,
    }.freeze

    def llm_tools(selected_model = model)
      return [] unless tool_capable?(selected_model)
      @llm_tools ||= build_llm_tools
    end

    def build_llm_tools
      @tools.filter_map do |tool|
        wrapper = LLM_TOOL_MAP[tool.class]
        wrapper&.new(tool)
      end
    rescue StandardError => tools_error
      @bus&.publish("agent:llm_tools_error", error: tools_error.message)
      []
    end

    def react_loop(message, selected_model, context:, &blk)
      require "json"
      messages = context + [{ role: "user", content: message }]
      sys      = react_system_prompt
      bridge   = Bridges::Replicate.new

      MAX_TOOL_TURNS.times do
        reply = bridge.chat(model: selected_model, messages: messages, system: sys)
        text  = reply.content.to_s

        match = TOOL_CALL_RE.match(text)
        unless match
          blk&.call(text)
          return text
        end

        visible_text = text.sub(match[0], "").strip
        blk&.call(visible_text) unless visible_text.empty?

        json_str    = (match[1] || match[2] || match[3]).to_s.strip
        call_data   = JSON.parse(json_str, symbolize_names: true)
        tool_name   = call_data.delete(:tool).to_s
        tool_output = dispatch_tool(tool_name, call_data)

        messages << { role: "assistant", content: text }
        messages << { role: "user", content: "<tool_result tool=\"#{tool_name}\">\n#{tool_output}\n</tool_result>" }
      end

      final_reply = bridge.chat(model: selected_model, messages: messages, system: sys).content.to_s
      blk&.call(final_reply)
      final_reply
    rescue StandardError => react_error
      "react error: #{react_error.message}"
    end

    def react_system_prompt
      base  = system_prompt.to_s
      descs = tools_description
      return base if descs.empty?

      tool_block = "## Available Tools\n" \
                   "Output a tool call as a single line, then stop:\n" \
                   "<use_tool>{\"tool\":\"name\",\"arg\":\"val\"}</use_tool>\n" \
                   "A <tool_result> will be injected. Call one tool per turn.\n\n" +
                   descs

      base.empty? ? tool_block : "#{base}\n\n#{tool_block}"
    end

    def tools_description
      @tools.filter_map do |tool|
        next unless tool.class.const_defined?(:NAME)
        description = tool.class.const_defined?(:DESCRIPTION) ? tool.class::DESCRIPTION : ""
        "- #{tool.class::NAME}: #{description}"
      end.join("\n")
    rescue StandardError
      ""
    end

    def dispatch_tool(tool_name, args)
      tool = @tools.find { |candidate| candidate.class.const_defined?(:NAME) && candidate.class::NAME == tool_name }
      unless tool
        available = @tools.filter_map { |candidate| candidate.class::NAME rescue nil }.join(", ")
        return "error: unknown tool '#{tool_name}'. Available: #{available}"
      end
      tool_result = tool.call(**args.transform_keys(&:to_sym))
      @bus&.publish("tool:used", tool: tool_name)
      tool_result.respond_to?(:ok?) ? (tool_result.ok? ? tool_result.value!.to_s : "error: #{tool_result.message}") : tool_result.to_s
    rescue StandardError => dispatch_error
      "tool error: #{dispatch_error.message}"
    end

  end
end
