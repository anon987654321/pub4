module MASTER
  class CLI
    module REPL
      def self.start(options = {})
        puts Colors.green("MASTER #{MASTER::VERSION} REPL")
        puts Colors.blue("Type '?' for help, 'exit' to quit, '!!' to repeat last command")
        
        engine = Engine.new
        last_command = nil
        history = []

        loop do
          input = read_input
          break if input.nil? || input == 'exit'
          next if input.strip.empty?

          # Handle special commands
          case input.strip
          when '?'
            show_help
            next
          when '!!'
            input = handle_repeat(last_command)
            next unless input
          end

          history << input
          last_command = input
          
          execute_command(input, engine)
        end

        puts Colors.green("\nGoodbye!")
      end

      def self.read_input
        # Check if Readline is available before using it
        if defined?(Readline)
          begin
            Readline.readline(Colors.blue("master> "), true)
          rescue Interrupt
            puts "\nInterrupted. Type 'exit' to quit."
            return ""
          end
        else
          # Fallback to basic input if readline not available
          print Colors.blue("master> ")
          begin
            $stdin.gets&.chomp
          rescue Interrupt
            puts "\nInterrupted. Type 'exit' to quit."
            return ""
          end
        end
      end

      def self.show_help
        puts Colors.blue("Available commands:")
        puts "  refactor <code> - Refactor code snippet"
        puts "  analyze <code>  - Analyze code quality"
        puts "  ?               - Show this help"
        puts "  !!              - Repeat last command"
        puts "  exit            - Exit REPL"
      end

      def self.handle_repeat(last_command)
        if last_command
          puts Colors.yellow("Repeating: #{last_command}")
          last_command
        else
          puts Colors.yellow("No previous command")
          nil
        end
      end

      def self.execute_command(input, engine)
        timer = Timer.new

        if input.start_with?('refactor ')
          code = input[9..-1]
          result = engine.refactor(code)
          if result[:success]
            puts Colors.green("✓ Refactored:")
            puts result[:code]
            puts Colors.blue("\nDiff:")
            puts result[:diff]
          else
            puts Colors.yellow("Suggestions:")
            puts result
          end
        elsif input.start_with?('analyze ')
          code = input[8..-1]
          result = engine.analyze(code)
          puts Colors.green("✓ Analysis:")
          puts result
        else
          puts Colors.yellow("Processed: #{input}")
        end

        puts Colors.blue("Time: #{timer.format_elapsed}")
      end
    end
  end
end
