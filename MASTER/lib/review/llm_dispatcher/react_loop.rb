# frozen_string_literal: true

module Master
  module Review
    class LLMDispatcher
      module ReactLoop
        private

        # Emulates function calling for models that lack native tool support.
        # Injects a text-format tool schema into the system prompt; parses <tool_call> XML
        # from responses; executes tools directly; loops until no calls remain.
        def react_tool_loop(selected_model, messages, sys:, stream:, image: nil, &blk)
          react_sys = build_react_system(sys)
          history = messages.dup
          last = nil

          REACT_MAX_STEPS.times do |step|
            result, done = react_step(step, selected_model:, history:, react_sys:, stream:, image:, blk:)
            return result if result.err?

            last = result
            break if done
          end

          last || Result.err("react: no response generated", category: :llm_call_failure)
        end

        def react_step(step, selected_model:, history:, react_sys:, stream:, image:, blk:)
          img = (step.zero? ? image : nil)
          result = send_ruby_llm(selected_model, history, sys: react_sys, stream: step.zero? ? stream : false, image: img, &(step.zero? ? blk : nil))
          return [result, true] if result.err?

          text = result.to_s
          calls = parse_tool_calls(text)
          return [result, true] if calls.empty?

          @bus&.publish("react:tool_calls", model: selected_model, step:, count: calls.size)
          history << { role: "assistant", content: text }
          tool_results = calls.map { |c| execute_react_tool(c["name"], c["args"] || {}) }
          history << { role: TOOL_RESULT_ROLE, content: tool_results.join("\n\n") }
          [result, false]
        end

        def build_react_system(base_sys)
          schema = @tools.filter_map do |t|
            name = t.class.name.split("::").last
            meta = @tool_registry.fetch(name, {})
            next unless tool_available_for_context?(meta)
            desc = meta["description"] || name.gsub(/([A-Z])/, ' \1').strip
            "- #{name}: #{desc}"
          end.join("\n")

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
          rescue JSON::ParserError => e
            Master::Ground::Swallow.log(e, context: "ReactLoop.parse_tool_calls")
            nil
          end
        end

        def execute_react_tool(name, args)
          tool = @tools.find { |t| t.class.name.split("::").last == name }
          return "<tool_result name=\"#{name}\">error: tool not found</tool_result>" unless tool
          runtime = tool.class.const_defined?(:NAME) ? tool.class::NAME : name
          unless Ground::SubagentContext.permits?(name) && Ground::SubagentContext.permits?(runtime)
            return "<tool_result name=\"#{name}\">error: tool denied for subagent #{Ground::SubagentContext.active_type}</tool_result>"
          end
          unless Ground::Tool::Profile.allow?(name) && Ground::Tool::Profile.allow?(runtime)
            return "<tool_result name=\"#{name}\">error: tool denied</tool_result>"
          end

          sym_args = args.transform_keys(&:to_sym)
          raw = tool.respond_to?(:call) ? tool.call(**sym_args) : "unsupported"
          out = Result.wrap(raw).value_or(raw.to_s)
          "<tool_result name=\"#{name}\">\n#{out}\n</tool_result>"
        rescue StandardError => e
          "<tool_result name=\"#{name}\">error: #{e.message}</tool_result>"
        end

        def text_prompt_for(messages)
          prompt = messages.last[:content].to_s
          context = messages[0...-1].map { |m| "#{m[:role]}: #{m[:content]}" }.join("\n\n")
          context.empty? ? prompt : "#{context}\n\nuser: #{prompt}"
        end
      end
    end
  end
end
