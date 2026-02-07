module MASTER
  class CLI
    def self.start(args)
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
      when 'auto_iterate'
        max_iterations = 5
        iterations = 0
        changes_made = true
        while changes_made && iterations < max_iterations
          iterations += 1
          puts "Iteration #{iterations}"
          changes_made = false
          engine = Engine.new
          Dir.glob("#{MASTER.root}/lib/*.rb").each do |file|
            backup = file + ".iter#{iterations}.backup"
            FileUtils.cp(file, backup)
            code = File.read(file)
            result = engine.refactor(code)
            if result[:success]
              File.write(file, result[:code])
              puts "Updated #{file}"
              changes_made = true
            end
          end
          sleep 1  # Rate limit
        end
        puts "Auto-iteration complete: #{iterations} iterations"
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
          result = engine.refactor(input[9..-1])
          puts result
        else
          puts "Processed: #{input}"
        end
      end
    end
  end
end
