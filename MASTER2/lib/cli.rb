module MASTER
  class CLI
    def self.start(args)
      persistence = Persistence.new("#{MASTER.root}/master.db")
      
      case args[0]
      when 'refactor'
        unless File.exist?(args[1])
          puts "Error: File not found #{args[1]}"
          return
        end
        code = File.read(args[1])
        engine = Engine.new
        result = engine.refactor(code)
        if result[:success]
          File.write(args[1], result[:code])
          puts "Refactored with diff:\n#{result[:diff]}"
          persistence.save_session({ action: 'refactor', file: args[1], result: result })
        else
          puts "Suggestions: #{result[:suggestions]}"
        end
      when 'analyze'
        unless File.exist?(args[1])
          puts "Error: File not found #{args[1]}"
          return
        end
        code = File.read(args[1])
        engine = Engine.new
        analysis = engine.analyze(code)
        puts analysis
        persistence.save_session({ action: 'analyze', file: args[1], analysis: analysis })
      when 'self_refactor'
        engine = Engine.new
        Dir.glob("#{MASTER.root}/lib/*.rb").each do |file|
          backup = file + '.backup'
          FileUtils.cp(file, backup)
          code = File.read(file)
          result = engine.refactor(code)
          if result[:success]
            File.write(file, result[:code])
            puts "Self-refactored: #{file} (backup: #{backup})"
          else
            puts "Skipped #{file}: #{result[:error]}"
          end
        end
      else
        repl(persistence, Engine.new)
      end
    end

    def self.repl(persistence, engine)
      loop do
        print "master> "
        input = gets.chomp
        break if input == 'exit'
        
        if input.start_with?('refactor ')
          result = engine.refactor(input[9..-1])
          puts result
          persistence.save_session({ action: 'repl_refactor', input: input, result: result })
        else
          puts "Processed: #{input}"
          persistence.save_session({ action: 'repl', input: input })
        end
      end
    end
  end
end
