# frozen_string_literal: true

module MASTER
  class RubocopDetector
    def self.scan(file_path)
      return Result.err("RuboCop not installed") unless installed?
      return Result.err("File not found: #{file_path}") unless File.exist?(file_path)

      begin
        require 'rubocop'
        
        config_store = RuboCop::ConfigStore.new
        options = {
          formatters: [],
          force_exclusion: false,
        }
        
        runner = RuboCop::Runner.new(options, config_store)
        results = []
        
        original_stdout = $stdout
        $stdout = StringIO.new
        
        begin
          runner.run([file_path])
          
          if runner.instance_variable_defined?(:@result_cache)
            cache = runner.instance_variable_get(:@result_cache)
            if cache && cache[file_path]
              cache[file_path].offenses.each do |offense|
                results << format_offense(offense)
              end
            end
          end
        ensure
          $stdout = original_stdout
        end
        
        Result.ok(violations: results, file: file_path, count: results.size)
      rescue LoadError
        Result.err("RuboCop gem not available")
      rescue StandardError => e
        Result.err("RuboCop scan failed: #{e.message}")
      end
    end

    def self.scan_multiple(file_paths)
      return Result.err("RuboCop not installed") unless installed?
      
      all_results = []
      file_paths.each do |path|
        result = scan(path)
        if result.ok?
          all_results << result.value
        else
          return result  # Early exit on error
        end
      end
      
      total_violations = all_results.sum { |r| r[:count] }
      Result.ok(
        files: all_results,
        total_violations: total_violations,
        files_scanned: file_paths.size
      )
    end

    def self.installed?
      require 'rubocop'
      true
    rescue LoadError
      false
    end

    def self.version
      return nil unless installed?
      require 'rubocop'
      RuboCop::Version.version
    end

    private

    def self.format_offense(offense)
      {
        line: offense.line,
        column: offense.column,
        severity: offense.severity.name,
        message: offense.message,
        cop_name: offense.cop_name,
        correctable: offense.correctable?,
        corrected: offense.corrected?,
      }
    end
  end
end
