# frozen_string_literal: true

module MASTER
  class CLI
    module Features
      module NextActions
        # Suggests next actions based on current context
        def suggest_next_actions
          suggestions = []
          
          # Context-based suggestions
          if @last_file
            suggestions << "edit #{File.basename(@last_file)}" << "cat #{File.basename(@last_file)}"
          end
          
          if @last_dir && @last_dir != @root
            suggestions << "cd #{File.basename(@last_dir)}"
          end
          
          # History-based suggestions
          if @last_query
            suggestions << "ask (follow-up question)"
          end
          
          # Common workflows
          if context_files.any?
            suggestions << "ask (query with context)" unless @last_query
          end
          
          # Scan if not scanned recently
          suggestions << "scan" unless @last_scan_time && (Time.now - @last_scan_time) < 300
          
          suggestions.take(3)
        end
        
        def format_next_actions
          actions = suggest_next_actions
          return nil if actions.empty?
          
          # Use constants from the including class
          c_dim = self.class.const_get(:C_DIM)
          c_reset = self.class.const_get(:C_RESET)
          
          "#{c_dim}Next: #{actions.join(' · ')}#{c_reset}"
        end
        
        private
        
        def context_files
          @llm.respond_to?(:context_files) ? @llm.context_files : []
        end
      end
    end
  end
end
