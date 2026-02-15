# frozen_string_literal: true

require "json"
require "open3"
require "yaml"
require "rbconfig"
require "fileutils"
require "uri"

module MASTER
  # Momentum - Track task progress and productivity metrics
  module Momentum
    extend self

    TASKS_PER_XP = 5

    XP = {
      chat: 1,
      refactor: 5,
      evolve: 10,
      fix: 3,
      test: 2
    }.freeze

    LEVELS = [
      { xp: 0, title: "Novice" },
      { xp: 50, title: "Apprentice" },
      { xp: 150, title: "Journeyman" },
      { xp: 300, title: "Expert" },
      { xp: 500, title: "Master" }
    ].freeze

    def fresh
      {
        xp: 0,
        level: 1,
        streak: 0,
        achievements: []
      }
    end

    def state
      @state ||= fresh
    end

    def award(action)
      xp_gain = XP[action] || 1
      multiplier = streak_multiplier
      total_gain = (xp_gain * multiplier).to_i
      
      state[:xp] += total_gain
      state[:level] = calculate_level(state[:xp])
      
      { xp_gained: total_gain, total_xp: state[:xp], level: state[:level] }
    end

    def title
      LEVELS.reverse.find { |l| state[:xp] >= l[:xp] }&.[](:title) || "Novice"
    end

    def streak_multiplier
      case state[:streak]
      when 0..2 then 1.0
      when 3..6 then 1.2
      when 7..13 then 1.5
      else 2.0
      end
    end

    def track(action, result: nil)
      # Track action and update streak if successful
      if result&.ok? || result.nil?
        state[:streak] += 1
      else
        state[:streak] = 0
      end
      
      Result.ok(action: action, tracked: true)
    end

    def summary
      { 
        tasks_completed: state[:xp] / TASKS_PER_XP,
        streak: state[:streak],
        level: state[:level],
        title: title
      }
    end

    private

    def calculate_level(xp)
      LEVELS.count { |l| xp >= l[:xp] }
    end
  end

  # Executor - Hybrid agent with multiple reasoning patterns
  # Patterns: react, pre_act, rewoo, reflexion
  # Auto-selects best pattern based on task characteristics
  class Executor

    MAX_STEPS = 15
    WALL_CLOCK_LIMIT_SECONDS = 120  # seconds
    MAX_HISTORY_ENTRIES = 50
    MAX_LINTER_RETRIES = 3  # Don't loop more than 3 times on same error
    
    # Magic number constants extracted for clarity (Phase 5 - Style compliance)
    MAX_BROWSE_CONTENT = 5000
    MAX_FILE_CONTENT = 3000
    MAX_CURL_CONTENT = 2000
    MAX_LLM_RESPONSE_PREVIEW = 1000
    MAX_SHELL_OUTPUT = 1000
    SIMPLE_QUERY_LENGTH_THRESHOLD = 200
    MAX_PARSE_FALLBACK_LENGTH = 100
    
    PATTERNS = %i[react pre_act rewoo reflexion].freeze
    SYSTEM_PROMPT_FILE = File.join(__dir__, "..", "data", "system_prompt.yml")
    
    # Dangerous patterns to block (injection prevention)
    # Synchronized with Stages::Guard::DANGEROUS_PATTERNS
    DANGEROUS_PATTERNS = [
      /rm\s+-r[f]?\s+\//,
      />\s*\/dev\/[sh]da/,
      /DROP\s+TABLE/i,
      /FORMAT\s+[A-Z]:/i,
      /mkfs\./,
      /dd\s+if=/,
    ].freeze
    
    # Protected paths that cannot be written to
    PROTECTED_WRITE_PATHS = %w[
      data/constitution.yml
      /etc/
      /usr/
      /sys/
      /proc/
      /dev/
      /boot/
    ].freeze
    
    # All available tools
    TOOLS = {
      ask_llm: "Ask the LLM a question directly",
      web_search: "Search the web for information",
      browse_page: "Browse a URL and extract content",
      memory_search: "Search past interactions and learnings",
      file_read: "Read a file's contents",
      file_write: "Write content to a file",
      analyze_code: "Analyze code for issues and opportunities",
      fix_code: "Auto-fix code violations",
      shell_command: "Run a shell command",
      code_execution: "Execute Ruby code",
      council_review: "Run adversarial council review",
      self_test: "Run self-test on MASTER",
    }.freeze

    attr_reader :history, :step, :pattern, :plan, :reflections, :max_steps

    def initialize(max_steps: MAX_STEPS)
      @max_steps = max_steps
      @history = []
      @reflections = []
      @plan = []
      @step = 0
    end

    # Main entry - auto-selects pattern or uses specified
    def call(goal, pattern: :auto, tier: nil)
      @history = []
      @reflections = []
      @plan = []
      @step = 0
      @pattern = pattern == :auto ? select_pattern(goal) : pattern
      
      # Quick path: simple queries
      return direct_ask(goal, tier: tier) if simple_query?(goal)

      UI.dim("  ⚡ Pattern: #{@pattern}") if ENV["DEBUG"]
      
      result = execute_pattern(@pattern, goal, tier: tier || :strong)
      
      # Fallback to simpler patterns if primary fails
      if !result.ok? && @pattern != :react
        UI.warn("Pattern #{@pattern} failed, falling back to :react")
        @step = 0
        @history = []
        result = execute_pattern(:react, goal, tier: tier || :strong)
      end
      
      # Final fallback to direct if all else fails
      if !result.ok? && @step > 0
        UI.warn("All patterns failed, attempting direct response")
        result = direct_ask("Given this context, provide the best answer you can:\n\n#{goal}", tier: :fast)
      end
      
      result
    end

    def execute_pattern(pattern, goal, tier:)
      case pattern
      when :react     then execute_react(goal, tier: tier)
      when :pre_act   then execute_pre_act(goal, tier: tier)
      when :rewoo     then execute_rewoo(goal, tier: tier)
      when :reflexion then execute_reflexion(goal, tier: tier)
      else execute_react(goal, tier: tier)
      end
    end

    def self.call(goal, **opts)
      new.call(goal, **opts)
    end

    # Pattern selection heuristics
    def select_pattern(goal)
      # Pre-Act: explicit multi-step tasks
      return :pre_act if goal.match?(/\b(then|after that|next|finally|step\s*\d|first.*then)\b/i)
      return :pre_act if goal.match?(/\b(build|create|implement|develop)\b.*\b(and|with)\b/i)
      
      # ReWOO: cost-sensitive or pure reasoning
      return :rewoo if goal.match?(/\b(explain|describe|summarize|compare|analyze)\b/i) &&
                       !goal.match?(/\b(file|code|execute|run)\b/i)
      
      # Reflexion: learning/fixing tasks
      return :reflexion if goal.match?(/\b(fix|debug|correct|improve|refactor)\b/i)
      return :reflexion if goal.match?(/\b(don't break|carefully|safely)\b/i)
      
      # Default: ReAct for exploratory/unknown
      :react
    end

    private

    def simple_query?(goal)
      goal.length < SIMPLE_QUERY_LENGTH_THRESHOLD &&
        !goal.match?(/\b(file|read|write|analyze|fix|search|browse|run|execute|test|review)\b/i) &&
        !goal.match?(/\b(create|update|modify|delete|install|build)\b/i)
    end

    def direct_ask(goal, tier: nil)
      # Use shared system message builder (no commands for brevity)
      system_msg = Context.build_system_message(include_commands: false)
      
      prompt = <<~PROMPT
        #{system_msg}
        
        User question: #{goal}
      PROMPT
      
      result = LLM.ask(prompt, tier: tier || :fast, stream: true)
      
      if result.ok?
        Result.ok(
          answer: result.value[:content],
          steps: 0,
          mode: :direct,
          pattern: :direct,
          cost: result.value[:cost]
        )
      else
        result
      end
    end

    def self.system_prompt_config
      @system_prompt_config ||= if File.exist?(SYSTEM_PROMPT_FILE)
        YAML.safe_load_file(SYSTEM_PROMPT_FILE) rescue {}
      else
        {}
      end
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # ReAct pattern implementation
    # Tight thought-action-observation loop
    # Best for: exploratory tasks, dynamic adaptation, unknown territory
    # ═══════════════════════════════════════════════════════════════════════════
    module React
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

    # ═══════════════════════════════════════════════════════════════════════════
    # Pre-Act pattern implementation
    # Plan first, then execute
    # Best for: multi-step tasks, structured workflows, clear sequences
    # 70% better action recall than ReAct (arXiv:2505.09970)
    # ═══════════════════════════════════════════════════════════════════════════
    module PreAct
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
        history_text = completed.map { |r| "#{r[:action]} → #{r[:observation][0..100]}" }.join("\n")
        
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
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # ReWOO pattern implementation
    # Reason Without Observation (batch reasoning)
    # Best for: cost-sensitive tasks, pure reasoning, minimal tool calls
    # Reduces LLM calls by batching all reasoning upfront
    # ═══════════════════════════════════════════════════════════════════════════
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
    module Reflexion
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
            return Result.err("Timed out after #{elapsed.round}s (#{@step} steps). Last observation: #{best_answer[0..200]}")
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
          "#{h[:thought]} → #{h[:action]} → #{h[:observation]&.[](0..200)}"
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

    # ═══════════════════════════════════════════════════════════════════════════
    # Tools module - All tool execution and dispatch logic
    # ═══════════════════════════════════════════════════════════════════════════
    module Tools
      def execute_tool(action_str)
        # Sanitize input before processing
        action_str = sanitize_tool_input(action_str)
        return action_str if action_str.start_with?("BLOCKED:")

        case action_str
        when /^ask_llm\s+["']?(.+?)["']?\s*$/i
          ask_llm($1)

        when /^web_search\s+["']?([^"']+)["']?/i
          web_search($1)

        when /^browse_page\s+["']?(https?:\/\/[^\s"']+)["']?/i
          browse_page($1)

        when /^file_read\s+["']?([^"'\n]+)["']?/i
          file_read($1.strip)

        when /^file_write\s+["']?([^"'\n]+)["']?\s+["']?(.+)["']?/mi
          file_write($1.strip, $2)

        when /^analyze_code\s+["']?([^"'\n]+)["']?/i
          analyze_code($1.strip)

        when /^fix_code\s+["']?([^"'\n]+)["']?/i
          fix_code($1.strip)

        when /^shell_command\s+["']?([^"'\n]+)["']?/i
          shell_command($1)

        when /^code_execution.*```(\w*)?\n(.+?)```/mi
          code_execution($2)

        when /^council_review\s+["']?(.+?)["']?\s*$/i
          council_review($1)

        when /^memory_search\s+["']?([^"']+)["']?/i
          memory_search($1)

        when /^self_test/i
          self_test

        else
          "Unknown tool. Available: #{TOOLS.keys.join(', ')}"
        end
      rescue StandardError => e
        "Tool error: #{e.message}"
      end

      # Tool implementations

      def ask_llm(prompt)
        result = LLM.ask(prompt, tier: :fast)
        result.ok? ? result.value[:content][0..1000] : "LLM error: #{result.error}"
      end

      def web_search(query)
        if defined?(Web)
          result = Web.browse("https://duckduckgo.com/html/?q=#{URI.encode_www_form_component(query)}")
          result.ok? ? result.value[:content] : "Search failed: #{result.error}"
        else
          "Web module not available"
        end
      end

      def browse_page(url)
        if defined?(Web)
          result = Web.browse(url)
          result.ok? ? result.value[:content] : "Browse failed: #{result.error}"
        else
          `curl -sL --max-time 10 "#{url}" 2>/dev/null`[0..2000]
        end
      end

      def file_read(path)
        return "File not found: #{path}" unless File.exist?(path)
        content = File.read(path)
        content.length > 3000 ? "#{content[0..3000]}... (truncated, #{content.length} chars total)" : content
      end

      def file_write(path, content)
        expanded = File.expand_path(path)
        
        # Check protected paths first
        PROTECTED_WRITE_PATHS.each do |protected|
          # For absolute paths, compare directly; for relative, expand from root
          protected_expanded = if protected.start_with?("/")
            protected
          else
            File.expand_path(protected, MASTER.root)
          end
          
          if expanded.start_with?(protected_expanded) || expanded == protected_expanded
            return "BLOCKED: file_write to protected path '#{path}'"
          end
        end
        
        # Check working directory constraint
        cwd = File.expand_path(".")
        unless expanded.start_with?(cwd)
          return "BLOCKED: file_write path '#{path}' is outside working directory"
        end
        
        FileUtils.mkdir_p(File.dirname(expanded))
        File.write(expanded, content)
        "Written #{content.length} bytes to #{path}"
      end

      def analyze_code(path)
        return "File not found: #{path}" unless File.exist?(path)
        code = File.read(path)
        
        if defined?(CodeReview)
          result = CodeReview.analyze(code, filename: File.basename(path))
          "Issues: #{result[:issues].size}, Score: #{result[:score]}/#{result[:max_score]}, Grade: #{result[:grade]}"
        else
          "CodeReview module not available"
        end
      end

      def fix_code(path)
        if defined?(AutoFixer)
          fixer = AutoFixer.new(mode: :moderate)
          result = fixer.fix(path)
          result.ok? ? "Fixed #{result.value[:fixed]} issues in #{path}" : "Fix failed: #{result.error}"
        else
          "AutoFixer module not available"
        end
      end

      def shell_command(cmd)
        if DANGEROUS_PATTERNS.any? { |p| p.match?(cmd) }
          return "BLOCKED: dangerous shell command rejected"
        end

        if defined?(Constitution)
          check = Constitution.check_operation(:shell_command, command: cmd)
          return "BLOCKED: #{check.error}" unless check.ok?
        end

        if defined?(Shell)
          result = Shell.execute(cmd)
          output = result.ok? ? result.value : "Error: #{result.error}"
        else
          stdout, stderr, status = Open3.capture3(cmd)
          output = status.success? ? stdout : "Error: #{stderr}"
        end

        output.length > 1000 ? "#{output[0..1000]}... (truncated)" : output
      end

      def code_execution(code)
        # Block dangerous Ruby constructs
        dangerous_code = [
          /system\s*\(/,
          /exec\s*\(/,
          /`[^`]*`/,
          /Kernel\.exec/,
          /IO\.popen/,
          /Open3/,
          /FileUtils\.rm_rf/
        ]
        
        if dangerous_code.any? { |pattern| pattern.match?(code) }
          return "BLOCKED: code_execution contains dangerous constructs"
        end
        
        # Attempt Pledge sandboxing on OpenBSD if available
        if defined?(Pledge)
          begin
            Pledge.pledge("stdio rpath")
          rescue StandardError
            # Pledge not available or failed, continue without it
          end
        end
        
        stdout, stderr, status = Open3.capture3(RbConfig.ruby, stdin_data: code)
        status.success? ? stdout[0..500] : "Error: #{stderr[0..300]}"
      end

      def council_review(text)
        if defined?(Chamber)
          result = Chamber.council_review(text)
          "Passed: #{result[:passed]}, Consensus: #{result[:consensus]}, Votes: #{result[:votes].size}"
        else
          "Chamber module not available"
        end
      end

      def memory_search(query)
        if defined?(Memory)
          results = Memory.search(query, limit: 3)
          results.empty? ? "No memories found for: #{query}" : results.join("\n")
        else
          "Memory module not available"
        end
      end

      def self_test
        if defined?(SelfTest)
          result = SelfTest.run
          result.ok? ? "Self-test completed" : "Self-test failed: #{result.error}"
        else
          "SelfTest module not available"
        end
      end

      def sanitize_tool_input(action_str)
        if DANGEROUS_PATTERNS.any? { |p| p.match?(action_str) }
          return "BLOCKED: dangerous pattern detected in tool input"
        end
        action_str
      end

      def check_tool_permission(tool_name)
        if defined?(Constitution)
          unless Constitution.permission?(tool_name)
            return Result.err("Tool '#{tool_name}' not permitted by constitution")
          end
        end
        Result.ok
      end

      def record_history(entry)
        @history << entry
        @history.shift if @history.size > MAX_HISTORY_ENTRIES
      end
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # Patterns module - Pattern execution orchestration
    # Note: Most patterns are defined above but some duplicates exist here
    # for compatibility with the original file organization
    # ═══════════════════════════════════════════════════════════════════════════
    module Patterns
      # Pattern methods are already defined in individual modules above
      # This module exists for backward compatibility
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # Context module - Context building and response parsing
    # ═══════════════════════════════════════════════════════════════════════════
    module Context
      def self.system_prompt_config
        @system_prompt_config ||= if File.exist?(Executor::SYSTEM_PROMPT_FILE)
          YAML.safe_load_file(Executor::SYSTEM_PROMPT_FILE) rescue {}
        else
          {}
        end
      end

      # Build comprehensive system message with all YAML sections + persona
      def self.build_system_message(include_commands: true)
        config = system_prompt_config
        
        # Identity (interpolated)
        identity = if config["identity"]
          config["identity"] % { version: MASTER::VERSION, platform: RUBY_PLATFORM, ruby_version: RUBY_VERSION }
        else
          "You are MASTER v#{MASTER::VERSION}, an autonomous coding assistant."
        end
        
        sections = [identity]
        
        # Environment
        sections << config["environment"] if config["environment"]
        
        # Shell patterns
        sections << config["shell_patterns"] if config["shell_patterns"]
        
        # Behavior
        sections << config["behavior"] if config["behavior"]
        
        # Task workflow
        if config["task_workflow"]
          sections << "TASK WORKFLOW:\n#{config["task_workflow"]}"
        end
        
        # Tone
        if config["tone"]
          sections << "COMMUNICATION:\n#{config["tone"]}"
        end
        
        # Commands (optional)
        if include_commands
          commands = config["commands"] || <<~CMD
            YOUR COMMANDS: model <name>, models, pattern <name>, budget, selftest, help, exit
          CMD
          sections << commands
        end
        
        # Safety / Injection defense
        if config["safety"]
          sections << "SAFETY:\n#{config["safety"]}"
        end
        
        # Critical axioms
        if config["critical_axioms"]
          sections << "CORE AXIOMS:\n#{config["critical_axioms"]}"
        end
        
        # Anti-simulation rules
        if config["anti_simulation"]
          sections << "EVIDENCE RULES:\n#{config["anti_simulation"]}"
        end
        
        # Check for active persona
        if defined?(LLM) && LLM.respond_to?(:persona_prompt)
          persona_prompt = LLM.persona_prompt
          sections << "\nACTIVE PERSONA:\n#{persona_prompt}" if persona_prompt && !persona_prompt.empty?
        end
        
        # Check for project-specific MASTER.md
        master_md = File.join(Dir.pwd, "MASTER.md")
        if File.exist?(master_md)
          sections << "\nPROJECT CONTEXT (from MASTER.md):\n#{File.read(master_md)[0..2000]}"
        end
        
        sections.join("\n\n")
      end

      # Build task context (tools + format + history)
      def build_task_context(goal)
        history_text = @history.map do |h|
          "Step #{h[:step]}:\nThought: #{h[:thought]}\nAction: #{h[:action]}\nObservation: #{h[:observation]&.[](0..400)}"
        end.join("\n\n")
        
        # Build tool list and format from TOOLS hash
        tool_list = TOOLS.map { |k, v| "  #{k}: #{v}" }.join("\n")
        
        # Generate tool format examples
        # NOTE: These patterns are derived from TOOLS keys but usage strings are hardcoded
        # TODO: Consider extending TOOLS hash with usage patterns for single source of truth
        tool_format = TOOLS.keys.map { |tool|
          case tool
          when :ask_llm then '- ask_llm "your question"'
          when :web_search then '- web_search "query"'
          when :browse_page then '- browse_page "url"'
          when :file_read then '- file_read "path"'
          when :file_write then '- file_write "path" "content"'
          when :analyze_code then '- analyze_code "path"'
          when :fix_code then '- fix_code "path"'
          when :shell_command then '- shell_command "command"'
          when :code_execution then "- code_execution ```ruby\n  code here\n  ```"
          when :council_review then '- council_review "text to review"'
          when :memory_search then '- memory_search "query"'
          when :self_test then '- self_test'
          else "- #{tool} (use appropriately)"
          end
        }.join("\n")

        <<~TASK
          TASK: #{goal}
          
          TOOLS AVAILABLE (for autonomous execution):
          #{tool_list}
          
          TOOL FORMAT:
          #{tool_format}
          
          When complete, respond: ANSWER: your final answer
          
          #{history_text.empty? ? "" : "PREVIOUS STEPS:\n#{history_text}\n"}
          
          Respond with:
          Thought: (brief reasoning)
          Action: (tool invocation or ANSWER: final answer)
        TASK
      end

      def build_context(goal, system_only: false)
        # Get comprehensive system message
        system_msg = Context.build_system_message(include_commands: true)
        
        # If system_only flag set, return just system message (for messages array usage)
        return system_msg if system_only
        
        # Return full context with system + task
        "#{system_msg}\n\n#{build_task_context(goal)}"
      end
      
      # Build context as messages array with system/user separation
      def build_context_messages(goal)
        [
          { role: "system", content: Context.build_system_message(include_commands: true) },
          { role: "user", content: build_task_context(goal) }
        ]
      end

      def parse_response(text)
        thought = text[/Thought:\s*(.+?)(?=Action:|ANSWER:|DONE:|$)/mi, 1]&.strip || "Continuing"
        action = text[/Action:\s*(.+?)(?=Observation:|Thought:|$)/mi, 1]&.strip ||
                 text[/(ANSWER|DONE|COMPLETE):\s*(.+)/mi, 0]&.strip ||
                 "ask_llm \"#{text[0..MAX_PARSE_FALLBACK_LENGTH]}\""

        { thought: thought, action: action }
      end

      def execute_tool(action_str)
        # Delegate to Tools module
        Tools.instance_method(:execute_tool).bind(self).call(action_str)
      end
    end

    # Include all modules in the Executor class
    include React
    include PreAct
    include ReWOO
    include Reflexion
    include Tools
    include Patterns
    include Context
  end
end
