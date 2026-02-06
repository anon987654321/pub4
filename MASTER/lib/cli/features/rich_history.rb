# frozen_string_literal: true

module MASTER
  class CLI
    module Features
      module RichHistory
        # Rich command history with metadata
        def record_command_history(input, success:, elapsed_ms:, tokens: nil)
          @command_history ||= []
          
          entry = {
            timestamp: Time.now,
            command: input,
            success: success,
            elapsed_ms: elapsed_ms,
            tokens: tokens,
            cost: tokens ? calculate_token_cost(tokens) : 0.0,
            context_files: context_files_count,
            working_dir: @root
          }
          
          @command_history << entry
          @command_history = @command_history.last(100) # Keep last 100
        end
        
        def show_rich_history(count = 20)
          return "No command history" if @command_history.nil? || @command_history.empty?
          
          # Use constants from the including class
          c_bold = self.class.const_get(:C_BOLD)
          c_green = self.class.const_get(:C_GREEN)
          c_red = self.class.const_get(:C_RED)
          c_dim = self.class.const_get(:C_DIM)
          c_reset = self.class.const_get(:C_RESET)
          icon_ok = self.class.const_get(:ICON_OK)
          icon_err = self.class.const_get(:ICON_ERR)
          
          lines = ["#{c_bold}Recent Commands#{c_reset}"]
          @command_history.last(count).reverse.each_with_index do |entry, idx|
            time_str = entry[:timestamp].strftime('%H:%M:%S')
            status = entry[:success] ? "#{c_green}#{icon_ok}#{c_reset}" : "#{c_red}#{icon_err}#{c_reset}"
            cmd = entry[:command].size > 40 ? "#{entry[:command][0..37]}..." : entry[:command]
            
            metadata = []
            metadata << "#{entry[:elapsed_ms]}ms" if entry[:elapsed_ms]
            metadata << "#{entry[:tokens][:input]}→#{entry[:tokens][:output]}tok" if entry[:tokens]
            
            lines << "#{status} #{c_dim}#{time_str}#{c_reset} #{cmd} #{c_dim}#{metadata.join(' · ')}#{c_reset}"
          end
          
          lines.join("\n")
        end
        
        private
        
        def context_files_count
          @llm.respond_to?(:context_files) ? @llm.context_files.size : 0
        end
        
        def calculate_token_cost(tokens)
          # Rough estimate: $0.03 per 1M input tokens, $0.15 per 1M output tokens
          (tokens[:input] * 0.03 / 1_000_000) + (tokens[:output] * 0.15 / 1_000_000)
        end
      end
    end
  end
end
