require 'optparse'

module MASTER
  class CLI
    def self.start(args)
      options = {}
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: bin/master [command] [options]"
        opts.on('-o', '--offline', 'Offline mode') { options[:offline] = true }
        opts.on('-c', '--converge', 'Auto-iterate until convergence') { options[:converge] = true }
        opts.on('--voice', 'Enable voice mode') { options[:voice] = true }
        opts.on('--dashboard', 'Start HTML dashboard') { options[:dashboard] = true }
        opts.on('--multimodal', 'Start multimodal interface') { options[:multimodal] = true }
        opts.on('--auto-proceed', 'Auto-apply suggestions without confirmation') { options[:auto_proceed] = true }
        opts.on('--threshold FLOAT', Float, 'Confidence threshold for auto-proceed (0.0-1.0)') { |t| options[:threshold] = t }
      end
      parser.parse!(args)

      case args[0]
      when 'refactor'
        unless File.exist?(args[1])
          puts "Error: File not found #{args[1]}"
          return
        end
        code = File.read(args[1])
        engine = Engine.new(
          auto_proceed: options[:auto_proceed],
          confidence_threshold: options[:threshold] || 0.85
        )
        if options[:offline]
          ENV['OFFLINE'] = '1'
        end
        result = engine.refactor(code)
        ENV.delete 'OFFLINE'
        if result[:success]
          File.write(args[1], result[:code])
          puts "Refactored with diff:\n#{result[:diff]}"
        elsif result[:skipped]
          puts "Skipped: #{result[:reason]}"
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
      when 'suggest'
        path = args[1] || 'lib/'
        suggester = SmartSuggest.new
        suggestions = suggester.batch_analyze([path])
        puts "Found #{suggestions.size} suggestions:\n\n"
        suggestions.take(10).each do |s|
          puts s.to_s
          puts ""
        end
      when 'self_refactor'
        self_refactor(options)
      when 'auto_iterate'
        path = args[1] || 'lib/'
        auto_iterate_path(path, options)
      when 'dashboard'
        start_dashboard(args[1] || 'lib/', options)
      when 'voice'
        start_voice_mode(options)
      when 'multimodal'
        start_multimodal(options)
      when 'stats'
        stats = Monitoring.get_stats
        puts "Stats: #{stats}"
      else
        if options[:voice]
          start_voice_mode(options)
        elsif options[:dashboard]
          start_dashboard('lib/', options)
        elsif options[:multimodal]
          start_multimodal(options)
        else
          repl
        end
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

    def self.auto_iterate_path(path, options)
      AutoIterate.converge(path, options) do |iteration|
        puts iteration.to_s
      end
    end

    def self.start_dashboard(path, options)
      view = HTMLView.new(theme: options[:theme] || 'dark')
      html = view.generate_dashboard(path)
      output_file = File.join(MASTER.root, 'dashboard.html')
      File.write(output_file, html)
      puts "📊 Dashboard generated: #{output_file}"
      puts "   Open in browser to view"
      
      # Optionally start a simple web server
      if options[:serve]
        puts "   Starting server on http://localhost:4567"
        # Would start Sinatra server here
      end
    end

    def self.start_voice_mode(options)
      Voice.listen do |command|
        puts "Processing: #{command}"
      end
    end

    def self.start_multimodal(options)
      Multimodal.start do |interface|
        interface.on_voice do |cmd, result|
          puts "Voice: #{cmd}"
        end
        
        interface.on_text do |cmd, result|
          puts "Text: #{cmd}"
        end
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
