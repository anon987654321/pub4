# frozen_string_literal: true

module MASTER
  class CLI
    module Features
      module CommandChaining
        # Command chaining with && || ; syntax
        
        def process_chained_commands(input)
          # Split by command chain operators while preserving them
          commands = split_command_chain(input)
          return process_single_input(input) if commands.size == 1
          
          results = []
          last_success = true
          
          commands.each do |cmd_part|
            operator = cmd_part[:operator]
            command = cmd_part[:command]
            
            # Determine if we should execute based on operator and last result
            should_execute = case operator
            when '&&'
              last_success
            when '||'
              !last_success
            else
              true  # ';' or first command
            end
            
            if should_execute
              begin
                result = handle(command)
                results << result if result
                last_success = true
              rescue => e
                results << error_with_solution(e)
                last_success = false
              end
            end
          end
          
          results.join("\n")
        end
        
        def split_command_chain(input)
          # Parse command chain with &&, ||, or ;
          parts = []
          current = String.new
          i = 0
          
          while i < input.length
            char = input[i]
            next_char = input[i + 1]
            
            if char == '&' && next_char == '&'
              parts << { operator: '&&', command: current.strip }
              current = String.new
              i += 2
            elsif char == '|' && next_char == '|'
              parts << { operator: '||', command: current.strip }
              current = String.new
              i += 2
            elsif char == ';'
              parts << { operator: ';', command: current.strip }
              current = String.new
              i += 1
            else
              current << char
              i += 1
            end
          end
          
          parts << { operator: nil, command: current.strip } unless current.strip.empty?
          parts.reject { |p| p[:command].empty? }
        end
      end
    end
  end
end
