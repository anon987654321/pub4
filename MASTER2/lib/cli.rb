# frozen_string_literal: true

module MASTER
  module CLI
    extend self

    def start(args)
      mode = args[0] || "repl"
      
      case mode
      when "repl", "interactive"
        Pipeline.repl
      when "pipe", "json"
        Pipeline.pipe
      when "daemon", "server"
        daemon_mode
      when "--help", "-h", "help"
        print_help
      else
        # Treat first arg as input text for quick execution
        result = Pipeline.new.call({ text: args.join(" ") })
        
        if result.success?
          output = result.value![:rendered] || result.value![:response] || result.value!.inspect
          puts output
          exit 0
        else
          warn "Error: #{result.failure}"
          exit 1
        end
      end
    end

    def daemon_mode
      puts "Daemon mode not yet implemented"
      puts "Use 'repl' for interactive mode or 'pipe' for JSON I/O"
      exit 1
    end

    def print_help
      puts <<~HELP
        MASTER v4 - LLM-powered pipeline system
        
        Usage:
          master [mode] [args]
        
        Modes:
          repl              Interactive REPL mode (default)
          pipe              JSON input/output mode (stdin → stdout)
          daemon            Background server mode (not yet implemented)
          help              Show this help message
          
          [text]            Quick execution with text as input
        
        Examples:
          master repl
          echo '{"text":"hello"}' | master pipe
          master "What is Ruby?"
        
        Environment:
          OPENROUTER_API_KEY    Required for LLM access
          
        See README.md for full documentation.
      HELP
    end
  end
end
