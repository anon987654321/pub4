module MASTER
  class CLI
    module Helpers
      def self.analyze_directory(directory, options)
        files = Dir.glob("#{directory}/**/*.rb")
        puts Colors.blue("Found #{files.length} Ruby files")

        files.each do |file|
          puts Colors.blue("\n--- Analyzing #{file} ---")
          code = File.read(file)
          engine = Engine.new
          analysis = engine.analyze(code)
          puts analysis
        end
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
            puts Colors.green("Self-refactored: #{file} (backup: #{backup})")
          else
            puts Colors.yellow("Skipped #{file}: #{result[:error]}")
          end
        end
        if options[:converge]
          consecutive_no_changes = 0
          options_without_converge = options.dup
          options_without_converge.delete(:converge)
          while consecutive_no_changes < 3
            changes = self_refactor(options_without_converge)
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
          puts Colors.blue("Iteration #{iterations}")
          changes = false
          engine = Engine.new
          Dir.glob("#{MASTER.root}/lib/*.rb").each do |file|
            backup = file + ".iter#{iterations}.backup"
            FileUtils.cp(file, backup)
            code = File.read(file)
            result = engine.refactor(code)
            if result[:success]
              File.write(file, result[:code])
              puts Colors.green("Updated #{file}")
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
        puts Colors.green("Auto-iteration complete: #{iterations} iterations")
      end
    end
  end
end
