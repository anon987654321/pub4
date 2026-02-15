# frozen_string_literal: true

module MASTER
  class Executor
    module ReWOO
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
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # Reflexion pattern implementation
    # Self-critique and learning
    # Best for: fixing, debugging, tasks where mistakes are costly
    # Adds meta-cognitive layer for error correction
    # ═══════════════════════════════════════════════════════════════════════════
  end
end
