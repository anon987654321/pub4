module MASTER
  class CLI
    def self.start(args)
      new.run(args)
    end
    
    def run(args)
      case args.first
      when 'refactor'
        refactor_file(args[1])
      when 'analyze'
        analyze_file(args[1])
      when 'repl'
        repl
      else
        puts "MASTER #{VERSION} - Autonomous Code Refactoring"
        puts "Usage: master [refactor|analyze|repl] [file]"
      end
    end
    
    private
    
    def refactor_file(path)
      return puts "File not found: #{path}" unless File.exist?(path)
      
      engine = Engine.new
      result = engine.refactor(File.read(path), path)
      
      if result[:success]
        File.write(path, result[:code])
        puts "Refactored: #{path}"
      else
        puts "Error: #{result[:error]}"
      end
    end
    
    def analyze_file(path)
      return puts "File not found: #{path}" unless File.exist?(path)
      
      engine = Engine.new
      analysis = engine.analyze(File.read(path), path)
      
      puts "Analysis for #{path}:"
      puts analysis[:suggestions].join("\n")
    end
    
    def repl
      puts "MASTER REPL - Type 'exit' to quit"
      engine = Engine.new
      
      loop do
        print "master> "
        input = gets.chomp
        break if input == 'exit'
        
        result = engine.execute(input)
        puts result
      end
    end
  end
end
