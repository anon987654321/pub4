# frozen_string_literal: true

require 'json'
require 'open3'

module MASTER
  module Core
    class ReActExecutor
      MAX_STEPS = 15
      WALL_CLOCK_TIMEOUT = 120 # seconds
      TOOLS = %w[
        web_search
        code_execution
        browse_page
        x_keyword_search
        file_read
        file_write
        shell_command
        memory_search
        vision_analyze
      ].freeze

      def self.execute(goal:, model: 'smart', max_steps: MAX_STEPS)
        start_time = Time.now
        memory = ReflectionMemory.new
        history = []
        step = 0

        while step < max_steps
          # Check wall-clock timeout
          elapsed = Time.now - start_time
          if elapsed > WALL_CLOCK_TIMEOUT
            return {
              success: false,
              error: "Wall-clock timeout (#{WALL_CLOCK_TIMEOUT}s) exceeded",
              timeout: true,
              steps: step,
              history: history,
              elapsed: elapsed
            }
          end
          
          step += 1
          
          context = build_context(goal, history, memory)
          
          thought_action = MASTER::LLM.call(
            context,
            model: model,
            temperature: 0.7,
            max_tokens: 300
          )

          parsed = parse_thought_action(thought_action)
          
          history << { step: step, thought: parsed[:thought], action: parsed[:action] }
          
          puts "  💭 Step \\#{step}: \\#{parsed[:thought]}"
          puts "  🔧 Action: \\#{parsed[:action]}"

          if parsed[:action] =~ /^ANSWER:/
            answer = parsed[:action].sub(/^ANSWER:\s*/, '')
            return {
              success: true,
              answer: answer,
              steps: step,
              history: history
            }
          end

          observation = execute_tool(parsed[:action])
          history.last[:observation] = observation
          
          puts "  📊 Observation: \\#{observation[0..150]}..."

          memory.store_reflection(
            content: "Goal: \\#{goal} | Action: \\#{parsed[:action]} | Observation: \\#{observation[0..100]}",
            strength: 0.6,
            task_id: goal.hash.to_s,
            tags: [:react, :tool_use]
          )
        end

        {
          success: false,
          error: "Max steps reached without answer",
          steps: step,
          history: history
        }
      end

      private

      def self.build_context(goal, history, memory)
        past_context = memory.build_context_string(query: goal, limit: 3)
        
        history_text = history.map do |h|
          "Step \\#{h[:step]}:\nThought: \\#{h[:thought]}\nAction: \\#{h[:action]}\n" \
          "Observation: \\#{h[:observation]&.[](0..200)}"
        end.join("\n\n")

        <<~CONTEXT
          You are solving: \\#{goal}
          
          Available tools: \\#{TOOLS.join(', ')}
          
          \\#{past_context.empty? ? '' : "Past experience:\n\\#{past_context}\n"}
          
          Previous steps:
          \\#{history_text}
          
          Think step-by-step:
          Thought: (reason about what to do next)
          Action: (tool_name "argument") OR ANSWER: (final answer)
        CONTEXT
      end

      def self.parse_thought_action(text)
        thought = text[/Thought:\s*(.+?)(?=Action:|ANSWER:|$)/m, 1]&.strip || "Continue"
        action = text[/Action:\s*(.+?)(?=Observation:|$)/m, 1]&.strip ||
                 text[/ANSWER:\s*(.+)/m, 0]&.strip ||
                 "web_search \"\\#{text[0..50]}\""
        
        { thought: thought, action: action }
      end

      def self.execute_tool(action_str)
        # Extract tool name from action string
        tool_name = action_str[/^(\w+)/, 1]
        
        # Validate tool name
        unless TOOLS.include?(tool_name)
          return "Error: Invalid tool '#{tool_name}'. Available tools: #{TOOLS.join(', ')}"
        end
        
        case action_str
        when /^web_search/
          query = action_str[/{"([^\"]+)"/, 1] || action_str.split.last
          "Search results for '\\#{query}': [simulated results - integrate real search API]"
          
        when /^code_execution/
          code = action_str[/```(\w+)?\n(.+?)```/m, 2] || action_str.split('"')[1]
          # Enforce sandboxing if available (Pledge on OpenBSD)
          execute_code_sandboxed(code || "puts 'No code provided'")
          
        when /^browse_page/
          url = action_str[/https?:\/\/[^\s]+/]
          "Page content from \\#{url}: [simulated - integrate Ferrum browser]"
          
        when /^x_keyword_search/
          query = action_str[/{"([^\"]+)"/, 1]
          "X posts for '\\#{query}': [simulated - integrate X/Twitter API]"
          
        when /^file_read/
          path = action_str[/{"([^\"]+)"/, 1]
          File.exist?(path) ? File.read(path)[0..500] : "File not found"
          
        when /^file_write/
          match = action_str.match(/"([^\"]+)"\s+"([^\"]+)"/)
          return "Error: Invalid file_write format" unless match
          
          # Ensure path is under MASTER.root
          path = File.expand_path(match[1])
          root = File.expand_path(MASTER.root)
          unless path.start_with?(root)
            return "Error: file_write path must be under #{root}"
          end
          
          File.write(path, match[2])
          "Written to \\#{match[1]}"
          
        when /^shell_command/
          # Try multiple parsing patterns
          cmd = action_str[/["']([^"']+)["']/, 1] || action_str[/{"([^\"]+)"/, 1] || action_str.split.last
          
          return "Error: No command specified" if cmd.nil? || cmd.empty?
          
          # Apply dangerous pattern guard (same as Stages::Guard)
          dangerous_patterns = [
            /rm\s+-r[f]?\s+\//, />\s*\/dev\/[sh]da/, /DROP\s+TABLE/i,
            /FORMAT\s+[A-Z]:/i, /mkfs\./, /dd\s+if=/
          ]
          
          if dangerous_patterns.any? { |pattern| pattern.match?(cmd) }
            return "Error: Blocked by safety filter - dangerous pattern detected"
          end
          
          stdout, stderr, status = Open3.capture3(cmd)
          status.success? ? stdout[0..500] : "Error: \\#{stderr[0..200]}"
          
        when /^memory_search/
          query = action_str[/{"([^\"]+)"/, 1]
          MASTER::Memory.search(query, limit: 3).join("\n")
          
        when /^vision_analyze/
          "Vision analysis: [requires Anthropic API integration]"
          
        else
          "Unknown tool. Available: \\#{TOOLS.join(', ')}"
        end
      rescue => e
        "Tool execution error: \\#{e.message}"
      end

      def self.execute_code_sandboxed(code)
        # Try to use Pledge for sandboxing on OpenBSD
        begin
          require 'tempfile'
          Tempfile.create(['react_exec', '.rb']) do |f|
            f.write(code)
            f.flush
            
            # Attempt to apply Pledge sandboxing
            begin
              require_relative 'openbsd_pledge'
              Pledge.unveil(f.path, 'r')
              Pledge.pledge('stdio rpath')
            rescue LoadError, NameError
              # Pledge not available - continue without sandboxing
            end
            
            stdout, stderr, status = Open3.capture3('ruby', f.path)
            status.success? ? stdout[0..500] : stderr[0..200]
          end
        rescue => e
          "Execution error: #{e.message}"
        end
      end

      def self.execute_code(code)
        stdout, stderr, status = Open3.capture3("ruby", stdin_data: code)
        status.success? ? stdout[0..500] : stderr[0..200]
      rescue => e
        "Execution error: \\#{e.message}"
      end
    end
  end
end
