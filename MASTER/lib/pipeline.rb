module MASTER
  class Pipeline
    def self.pipe
      input = STDIN.read
      result = process(input)
      puts result
    end
    
    def self.repl
      puts "MASTER v4.0.0 REPL"
      loop do
        print "master> "
        input = gets.chomp
        break if input == 'exit'
        
        result = process(input)
        puts result
      end
    end
    
    private
    
    def self.process(input)
      # Simple processing without full pipeline
      if input.include?('refactor')
        "Refactoring: #{input}"
      else
        "Processed: #{input}"
      end
    end
  end
end
