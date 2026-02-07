# frozen_string_literal: true

require "json"
require "open3"

module MASTER
  # Executor - Core execution engine using ReAct pattern
  # Every task is: Thought → Action → Observation → repeat until done
  # This is the default behavior, not a special mode
  class Executor
    MAX_STEPS = 15
    
    # All available tools - the executor's capabilities
    TOOLS = {
      # Information gathering
      ask_llm: "Ask the LLM a question directly",
      web_search: "Search the web for information",
      browse_page: "Browse a URL and extract content",
      memory_search: "Search past interactions and learnings",
      
      # Code operations
      file_read: "Read a file's contents",
      file_write: "Write content to a file",
      analyze_code: "Analyze code for issues and opportunities",
      fix_code: "Auto-fix code violations",
      shell_command: "Run a shell command",
      code_execution: "Execute Ruby code",
      
      # MASTER-specific
      council_review: "Run adversarial council review",
      self_test: "Run self-test on MASTER",
    }.freeze

    attr_reader :history, :step

    def initialize(max_steps: MAX_STEPS)
      @max_steps = max_steps
      @history = []
      @step = 0
    end

    # Main entry point - execute a task/goal
    def call(goal, tier: nil)
      @history = []
      @step = 0
      
      # Quick path: simple queries that don't need tools
      if simple_query?(goal)
        return direct_ask(goal, tier: tier)
      end

      # Full ReAct loop for complex tasks
      execute_loop(goal, tier: tier || :strong)
    end

    # Class method for easy invocation
    def self.call(goal, **opts)
      new.call(goal, **opts)
    end

    private

    def simple_query?(goal)
      # Questions that don't need tool use
      goal.length < 200 &&
        !goal.match?(/\b(file|read|write|analyze|fix|search|browse|run|execute|test|review)\b/i) &&
        !goal.match?(/\b(create|update|modify|delete|install|build)\b/i)
    end

    def direct_ask(goal, tier: nil)
      result = LLM.ask(goal, tier: tier || :fast, stream: true)
      
      if result.ok?
        Result.ok(
          answer: result.value[:content],
          steps: 0,
          mode: :direct,
          cost: result.value[:cost]
        )
      else
        result
      end
    end

    def execute_loop(goal, tier:)
      while @step < @max_steps
        @step += 1

        context = build_context(goal)
        
        result = LLM.ask(context, tier: tier)
        unless result.ok?
          return Result.err("LLM error at step #{@step}: #{result.error}")
        end

        parsed = parse_response(result.value[:content])
        @history << { step: @step, thought: parsed[:thought], action: parsed[:action] }

        # Show progress
        UI.dim("  💭 #{@step}: #{parsed[:thought][0..80]}...")
        UI.dim("  🔧 #{parsed[:action][0..60]}")

        # Check for completion
        if parsed[:action] =~ /^(ANSWER|DONE|COMPLETE):/i
          answer = parsed[:action].sub(/^(ANSWER|DONE|COMPLETE):\s*/i, "")
          return Result.ok(
            answer: answer,
            steps: @step,
            mode: :react,
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
      history_text = @history.map do |h|
        "Step #{h[:step]}:\nThought: #{h[:thought]}\nAction: #{h[:action]}\nObservation: #{h[:observation]&.[](0..400)}"
      end.join("\n\n")

      tool_list = TOOLS.map { |k, v| "  #{k}: #{v}" }.join("\n")

      <<~CONTEXT
        You are MASTER, an autonomous coding assistant. Solve this task:
        
        TASK: #{goal}
        
        TOOLS AVAILABLE:
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
        Thought: (your reasoning about what to do next)
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
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
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
      stdout, stderr, status = Open3.capture3(cmd)
      output = status.success? ? stdout : "Error: #{stderr}"
      output.length > 1000 ? "#{output[0..1000]}... (truncated)" : output
    end

    def code_execution(code)
      stdout, stderr, status = Open3.capture3("ruby", stdin_data: code)
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
  end
end
