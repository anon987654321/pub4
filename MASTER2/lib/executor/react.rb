# frozen_string_literal: true

module MASTER
  class Executor
    module React
      # JSON schema for each step: thought + either tool call or final answer.
      # Structured output replaces fragile regex parsing of free-form LLM text.
      STEP_SCHEMA = {
        type: "object",
        additionalProperties: false,
        required: %w[thought],
        properties: {
          thought: { type: "string", description: "Brief reasoning about the next step" },
          tool: { type: "string", description: "Tool to invoke (omit when answering)" },
          args: { type: "object", description: "Named arguments for the tool" },
          answer: { type: "string", description: "Final answer (set this to complete the task)" },
        },
      }.freeze

      def execute_react(goal, tier:)
        start_time = MASTER::Utils.monotonic_now

        while @step < @max_steps
          begin
            check_timeout!(start_time)
          rescue Result::Error => e
            return Result.err(e.message)
          end

          @step += 1

          msgs = build_context_messages(goal)

          # Structured call: LLM returns typed JSON instead of free-form text.
          # Eliminates parsing failures from formatting variations (gist item #1).
          result = LLM.ask_json(
            msgs.last[:content],
            schema: STEP_SCHEMA,
            messages: [msgs.first],
            tier: tier,
          )

          return Result.err("LLM error at step #{@step}: #{result.error}") unless result.ok?

          parsed = parse_step(result.value[:content])
          record_history({ step: @step, thought: parsed[:thought], action: parsed[:action] })

          UI.dim("  #{@step}: #{parsed[:thought][0..80]}")

          # Completion: answer field is set
          if parsed[:answer]
            return Result.ok(
              answer: parsed[:answer],
              steps: @step,
              pattern: :react,
              history: @history,
            )
          end

          tool_name = parsed[:tool]
          unless tool_name
            # No tool and no answer — treat thought as final response
            return Result.ok(
              answer: parsed[:thought],
              steps: @step,
              pattern: :react,
              history: @history,
            )
          end

          UI.dim("  > #{tool_name}(#{parsed[:args].to_json[0..60]})")

          # Gist #12: Human-readable preamble before each tool call (Codex CLI "Responsiveness")
          preamble = case tool_name.to_s
                     when "file_read"      then "Reading #{parsed[:args][:path] || '...'}"
                     when "file_write"     then "Writing #{parsed[:args][:path] || '...'}"
                     when "analyze_code"   then "Analysing #{parsed[:args][:path] || 'code'}"
                     when "fix_code"       then "Applying fixes to #{parsed[:args][:path] || '...'}"
                     when "shell_command"  then "Running: #{(parsed[:args][:command] || '').to_s[0..60]}"
                     when "web_search"     then "Searching: #{(parsed[:args][:query] || '').to_s[0..60]}"
                     when "browse_page"    then "Browsing #{parsed[:args][:url] || '...'}"
                     when "council_review" then "Asking council..."
                     when "memory_search"  then "Searching memory: #{(parsed[:args][:query] || '').to_s[0..50]}"
                     end
          UI.dim("  … #{preamble}") if preamble

          # Dispatch typed tool call (args is already a Hash from JSON parse)
          raw_observation = dispatch_typed(tool_name, parsed[:args] || {})

          # Injection defense: halt loop on detected injection (gist item #3).
          # Sanitize-and-continue is insufficient — abort with error instead.
          sanitizer = if defined?(Security::InjectionGuard)
                        Security::InjectionGuard
                      else
                        (defined?(Security::Sanitizer) ? Security::Sanitizer : nil)
                      end
          if sanitizer && !sanitizer.safe?(raw_observation)
            return Result.err(
              "Injection attempt detected in tool response from '#{tool_name}'. Aborting.",
              category: :validation,
            )
          end

          observation = raw_observation.to_s
          @history.last[:observation] = observation

          UI.dim("  = #{observation[0..100]}")
        end

        Result.err("Max steps (#{@max_steps}) reached without completion")
      end

      private

      # Parse the JSON step response into a normalised hash.
      # Handles both Hash (already parsed by ask_json) and String fallback.
      def parse_step(payload)
        data = case payload
               when Hash   then payload
               when String then begin
                 JSON.parse(payload, symbolize_names: true)
               rescue StandardError
                 {}
               end
               else {}
               end

        thought = data[:thought].to_s.strip.then { |t| t.empty? ? "Continuing" : t }
        tool    = data[:tool].to_s.strip
        tool    = nil if tool.empty? || tool == "none"
        args    = data[:args].is_a?(Hash) ? data[:args] : {}
        answer  = data[:answer].to_s.strip
        answer  = nil if answer.empty?

        # Legacy: if no tool/answer but action key present (transitional fallback)
        action = if tool
                   "#{tool} #{args.to_json}"
                 else
                   (answer ? "ANSWER: #{answer}" : thought)
                 end

        { thought: thought, tool: tool, args: args, answer: answer, action: action }
      end

      # Dispatch a tool by name with a Hash of typed arguments.
      # Delegates to ToolDispatch which handles sanitization and safety checks.
      def dispatch_typed(tool_name, args)
        case tool_name.to_s
        when "ask_llm"        then ask_llm(args[:prompt] || args.values.first.to_s)
        when "web_search"     then web_search(args[:query] || args.values.first.to_s)
        when "browse_page"    then browse_page(args[:url] || args.values.first.to_s)
        when "file_read"      then file_read(args[:path] || args.values.first.to_s)
        when "file_write"     then file_write(args[:path].to_s, args[:content].to_s)
        when "analyze_code"   then analyze_code(args[:path] || args.values.first.to_s)
        when "fix_code"       then fix_code(args[:path] || args.values.first.to_s)
        when "shell_command"  then shell_command(args[:command] || args.values.first.to_s)
        when "code_execution" then code_execution(args[:code] || args.values.first.to_s)
        when "council_review" then council_review(args[:text] || args.values.first.to_s)
        when "memory_search"  then memory_search(args[:query] || args.values.first.to_s)
        when "self_test"      then self_test
        else "Unknown tool: #{tool_name}. Available: #{TOOLS.keys.join(', ')}"
        end
      rescue StandardError => e
        "Tool error (#{tool_name}): #{e.message}"
      end
    end
  end
end
