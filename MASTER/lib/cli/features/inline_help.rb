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
          
          # Use constants from the including class
          c_dim = self.class.const_get(:C_DIM)
          c_reset = self.class.const_get(:C_RESET)
          
          "#{c_dim}💡 #{hints.first}#{c_reset}"
        end
        
        def enhanced_help_text
          # Use constants from the including class
          c_bold = self.class.const_get(:C_BOLD)
          c_light_blue = self.class.const_get(:C_LIGHT_BLUE)
          c_dim = self.class.const_get(:C_DIM)
          c_reset = self.class.const_get(:C_RESET)
          aliases = self.class.const_get(:ALIASES)
          
          lines = ["#{c_bold}MASTER CLI Commands#{c_reset}", ""]
          
          COMMAND_HINTS.each do |cmd, hint|
            alias_str = aliases.key(cmd)
            alias_part = alias_str ? " (#{alias_str})" : ""
            lines << "  #{c_light_blue}#{cmd}#{alias_part}#{c_reset} - #{hint}"
          end
          
          lines << ""
          lines << "#{c_dim}Type 'command --help' for detailed help#{c_reset}"
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
