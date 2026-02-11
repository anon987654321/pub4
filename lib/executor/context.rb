# frozen_string_literal: true

require "yaml"

module MASTER
  class Executor
    # Context building and response parsing
    module Context
      def self.system_prompt_config
        @system_prompt_config ||= if File.exist?(Executor::SYSTEM_PROMPT_FILE)
          YAML.safe_load_file(Executor::SYSTEM_PROMPT_FILE) rescue {}
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
                 "ask_llm \"#{text[0..MAX_PARSE_FALLBACK_LENGTH]}\""

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
    end
  end
end
