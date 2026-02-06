# frozen_string_literal: true

module MASTER
  class CLI
    module Features
      module ErrorSolutions
        # Error messages with suggested solutions
        ERROR_SOLUTIONS = {
          /not found|no such file/i => [
            "Check file path is correct",
            "Use 'ls' to list files",
            "Use 'cd' to navigate to correct directory"
          ],
          /permission denied/i => [
            "Check file permissions",
            "You may need elevated privileges"
          ],
          /llm|api|openrouter/i => [
            "Set OPENROUTER_API_KEY environment variable",
            "Check API key is valid",
            "Check network connection"
          ],
          /syntax error|parse error/i => [
            "Check Ruby syntax",
            "Look for missing end, bracket, or quote"
          ],
          /context.*empty|no context/i => [
            "Add files to context with: context add <file>",
            "Scan directory with: scan"
          ]
        }.freeze
        
        def error_with_solution(error)
          message = error.respond_to?(:message) ? error.message : error.to_s
          
          # Find matching solution
          solution = ERROR_SOLUTIONS.find { |pattern, _| message.match?(pattern) }&.last
          
          # Use constants from the including class
          c_red = self.class.const_get(:C_RED)
          c_yellow = self.class.const_get(:C_YELLOW)
          c_reset = self.class.const_get(:C_RESET)
          icon_flow = self.class.const_get(:ICON_FLOW)
          icon_item = self.class.const_get(:ICON_ITEM)
          
          if solution
            ["#{c_red}Error: #{message}#{c_reset}",
             "#{c_yellow}#{icon_flow} Try:#{c_reset}",
             solution.map { |s| "  #{icon_item} #{s}" }.join("\n")
            ].join("\n")
          else
            "#{c_red}Error: #{message}#{c_reset}"
          end
        end
        
        def handle_error(error)
          puts error_with_solution(error)
          @streak = 0
        end
      end
    end
  end
end
