require 'optparse'
require 'readline'
require_relative 'cli/constants'
require_relative 'cli/colors'
require_relative 'cli/progress'
require_relative 'cli/suggestions'
require_relative 'cli/file_detector'
require_relative 'cli/helpers'
require_relative 'cli/repl'

module MASTER
  class CLI
    def self.start(args)
      options = Constants::DEFAULT_OPTIONS.dup
      parser = OptionParser.new do |opts|
        opts.banner = Constants::BANNER
        opts.on('-o', '--offline', 'Offline mode') { options[:offline] = true }
        opts.on('-c', '--converge', 'Auto-iterate until convergence') { options[:converge] = true }
        opts.on('-d', '--dry-run', 'Show what would change without writing') { options[:dry_run] = true }
        opts.on('-p', '--preview', 'Show before/after diff') { options[:preview] = true }
      end
      parser.parse!(args)

      # Smart defaults: no args → REPL
      return REPL.start(options) if args.empty?

      command = args[0]

      # Handle unknown commands with suggestions
      unless Constants::COMMANDS.include?(command) || File.exist?(command)
        handle_unknown_command(command)
        return
      end

      # Smart file detection
      if File.exist?(command) && !Constants::COMMANDS.include?(command)
        return unless handle_file_detection(command, args, options)
        command = args[0]
      end

      route_command(command, args, options, parser)
    rescue => e
      puts Colors.red("Error: #{e.message}")
      puts parser.help
    end

    def self.handle_unknown_command(command)
      puts Colors.red("Error: Unknown command '#{command}'")
      suggestion = Suggestions.closest_match(command, Constants::COMMANDS)
      puts Colors.yellow("Did you mean '#{suggestion}'?") if suggestion
      puts "\nAvailable commands: #{Constants::COMMANDS.join(', ')}"
    end

    def self.handle_file_detection(file_path, args, options)
      suggestion = FileDetector.suggest_command(file_path)
      return true unless suggestion

      puts Colors.blue("Auto-detected file type. Suggested command: #{suggestion[:command]}")
      puts Colors.blue("Reason: #{suggestion[:reason]}")
      print "Proceed with '#{suggestion[:command]}'? (y/n): "
      response = $stdin.gets.chomp.downcase
      return false unless response == 'y'

      # Modify args in place to inject suggested command
      args.unshift(suggestion[:command])
      true
    end

    def self.route_command(command, args, options, parser)
      case command
      when 'refactor'
        handle_refactor(args[1], options)
      when 'analyze'
        handle_analyze(args[1], options)
      when 'version'
        puts Colors.blue("MASTER version #{MASTER::VERSION}")
      when 'help'
        show_help(parser)
      when 'self_refactor'
        Helpers.self_refactor(options)
      when 'auto_iterate'
        Helpers.auto_iterate(options)
      when 'stats'
        stats = Monitoring.get_stats
        puts Colors.blue("Stats: #{stats}")
      when 'repl'
        REPL.start(options)
      end
    end

    def self.show_help(parser)
      puts parser.help
      puts "\nAvailable commands:"
      puts "  refactor <file>  - Refactor code in file"
      puts "  analyze <file>   - Analyze code quality"
      puts "  repl             - Enter interactive REPL"
      puts "  version          - Show version"
      puts "  help             - Show this help"
    end

    def self.handle_refactor(file_path, options)
      return handle_file_error(file_path) unless File.exist?(file_path)

      timer = Timer.new
      progress = Progress.new("Refactoring #{file_path}")
      progress.start

      code = File.read(file_path)
      ENV['OFFLINE'] = '1' if options[:offline]
      
      engine = Engine.new
      result = engine.refactor(code)
      
      ENV.delete 'OFFLINE'
      progress.stop

      if result[:success]
        handle_refactor_success(file_path, result, options, timer)
      else
        puts Colors.yellow("Suggestions: #{result[:suggestions]}")
      end
    end

    def self.handle_refactor_success(file_path, result, options, timer)
      if options[:dry_run]
        puts Colors.yellow("Dry-run mode: showing changes without writing")
        puts Colors.blue("Diff:\n#{result[:diff]}")
      elsif options[:preview]
        puts Colors.blue("Preview of changes:")
        puts result[:diff]
        print "Apply changes? (y/n): "
        if $stdin.gets.chomp.downcase == 'y'
          File.write(file_path, result[:code])
          puts Colors.green("✓ Refactored successfully")
        else
          puts Colors.yellow("Changes not applied")
        end
      else
        File.write(file_path, result[:code])
        puts Colors.green("✓ Refactored with diff:")
        puts result[:diff]
      end

      show_performance_metrics(result, timer)
    end

    def self.handle_analyze(target, options)
      # Handle directory input
      if File.directory?(target)
        print Colors.yellow("Analyze all files in directory '#{target}'? (y/n): ")
        return unless $stdin.gets.chomp.downcase == 'y'
        return Helpers.analyze_directory(target, options)
      end

      return handle_file_error(target) unless File.exist?(target)

      timer = Timer.new
      progress = Progress.new("Analyzing #{target}")
      progress.start

      code = File.read(target)
      engine = Engine.new
      analysis = engine.analyze(code)

      progress.stop

      puts Colors.green("✓ Analysis complete")
      puts analysis
      puts Colors.blue("\n💡 Tip: Run `master refactor #{target}` to auto-apply fixes")
      puts Colors.blue("\n--- Performance Metrics ---")
      puts "Time: #{timer.format_elapsed}"
    end

    def self.handle_file_error(file_path)
      puts Colors.red("Error: File not found #{file_path}")
      similar = Suggestions.similar_files(file_path)
      if similar.any?
        puts Colors.yellow("Did you mean one of these?")
        similar.each { |f| puts "  - #{f}" }
      end
      false
    end

    def self.show_performance_metrics(result, timer)
      return unless result[:analysis]

      puts Colors.blue("\n--- Performance Metrics ---")
      puts "Time: #{timer.format_elapsed}"
      if result[:analysis][:tokens_in]
        puts "Tokens: #{result[:analysis][:tokens_in]} in, #{result[:analysis][:tokens_out]} out"
      end
      if result[:analysis][:cost]
        puts "Estimated cost: $#{result[:analysis][:cost].round(4)}"
      end
    end
  end
end
