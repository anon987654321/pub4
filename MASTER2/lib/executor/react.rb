# frozen_string_literal: true

module MASTER
  class Executor
    # ReAct pattern implementation
    # Tight thought-action-observation loop
    # Best for: exploratory tasks, dynamic adaptation, unknown territory
    module React
      # ═══════════════════════════════════════════════════════════════════════════
      # PATTERN 1: ReAct - Tight thought-action-observation loop
      # Best for: exploratory tasks, dynamic adaptation, unknown territory
      # ═══════════════════════════════════════════════════════════════════════════
      
      def execute_react(goal, tier:)
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        while @step < @max_steps
          # Check wall clock timeout
          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
          if elapsed > WALL_CLOCK_LIMIT_SECONDS
            best_answer = @history.last&.[](:observation) || "Timed out"
            return Result.err("Timed out after #{elapsed.round}s (#{@step} steps). Last observation: #{best_answer[0..200]}")
          end

          @step += 1

          context = build_context(goal)
          
          result = LLM.ask(context, tier: tier)
          unless result.ok?
            return Result.err("LLM error at step #{@step}: #{result.error}")
          end

          parsed = parse_response(result.value[:content])
          record_history({ step: @step, thought: parsed[:thought], action: parsed[:action] })

          # Show progress
          UI.dim("  💭 #{@step}: #{parsed[:thought][0..80]}...")
          UI.dim("  🔧 #{parsed[:action][0..60]}")

          # Check for completion
          if parsed[:action] =~ /^(ANSWER|DONE|COMPLETE):/i
            answer = parsed[:action].sub(/^(ANSWER|DONE|COMPLETE):\s*/i, "")
            return Result.ok(
              answer: answer,
              steps: @step,
              pattern: :react,
              history: @history
            )
          end

          # Execute tool and get observation
          observation = execute_tool(parsed[:action])
          @history.last[:observation] = observation

          UI.dim("  📊 #{observation[0..100]}...")
        end

        Result.err("Max steps (#{@max_steps}) reached without completion")
      end

      def build_context(goal)
        config = self.class.system_prompt_config
        
        # Core identity and rules
        identity = if config["identity"]
          config["identity"] % { version: MASTER::VERSION, platform: RUBY_PLATFORM, ruby_version: RUBY_VERSION }
        else
          "You are MASTER v#{MASTER::VERSION}, an autonomous coding assistant."
        end
        
        rules = (config["rules"] || []).map { |r| "- #{r}" }.join("\n")
        
        # Available tools
        tools_desc = TOOLS.map { |name, desc| "- #{name}: #{desc}" }.join("\n")
        
        # Recent history
        history_str = if @history.empty?
          "This is the first step."
        else
          @history.last(5).map do |h|
            "Step #{h[:step]}: Thought: #{h[:thought]}\nAction: #{h[:action]}\nObservation: #{h[:observation]}"
          end.join("\n\n")
        end
        
        <<~PROMPT
          #{identity}
          
          #{rules}
          
          TOOLS:
          #{tools_desc}
          
          HISTORY:
          #{history_str}
          
          TASK: #{goal}
          
          Respond with:
          Thought: [your reasoning]
          Action: [tool_name: arguments] OR ANSWER: [final answer]
        PROMPT
      end

      def parse_response(text)
        thought = text[/Thought:\s*(.+?)(?=Action:|$)/mi, 1]&.strip || ""
        action = text[/Action:\s*(.+?)(?=Observation:|$)/mi, 1]&.strip || ""
        
        { thought: thought, action: action }
      end
    end
  end
end
