# frozen_string_literal: true

module MASTER
  class CLI
    module Features
      module InlineHelp
        # Inline help and prompt hints
        COMMAND_HINTS = {
          'ask' => 'Query LLM with optional context',
          'scan' => 'Scan directory for code analysis',
          'refactor' => 'Refactor code with LLM',
          'context' => 'Manage LLM context files',
          'cat' => 'View file contents',
          'edit' => 'Edit file',
          'cd' => 'Change directory',
          'status' => 'Show session status',
          'history' => 'Show command history',
          'cost' => 'Show LLM usage cost'
        }.freeze
        
        def inline_help_for(command)
          COMMAND_HINTS[command]
        end
        
        def show_inline_hints
          return unless @show_hints
          
          recent_cmds = recent_commands(3)
          hints = recent_cmds.map { |cmd| "#{cmd}: #{inline_help_for(cmd)}" }.compact
          
          return if hints.empty?
          
          "#{C_DIM}💡 #{hints.first}#{C_RESET}"
        end
        
        def enhanced_help_text
          lines = ["#{C_BOLD}MASTER CLI Commands#{C_RESET}", ""]
          
          COMMAND_HINTS.each do |cmd, hint|
            alias_str = ALIASES.key(cmd)
            alias_part = alias_str ? " (#{alias_str})" : ""
            lines << "  #{C_LIGHT_BLUE}#{cmd}#{alias_part}#{C_RESET} - #{hint}"
          end
          
          lines << ""
          lines << "#{C_DIM}Type 'command --help' for detailed help#{C_RESET}"
          lines.join("\n")
        end
        
        private
        
        def recent_commands(n)
          return [] unless @command_history
          @command_history.last(n).map { |e| e[:command].split.first }.uniq
        end
      end
    end
  end
end
