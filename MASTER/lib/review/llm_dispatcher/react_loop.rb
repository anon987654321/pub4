# frozen_string_literal: true

require "did_you_mean"

module Master
  module Review
    class LLMDispatcher
      module ReactLoop
        # Names models reach for when they guess a parameter. Renamed only when
        # the tool declares the target and not the guess, so no real key moves.
        ARG_ALIASES = {
          file_path: :path, filepath: :path, filename: :path, file: :path, dir: :path, directory: :path,
          cmd: :command, old_str: :old_string, old_text: :old_string, new_str: :new_string,
          new_text: :new_string, regex: :pattern, search: :pattern, q: :query
        }.freeze

        private

        # Emulates function calling for models that lack native tool support.
        # Injects a text-format tool schema into the system prompt; parses <tool_call> XML
        # from responses; executes tools directly; loops until no calls remain.
        def react_tool_loop(selected_model, messages, sys:, stream:, image: nil, &blk)
          react_sys = build_react_system(sys)
          history = messages.dup
          last = nil
          empty_rounds = 0

          REACT_MAX_STEPS.times do |step|
            result, done = react_step(step, selected_model:, history:, react_sys:, stream:, image:, blk:)
            return result if result.err?

            last = result
            break if done

            # data/rules.yml's empty_tool_response: two rounds in which every tool
            # answered nothing is a model calling into a void, not progress.
            empty_rounds = empty_tool_round?(history.last[:content]) ? empty_rounds + 1 : 0
            return empty_tool_failure(selected_model) if empty_rounds >= 2
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

        def empty_tool_round?(tool_results)
          tool_results.to_s.scan(%r{<tool_result name="[^"]*">(.*?)</tool_result>}m).all? { |(body)| body.strip.empty? }
        end

        def empty_tool_failure(selected_model)
          @bus&.publish("phantom:detected", patterns: ["empty_tool_response"], model: selected_model)
          Result.err("react: tools returned nothing twice in a row", category: :llm_failure)
        end

        def build_react_system(base_sys)
          schema = @tools.filter_map do |t|
            name = t.class.name.split("::").last
            meta = @tool_registry.fetch(name, {})
            next unless tool_available_for_context?(meta)
            desc = meta["description"] || name.gsub(/([A-Z])/, ' \1').strip
            "- #{name}#{param_signature(t)}: #{desc}"
          end.join("\n")

          react_instructions = <<~INST.strip
            You have access to these tools. Call a tool with:
            <tool_call>{"name": "ToolName", "args": {"param": "value"}}</tool_call>

            Available tools (* marks a required parameter):
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

        def execute_react_tool(requested, args)
          tool = find_react_tool(requested)
          return unknown_tool_result(requested) unless tool

          name = tool.class.name.split("::").last
          @bus&.publish("tool:healed", tool: name, from: requested, to: name) unless name == requested
          runtime = tool.class.const_defined?(:NAME) ? tool.class::NAME : name
          unless CLI::SubagentContext.permits?(name) && CLI::SubagentContext.permits?(runtime)
            return "<tool_result name=\"#{name}\">error: tool denied for subagent #{CLI::SubagentContext.active_type}</tool_result>"
          end
          unless Ground::Tool::Profile.allow?(name) && Ground::Tool::Profile.allow?(runtime)
            return "<tool_result name=\"#{name}\">error: tool denied</tool_result>"
          end

          out = invoke_react_tool(tool, args.transform_keys(&:to_sym))
          "<tool_result name=\"#{name}\">\n#{out}\n</tool_result>"
        rescue StandardError => e
          "<tool_result name=\"#{name}\">error: #{e.message}</tool_result>"
        end

        # Case, underscores and hyphens are spelling, not identity: a model
        # without native tools writes read_file or readFile for ReadFile. An exact
        # name wins; otherwise a name that folds onto exactly one tool reaches it,
        # and any other answers with the nearest names instead of a bare refusal.
        def find_react_tool(requested)
          exact = @tools.find { |tool| tool.class.name.to_s.split("::").last == requested }
          return exact if exact

          folded = fold_tool_name(requested)
          matches = @tools.select { |tool| react_tool_names(tool).any? { |known| fold_tool_name(known) == folded } }
          matches.first if matches.size == 1
        end

        def react_tool_names(tool)
          short = tool.class.name.to_s.split("::").last
          tool.class.const_defined?(:NAME) ? [short, tool.class::NAME] : [short]
        end

        def fold_tool_name(name) = name.to_s.downcase.delete("_-")

        def unknown_tool_result(requested)
          names = @tools.map { |tool| tool.class.name.to_s.split("::").last }.uniq
          near = DidYouMean::SpellChecker.new(dictionary: names).correct(requested.to_s).first(3)
          hint = near.empty? ? "" : "; nearest: #{near.join(", ")}"
          "<tool_result name=\"#{requested}\">error: tool not found#{hint}</tool_result>"
        end

        # Through the same RubyLLM wrapper a native tool call uses, so both paths
        # read one parameter list and one coercion: calling the Io tool directly
        # handed it names like SearchFiles' `path` that only the wrapper maps.
        def invoke_react_tool(tool, args)
          wrapper = LLM_TOOL_MAP[tool.class]
          unless wrapper
            raw = tool.respond_to?(:call) ? tool.call(**args) : "unsupported"
            return Result.wrap(raw).value_or(raw.to_s)
          end

          llm_tool = wrapper.new(tool, bus: @bus)
          reply = llm_tool.call(heal_args(llm_tool, args))
          return reply unless reply.is_a?(Hash) && reply[:error]

          "error: #{reply[:error]}; parameters are #{param_signature(tool)}"
        end

        def heal_args(llm_tool, args)
          declared = llm_tool.parameters.keys
          args.to_h do |key, value|
            target = ARG_ALIASES[key]
            next [key, value] unless target && !declared.include?(key) && declared.include?(target) && !args.key?(target)

            @bus&.publish("tool:healed", tool: llm_tool.class.name.split("::").last, from: key, to: target)
            [target, value]
          end
        end

        def param_signature(tool)
          wrapper = LLM_TOOL_MAP[tool.class]
          return "" unless wrapper

          "(#{wrapper.parameters.values.map { |param| "#{param.name}#{'*' if param.required}" }.join(', ')})"
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
