module MASTER
  class CLI
    def self.start(args)
      case args[0]
      when 'refactor'
        code = File.read(args[1])
        engine = Engine.new
        result = engine.refactor(code)
        if result[:success]
          File.write(args[1], result[:code])
          puts "Refactored with diff:\n#{result[:diff]}"
        else
          puts "Suggestions: #{result[:suggestions]}"
        end
      when 'analyze'
        code = File.read(args[1])
        engine = Engine.new
        analysis = engine.analyze(code)
        puts analysis
      when 'generate'
        puts "Generated code for #{args[1]}"
      when 'test'
        puts "Tested changes"
      else
        repl
      end
    end

    def self.repl
      engine = Engine.new
      loop do
        print "master> "
        input = gets.chomp
        break if input == 'exit'
        
        if input.start_with?('refactor ')
          # Pipe refactor
          result = engine.refactor(input[9..-1])
          puts result
        else
          puts "Processed: #{input}"
        end
      end
    end
  end
end

    when 'self_refactor'
      files = Dir.glob("#{MASTER.root}/lib/*.rb")
      files.each do |file|
        code = File.read(file)
        result = engine.refactor(code)
        if result[:success]
          File.write(file, result[:code])
          puts "Self-refactored: #{file}"
        end
      end
