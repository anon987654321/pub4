# frozen_string_literal: true

module MASTER
  class Executor
    # Pattern execution methods - ReAct, Pre-Act, ReWOO, Reflexion
    module Patterns
      # ═══════════════════════════════════════════════════════════════════════════
      # PATTERN 1: ReAct - Reasoning + Acting
      # Best for: exploratory tasks, unknown requirements, dynamic scenarios
      # ═══════════════════════════════════════════════════════════════════════════

      def execute_react(goal, tier:)
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        while @step < @max_steps
          # Check wall clock timeout
          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
          if elapsed > WALL_CLOCK_LIMIT_SECONDS
            best_answer = @history.last&.[](:observation) || "Timed out"
            return Result.err("Timed out after #{elapsed.round}s (#{@step} steps). Last observation: #{best_answer[0..SIMPLE_QUERY_LENGTH_THRESHOLD]}")
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

          UI.dim("  📊 #{observation[0..MAX_PARSE_FALLBACK_LENGTH]}...")
        end

        Result.err("Max steps (#{@max_steps}) reached without completion")
      end

      # ═══════════════════════════════════════════════════════════════════════════
      # PATTERN 2: Pre-Act - Plan first, then execute
      # Best for: multi-step tasks, structured workflows, clear sequences
      # 70% better action recall than ReAct (arXiv:2505.09970)
      # ═══════════════════════════════════════════════════════════════════════════
      
      def execute_pre_act(goal, tier:)
        # Phase 1: Generate plan
        UI.dim("  📋 Planning...")
        plan_result = generate_plan(goal, tier: tier)
        return plan_result unless plan_result.ok?
        
        @plan = plan_result.value[:steps]
        UI.dim("  📋 Plan: #{@plan.size} steps")
        
        # Phase 2: Execute plan step by step
        results = []
        @plan.each_with_index do |planned_step, idx|
          @step = idx + 1
          UI.dim("  ▸ Step #{@step}/#{@plan.size}: #{planned_step[0..60]}...")
          
          # Execute the planned action
          observation = execute_tool(planned_step)
          results << { step: @step, action: planned_step, observation: observation }
          record_history(results.last)
          
          UI.dim("  📊 #{observation[0..80]}...")
          
          # Check if we need to replan (unexpected result)
          if observation.include?("error") || observation.include?("not found")
            UI.dim("  ⚠ Replanning due to unexpected result...")
            replan_result = replan(goal, results, tier: tier)
            if replan_result.ok? && replan_result.value[:steps].any?
              @plan = @plan[0..idx] + replan_result.value[:steps]
            end
          end
        end
        
        # Phase 3: Synthesize final answer
        synthesize_answer(goal, results, tier: tier)
      end

      def generate_plan(goal, tier:)
        tool_list = TOOLS.map { |k, v| "  #{k}: #{v}" }.join("\n")
        
        prompt = <<~PLAN
          Create a step-by-step plan to accomplish this task:
          
          TASK: #{goal}
          
          TOOLS AVAILABLE:
          #{tool_list}
          
          Respond with a numbered list of tool invocations, one per line.
          Each step should be a complete tool command.
          
          Example:
          1. file_read "config.yml"
          2. analyze_code "src/main.rb"
          3. fix_code "src/main.rb"
          
          PLAN:
        PLAN
        
        result = LLM.ask(prompt, tier: tier)
        return result unless result.ok?
        
        # Parse numbered steps
        steps = result.value[:content].scan(/^\d+\.\s*(.+)$/m).flatten
        steps = steps.map(&:strip).reject(&:empty?)
        
        Result.ok(steps: steps)
      end

      def replan(goal, completed, tier:)
        history_text = completed.map { |r| "#{r[:action]} → #{r[:observation][0..MAX_PARSE_FALLBACK_LENGTH]}" }.join("\n")
        
        prompt = <<~REPLAN
          Original task: #{goal}
          
          Completed steps:
          #{history_text}
          
          The last step had an unexpected result. What additional steps are needed?
          Respond with numbered tool commands only:
        REPLAN
        
        result = LLM.ask(prompt, tier: :fast)
        return result unless result.ok?
        
        steps = result.value[:content].scan(/^\d+\.\s*(.+)$/m).flatten
        Result.ok(steps: steps.map(&:strip))
      end

      def synthesize_answer(goal, results, tier:)
        history_text = results.map do |r|
          "Step #{r[:step]}: #{r[:action]}\nResult: #{r[:observation][0..300]}"
        end.join("\n\n")
        
        prompt = <<~SYNTH
          Task: #{goal}
          
          Execution results:
          #{history_text}
          
          Provide a concise final answer based on these results:
        SYNTH
        
        result = LLM.ask(prompt, tier: :fast)
        return result unless result.ok?
        
        Result.ok(
          answer: result.value[:content],
          steps: @step,
          pattern: :pre_act,
          plan: @plan,
          history: @history
        )
      end

      # ═══════════════════════════════════════════════════════════════════════════
      # PATTERN 3: ReWOO - Reason Without Observation (batch reasoning)
      # Best for: cost-sensitive tasks, pure reasoning, minimal tool calls
      # Reduces LLM calls by batching all reasoning upfront
      # ═══════════════════════════════════════════════════════════════════════════
      
      def execute_rewoo(goal, tier:)
        tool_list = TOOLS.map { |k, v| "  #{k}: #{v}" }.join("\n")
        
        # Single LLM call to plan ALL actions with placeholders
        prompt = <<~REWOO
          Task: #{goal}
          
          Tools: #{tool_list}
          
          Create a complete plan using #E{n} as placeholders for tool results.
          Each step can reference previous results.
          
          Format:
          Plan: (your reasoning)
          #E1 = tool_name "args"
          #E2 = tool_name "args using #E1 if needed"
          ...
          
          Example:
          Plan: Read the file, analyze it, then fix issues
          #E1 = file_read "src/app.rb"
          #E2 = analyze_code "src/app.rb"
          #E3 = fix_code "src/app.rb"
        REWOO
        
        UI.dim("  🧠 Batch reasoning...")
        result = LLM.ask(prompt, tier: tier)
        return result unless result.ok?
        
        # Parse the plan
        content = result.value[:content]
        plan_text = content[/Plan:\s*(.+?)(?=#E1|$)/mi, 1]&.strip
        actions = content.scan(/#E(\d+)\s*=\s*(.+)$/i)
        
        UI.dim("  📋 Plan: #{actions.size} actions")
        
        # Execute all actions, substituting placeholders
        evidence = {}
        actions.each do |num, action_str|
          @step = num.to_i
          
          # Substitute any #E{n} references with actual results
          resolved = action_str.gsub(/#E(\d+)/) { evidence[$1.to_i] || "" }
          
          UI.dim("  ▸ #E#{num}: #{resolved[0..60]}...")
          observation = execute_tool(resolved.strip)
          evidence[num.to_i] = observation
          record_history({ step: @step, action: resolved, observation: observation })
          
          UI.dim("  📊 #{observation[0..60]}...")
        end
        
        # Final synthesis with all evidence
        synth_prompt = <<~SYNTH
          Task: #{goal}
          Plan: #{plan_text}
          
          Evidence:
          #{evidence.map { |k, v| "#E#{k} = #{v[0..400]}" }.join("\n\n")}
          
          Final answer:
        SYNTH
        
        final = LLM.ask(synth_prompt, tier: :fast)
        return final unless final.ok?
        
        Result.ok(
          answer: final.value[:content],
          steps: @step,
          pattern: :rewoo,
          evidence: evidence,
          history: @history
        )
      end

      # ═══════════════════════════════════════════════════════════════════════════
      # PATTERN 4: Reflexion - Self-critique and learning
      # Best for: fixing, debugging, tasks where mistakes are costly
      # Adds meta-cognitive layer for error correction
      # ═══════════════════════════════════════════════════════════════════════════
      
      def execute_reflexion(goal, tier:)
        original_goal = goal.dup.freeze
        max_attempts = 3
        attempt = 0
        
        while attempt < max_attempts
          attempt += 1
          UI.dim("  🔄 Attempt #{attempt}/#{max_attempts}")
          
          # Build augmented goal from original + all lessons so far
          augmented_goal = if @reflections.any?
            lessons = @reflections.map { |r| r[:lessons] }.compact.reject(&:empty?)
            "#{original_goal}\n\nLESSONS FROM PREVIOUS ATTEMPTS:\n#{lessons.join("\n")}"
          else
            original_goal
          end

          # Execute using ReAct
          result = execute_react_inner(augmented_goal, tier: tier)
          
          # Reflect on the result
          reflection = reflect_on_result(original_goal, result, tier: :fast)
          @reflections << reflection
          
          if reflection[:success]
            UI.dim("  ✓ Reflection: Success")
            return Result.ok(
              answer: result.ok? ? result.value[:answer] : reflection[:improved_answer],
              steps: @step,
              pattern: :reflexion,
              attempts: attempt,
              reflections: @reflections,
              history: @history
            )
          end
          
          UI.dim("  ⚠ Reflection: #{reflection[:critique][0..60]}...")
          
          @history = [] # Reset for fresh attempt
          @step = 0
        end
        
        Result.err("Failed after #{max_attempts} attempts with reflection")
      end

      def execute_react_inner(goal, tier:)
        # Simplified ReAct without the outer Result wrapper
        # Intentionally cap inner loop to respect overall step budget
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        [5, @max_steps - @step].max.times do
          # Check wall clock timeout
          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
          if elapsed > WALL_CLOCK_LIMIT_SECONDS
            best_answer = @history.last&.[](:observation) || "Timed out"
            return Result.err("Timed out after #{elapsed.round}s (#{@step} steps). Last observation: #{best_answer[0..SIMPLE_QUERY_LENGTH_THRESHOLD]}")
          end

          @step += 1
          context = build_context(goal)
          
          result = LLM.ask(context, tier: tier)
          return Result.err("LLM error") unless result.ok?
          
          parsed = parse_response(result.value[:content])
          record_history({ step: @step, thought: parsed[:thought], action: parsed[:action] })
          
          if parsed[:action] =~ /^(ANSWER|DONE|COMPLETE):/i
            answer = parsed[:action].sub(/^(ANSWER|DONE|COMPLETE):\s*/i, "")
            return Result.ok(answer: answer, steps: @step)
          end
          
          observation = execute_tool(parsed[:action])
          @history.last[:observation] = observation
        end
        
        Result.err("No answer in 5 steps")
      end

      def reflect_on_result(goal, result, tier:)
        history_text = @history.map do |h|
          "#{h[:thought]} → #{h[:action]} → #{h[:observation]&.[](0..SIMPLE_QUERY_LENGTH_THRESHOLD)}"
        end.join("\n")
        
        prompt = <<~REFLECT
          Task: #{goal}
          
          Execution trace:
          #{history_text}
          
          Result: #{result.ok? ? result.value[:answer] : result.error}
          
          Reflect on this execution:
          1. Did it successfully complete the task? (yes/no)
          2. What went wrong or could be improved?
          3. What lessons should be applied to the next attempt?
          4. If the answer was incomplete, provide an improved answer.
          
          Respond in this format:
          SUCCESS: yes/no
          CRITIQUE: (what went wrong)
          LESSONS: (what to do differently)
          IMPROVED_ANSWER: (better answer if needed)
        REFLECT
        
        result = LLM.ask(prompt, tier: tier)
        return { success: true, critique: "", lessons: "" } unless result.ok?
        
        content = result.value[:content]
        {
          success: content.match?(/SUCCESS:\s*yes/i),
          critique: content[/CRITIQUE:\s*(.+?)(?=LESSONS:|$)/mi, 1]&.strip || "",
          lessons: content[/LESSONS:\s*(.+?)(?=IMPROVED_ANSWER:|$)/mi, 1]&.strip || "",
          improved_answer: content[/IMPROVED_ANSWER:\s*(.+)/mi, 1]&.strip
        }
      end
    end
  end
end
