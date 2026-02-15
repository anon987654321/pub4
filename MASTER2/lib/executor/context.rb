# frozen_string_literal: true

module MASTER
  class Executor
    module Context
      SIMPLE_SECTIONS = %w[environment shell_patterns behavior].freeze
      LABELED_SECTIONS = {
        "task_workflow" => "TASK WORKFLOW",
        "safety" => "SAFETY",
        "critical_axioms" => "CORE AXIOMS",
        "anti_simulation" => "EVIDENCE RULES",
      }.freeze

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

        # Add simple sections
        SIMPLE_SECTIONS.each { |key| sections << config[key] if config[key] }

        # Add labeled sections
        LABELED_SECTIONS.each do |key, label|
          sections << "#{label}:\n#{config[key]}" if config[key]
        end

        # Commands (optional)
        if include_commands
          commands = config["commands"] || <<~CMD
            YOUR COMMANDS: model <name>, models, pattern <name>, budget, selftest, help, exit
          CMD
          sections << commands
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
        tool_list = TOOLS.map { |k, v| "  #{k}: #{v[:desc]}" }.join("\n")
        tool_format = TOOLS.map { |k, v| "- #{v[:usage]}" }.join("\n")

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
    end
  end
end
