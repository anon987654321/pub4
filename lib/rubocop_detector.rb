# frozen_string_literal: true

module MASTER
  # RubocopDetector - Integration with RuboCop for style violation detection
  # Provides programmatic access to RuboCop's linting capabilities
  class RubocopDetector
    # Scan file for RuboCop violations
    # @param file_path [String] Path to Ruby file to scan
    # @return [Result] Ok with violations array, or Err with error message
    def self.scan(file_path)
      return Result.err("RuboCop not installed") unless installed?
      return Result.err("File not found: #{file_path}") unless File.exist?(file_path)

      begin
        require 'rubocop'
        
        # Configure RuboCop
        config_store = RuboCop::ConfigStore.new
        options = {
          formatters: [],
          force_exclusion: false,
        }
        
        # Create runner and process file
        runner = RuboCop::Runner.new(options, config_store)
        results = []
        
        # Temporarily capture offenses
        original_stdout = $stdout
        $stdout = StringIO.new
        
        begin
          # Run RuboCop on the file
          runner.run([file_path])
          
          # Access offenses through the runner's result cache
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

    # Scan multiple files
    # @param file_paths [Array<String>] Paths to Ruby files
    # @return [Result] Ok with aggregated results, or Err
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

    # Check if RuboCop is available
    # @return [Boolean] true if RuboCop gem is installed
    def self.installed?
      require 'rubocop'
      true
    rescue LoadError
      false
    end

    # Get RuboCop version if installed
    # @return [String, nil] Version string or nil if not installed
    def self.version
      return nil unless installed?
      require 'rubocop'
      RuboCop::Version.version
    end

    private

    # Format RuboCop offense into consistent hash
    # @param offense [RuboCop::Cop::Offense] RuboCop offense object
    # @return [Hash] Formatted offense data
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
