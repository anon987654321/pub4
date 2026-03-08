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
          thought: { type: "string", description: "Your step-by-step reasoning for this action" },
          tool:    { type: "string", description: "The tool to invoke (omit if providing final answer)" },
          args:    { type: "object", description: "Arguments to pass to the tool" },
          answer:  { type: "string", description: "The final answer to return to the user (omit if using a tool)" },
        },
      }.freeze

      def execute_react(goal, tier:)
        # Gist #8: Understand-before-act — scan files mentioned in goal before planning.
        understand_context(goal)

        run_step_loop(goal, @max_steps) do |step_num, plan|
          msgs = build_context_messages(goal)

          # Structured call: LLM returns typed JSON.
          llm_result = LLM.ask_json(
            msgs.last[:content],
            schema: STEP_SCHEMA,
            messages: [msgs.first],
            tier: tier,
          )

          return llm_result unless llm_result.ok?

          parsed = parse_step(llm_result.value[:content])
          record_history({ step: step_num, thought: parsed[:thought], action: parsed[:action] })

          # Update plan
          plan.add(parsed[:thought][0..80]) if plan.size < step_num
          plan.start(step_num - 1)
          UI.dim("  #{step_num}: #{parsed[:thought][0..80]}")

          # Completion: answer field is set
          if parsed[:answer]
            plan.complete(step_num - 1)
            return Result.ok(
              answer:  parsed[:answer],
              steps:   step_num,
              pattern: :react,
              history: @history,
              plan:    plan.to_dmesg,
            )
          end

          tool_name = parsed[:tool]
          if tool_name.nil?
            # No tool and no answer on step 1 -- likely malformed JSON; retry once.
            if step_num == 1 && parsed[:thought] == "Continuing"
              UI.dim("  retrying (empty response)...")
              @step = 0
              next :continue
            end
            # No tool and no answer -- treat thought as final response
            return Result.ok(answer: parsed[:thought], steps: step_num, pattern: :react, history: @history)
          end

          # Human-readable preamble before each tool call (Gist #12)
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
          UI.dim("  ... #{preamble}") if preamble
          UI.dim("  > #{tool_name}(#{parsed[:args].to_json[0..60]})")

          raw_observation = dispatch_typed(tool_name, parsed[:args] || {})

          # Injection defense: fail-closed on detected injection.
          return err if (err = injection_error_for(raw_observation, source: tool_name))

          # Tool Firewall: normalize raw output into structured Evidence.
          evidence    = ToolResult.normalize(tool_name, raw_observation)
          observation = evidence.to_prompt
          @history.last[:observation]   = observation
          @history.last[:evidence_hash] = evidence.content_hash

          UI.dim("  = #{observation.lines.first.to_s.strip[0..100]}")

          :continue
        end
      end

      private

      # Gist #8: Understand phase -- scan files mentioned in the goal before planning.
      def understand_context(goal)
        candidates = goal.scan(/[\w\/.]+\.rb/).uniq.first(4)
        return if candidates.empty?

        files_scanned = []
        candidates.each do |token|
          paths = [
            token,
            File.join(MASTER.root, token),
            File.join(MASTER.root, "lib", token),
          ]
          found = paths.find { |p| File.exist?(p) }
          next unless found

          content = File.read(found)[0..800]
          record_history({
            step:        0,
            thought:     "understand: read #{token}",
            action:      "file_read #{token}",
            observation: content,
          })
          files_scanned << token
        end

        return if files_scanned.empty?

        Output.progress("Scanned #{files_scanned.size} file(s): #{files_scanned.join(', ')}", source: "understand") if defined?(Output)
      end

      # Parse the JSON step response into a normalised hash.
      # Handles both Hash (already parsed by ask_json) and String fallback.
      def parse_step(payload)
        step_data = case payload
                    when Hash   then payload
                    when String
                      begin
                        JSON.parse(payload, symbolize_names: true)
                      rescue StandardError => e
                        Logging.warn("JSON parse failed in react step: #{e.message}", subsystem: "executor.react")
                        {}
                      end
                    else {}
                    end

        thought = step_data[:thought].to_s.strip.then { |v| v.empty? ? "Continuing" : v }
        tool    = step_data[:tool].to_s.strip
        tool    = nil if tool.empty? || tool == "none"
        args    = step_data[:args].is_a?(Hash) ? step_data[:args] : {}
        answer  = step_data[:answer].to_s.strip
        answer  = nil if answer.empty?

        action = if tool
                   "#{tool} #{args.to_json}"
                 else
                   (answer ? "ANSWER: #{answer}" : thought)
                 end

        { thought: thought, tool: tool, args: args, answer: answer, action: action }
      end

      # Dispatch a tool by name with a Hash of typed arguments.
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
      rescue StandardError => err
        "Tool error (#{tool_name}): #{err.message}"
      end
    end
  end
end
