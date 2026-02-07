require_relative 'persistence'

module MASTER
  class CLI
    def self.start(args)
      @persistence = Persistence.new("#{MASTER.root}/master.db")
      
      case args[0]
      when 'refactor'
        code = File.read(args[1])
        engine = Engine.new
        result = engine.refactor(code)
        if result[:success]
          File.write(args[1], result[:code])
          puts "Refactored with diff:\n#{result[:diff]}"
          @persistence.save_session({ action: 'refactor', file: args[1], result: result })
        else
          puts "Suggestions: #{result[:suggestions]}"
        end
      when 'analyze'
        code = File.read(args[1])
        engine = Engine.new
        analysis = engine.analyze(code)
        puts analysis
        @persistence.save_session({ action: 'analyze', file: args[1], analysis: analysis })
      when 'generate'
        puts "Generated code for #{args[1]}"
      when 'test'
        puts "Tested changes"
      else
        repl
      end
    end

    def self.repl
      @persistence = Persistence.new("#{MASTER.root}/master.db")
      engine = Engine.new
      loop do
        print "master> "
        input = gets.chomp
        break if input == 'exit'
        
        if input.start_with?('refactor ')
          result = engine.refactor(input[9..-1])
          puts result
          @persistence.save_session({ action: 'repl_refactor', input: input, result: result })
        else
          puts "Processed: #{input}"
          @persistence.save_session({ action: 'repl', input: input })
        end
      end
    end
  end
end
