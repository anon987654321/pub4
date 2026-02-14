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
