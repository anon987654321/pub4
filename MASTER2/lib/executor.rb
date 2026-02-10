# frozen_string_literal: true

require "json"
require "open3"
require "yaml"
require "rbconfig"

module MASTER
  # Executor - Hybrid agent with multiple reasoning patterns
  # Patterns: react, pre_act, rewoo, reflexion
  # Auto-selects best pattern based on task characteristics
  class Executor
    MAX_STEPS = 15
    WALL_CLOCK_LIMIT_SECONDS = 120  # seconds
    MAX_HISTORY_ENTRIES = 50
    MAX_LINTER_RETRIES = 3  # Don't loop more than 3 times on same error
    PATTERNS = %i[react pre_act rewoo reflexion].freeze
    SYSTEM_PROMPT_FILE = File.join(__dir__, "..", "data", "system_prompt.yml")
    
    # Dangerous patterns to block (injection prevention)
    # Reference the canonical definition in Stages::Guard
    DANGEROUS_PATTERNS = Stages::Guard::DANGEROUS_PATTERNS
    
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
      goal.length < 200 &&
        !goal.match?(/\b(file|read|write|analyze|fix|search|browse|run|execute|test|review)\b/i) &&
        !goal.match?(/\b(create|update|modify|delete|install|build)\b/i)
    end

    def direct_ask(goal, tier: nil)
      config = self.class.system_prompt_config
      
      # Build concise system context for direct queries
      identity = if config["identity"]
        config["identity"] % { version: MASTER::VERSION, platform: RUBY_PLATFORM }
      else
        "You are MASTER v#{MASTER::VERSION}, an autonomous coding assistant."
      end
      
      commands = config["commands"] || <<~CMD
        YOUR COMMANDS: model <name>, models, pattern <name>, budget, selftest, help, exit
      CMD
      
      # Tone from config
      tone_rules = config.dig("tone")&.take(2)&.join(" ") || "Be concise and direct."
      
      prompt = <<~PROMPT
        #{identity}
        #{tone_rules}
        
        #{commands.lines.first(8).join}
        
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

    # ═══════════════════════════════════════════════════════════════════════════
    # Shared: Context building and response parsing
    # ═══════════════════════════════════════════════════════════════════════════

    def self.system_prompt_config
      @system_prompt_config ||= if File.exist?(SYSTEM_PROMPT_FILE)
        YAML.safe_load_file(SYSTEM_PROMPT_FILE) rescue {}
      else
        {}
      end
    end

    def build_context(goal)
      config = self.class.system_prompt_config
      history_text = @history.map do |h|
        "Step #{h[:step]}:\nThought: #{h[:thought]}\nAction: #{h[:action]}\nObservation: #{h[:observation]&.[](0..400)}"
      end.join("\n\n")

      tool_list = TOOLS.map { |k, v| "  #{k}: #{v}" }.join("\n")
      
      # Build identity from config or default
      identity = if config["identity"]
        config["identity"] % { version: MASTER::VERSION, platform: RUBY_PLATFORM }
      else
        "You are MASTER v#{MASTER::VERSION}, an autonomous coding assistant running on #{RUBY_PLATFORM}."
      end
      
      # Tone guidelines
      tone = config.dig("tone")&.map { |t| "- #{t}" }&.join("\n") || ""
      
      # Commands from config or inline
      commands = config["commands"] || <<~CMD
        YOUR COMMANDS (what users type at the master> prompt):
          model <name>      Switch LLM model (e.g., model kimi-k2.5)
          models            List available models
          pattern <name>    Switch execution pattern
          budget            Show remaining budget
          selftest          Run self-test
          help              Show all commands
          exit              Exit MASTER (or Ctrl+C twice)
      CMD
      
      # Check for project-specific MASTER.md
      project_context = ""
      master_md = File.join(Dir.pwd, "MASTER.md")
      if File.exist?(master_md)
        project_context = "\nPROJECT CONTEXT (from MASTER.md):\n#{File.read(master_md)[0..2000]}\n"
      end

      <<~CONTEXT
        #{identity}
        
        #{tone.empty? ? "" : "COMMUNICATION STYLE:\n#{tone}\n"}
        #{commands}
        #{project_context}
        TASK: #{goal}
        
        TOOLS AVAILABLE (for autonomous execution):
        #{tool_list}
        
        TOOL FORMAT:
        - ask_llm "your question"
        - web_search "query"
        - browse_page "url"
        - file_read "path"
        - file_write "path" "content"
        - analyze_code "path"
        - fix_code "path"
        - shell_command "command"
        - code_execution ```ruby
          code here
          ```
        - council_review "text to review"
        - memory_search "query"
        - self_test
        
        When complete, respond: ANSWER: your final answer
        
        #{history_text.empty? ? "" : "PREVIOUS STEPS:\n#{history_text}\n"}
        
        Respond with:
        Thought: (brief reasoning)
        Action: (tool invocation or ANSWER: final answer)
      CONTEXT
    end

    def parse_response(text)
      thought = text[/Thought:\s*(.+?)(?=Action:|ANSWER:|DONE:|$)/mi, 1]&.strip || "Continuing"
      action = text[/Action:\s*(.+?)(?=Observation:|Thought:|$)/mi, 1]&.strip ||
               text[/(ANSWER|DONE|COMPLETE):\s*(.+)/mi, 0]&.strip ||
               "ask_llm \"#{text[0..100]}\""

      { thought: thought, action: action }
    end

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
end
