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
          thought: { type: "string", description: Prompts.get(:react, :schema_thought) },
          tool: { type: "string", description: Prompts.get(:react, :schema_tool) },
          args: { type: "object", description: Prompts.get(:react, :schema_args) },
          answer: { type: "string", description: Prompts.get(:react, :schema_answer) },
        },
      }.freeze

      def execute_react(goal, tier:)
        start_time = MASTER::Utils.monotonic_now
        plan       = Plan.new

        # Gist #8: Understand-before-act (Gemini CLI 4-phase model).
        # Scan files mentioned in goal text before entering the planning loop.
        understand_context(goal)

        while @step < @max_steps
          return err if (err = timeout_error_for(start_time))

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

          # Update plan: add thought as a step and mark it in_progress
          plan.add(parsed[:thought][0..80]) if plan.size < @step
          plan.start(@step - 1)
          UI.dim("  #{@step}: #{parsed[:thought][0..80]}")
          Output.progress(plan.summary, source: "plan") if defined?(Output) && @step > 1

          # Completion: answer field is set
          if parsed[:answer]
            plan.complete(@step - 1)
            return Result.ok(
              answer: parsed[:answer],
              steps: @step,
              pattern: :react,
              history: @history,
              plan: plan.to_dmesg,
            )
          end

          tool_name = parsed[:tool]
          unless tool_name
            # No tool and no answer -- treat thought as final response
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
          UI.dim("  ... #{preamble}") if preamble

          # Dispatch typed tool call (args is already a Hash from JSON parse)
          raw_observation = dispatch_typed(tool_name, parsed[:args] || {})

          # Injection defense: halt loop on detected injection (gist item #3).
          # Sanitize-and-continue is insufficient -- abort with error instead.
          return err if (err = injection_error_for(raw_observation, source: tool_name))

          observation = raw_observation.to_s
          @history.last[:observation] = observation

          UI.dim("  = #{observation[0..100]}")
        end

        Result.err("Max steps (#{@max_steps}) reached without completion")
      end

      private

      # Gist #8: Understand phase -- scan files mentioned in the goal before planning.
      # Reads file content and adds it to history context so the first plan step
      # is grounded in actual code rather than hallucinated structure.
      def understand_context(goal)
        # Extract file-like tokens from goal text (e.g. lib/foo.rb, executor.rb)
        candidates = goal.scan(/[\w\/.]+\.rb/).uniq.first(4)
        return if candidates.empty?

        files_scanned = []
        candidates.each do |token|
          paths = [
            token,
            File.join(MASTER.root, token),
            File.join(MASTER.root, "lib", token),
          ]
          found = paths.find { |candidate_path| File.exist?(candidate_path) }
          next unless found

          content = File.read(found)[0..800]
          record_history({
            step: 0,
            thought: "understand: read #{token}",
            action: "file_read #{token}",
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
               when String then begin
                 JSON.parse(payload, symbolize_names: true)
               rescue StandardError
                 {}
               end
               else {}
               end

        thought = step_data[:thought].to_s.strip.then { |val| val.empty? ? "Continuing" : val }
        tool    = step_data[:tool].to_s.strip
        tool    = nil if tool.empty? || tool == "none"
        args    = step_data[:args].is_a?(Hash) ? step_data[:args] : {}
        answer  = step_data[:answer].to_s.strip
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
      rescue StandardError => err
        "Tool error (#{tool_name}): #{err.message}"
      end
    end
  end
end
