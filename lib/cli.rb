require 'optparse'

module MASTER
  class CLI
    def self.start(args)
      options = {}
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: bin/master [command] [options]"
        opts.on('-o', '--offline', 'Offline mode') { options[:offline] = true }
        opts.on('-c', '--converge', 'Auto-iterate until convergence') { options[:converge] = true }
      end
      parser.parse!(args)

      case args[0]
      when 'refactor'
        unless File.exist?(args[1])
          puts "Error: File not found #{args[1]}"
          return
        end
        code = File.read(args[1])
        engine = Engine.new
        if options[:offline]
          ENV['OFFLINE'] = '1'
        end
        result = engine.refactor(code)
        ENV.delete 'OFFLINE'
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
        self_refactor(options)
      when 'auto_iterate'
        auto_iterate(options)
      when 'stats'
        stats = Monitoring.get_stats
        puts "Stats: #{stats}"
      else
        repl
      end
    rescue => e
      puts "Error: #{e.message}"
      puts parser.help
    end

    def self.self_refactor(options)
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
      if options[:converge]
        consecutive_no_changes = 0
        while consecutive_no_changes < 3
          changes = self_refactor(options)
          if changes
            consecutive_no_changes = 0
          else
            consecutive_no_changes += 1
          end
        end
      end
    end

    def self.auto_iterate(options)
      max_iterations = options[:max] || 10
      iterations = 0
      consecutive_no_changes = 0
      while iterations < max_iterations && consecutive_no_changes < 3
        iterations += 1
        puts "Iteration #{iterations}"
        changes = false
        engine = Engine.new
        Dir.glob("#{MASTER.root}/lib/*.rb").each do |file|
          backup = file + ".iter#{iterations}.backup"
          FileUtils.cp(file, backup)
          code = File.read(file)
          result = engine.refactor(code)
          if result[:success]
            File.write(file, result[:code])
            puts "Updated #{file}"
            changes = true
          end
        end
        if !changes
          consecutive_no_changes += 1
        else
          consecutive_no_changes = 0
        end
        sleep 2
      end
      puts "Auto-iteration complete: #{iterations} iterations"
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
        elsif input.start_with?('analyze ')
          result = engine.analyze(input[9..-1])
          puts result
        else
          puts "Processed: #{input}"
        end
      end
    end
  end
end
