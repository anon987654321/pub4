# frozen_string_literal: true

module MASTER
  # CrossRef - Cross-reference analyzer for constants and methods
  module CrossRef
    extend self

    # Analyzer class for building reference maps
    class Analyzer
      attr_reader :constant_defs, :constant_uses, :method_defs, :method_calls

      def initialize
        @constant_defs = {}   # { constant_name => [file, line] }
        @constant_uses = {}   # { constant_name => [[file, line], ...] }
        @method_defs = {}     # { method_name => [file, line] }
        @method_calls = {}    # { method_name => [[file, line], ...] }
      end

      def analyze(files)
        files = [files] unless files.is_a?(Array)
        
        files.each do |file|
          next unless File.exist?(file) && file.end_with?(".rb")
          
          begin
            content = File.read(file)
            analyze_file(file, content)
          rescue StandardError
            # Skip files that can't be read
            next
          end
        end
        
        Result.ok(analyzer: self)
      end

      # Find unused constants
      def unused_constants
        @constant_defs.keys.reject { |name| @constant_uses[name]&.any? }
      end

      # Find uncalled public methods
      def uncalled_methods
        @method_defs.keys.reject { |name| @method_calls[name]&.any? }
      end

      # Find duplicate method calls in same method
      def duplicate_calls
        # Simplified: find methods that call the same method multiple times
        duplicates = []
        
        @method_defs.each do |method_name, location|
          # This is a simplified heuristic - proper implementation would need AST
          file, _line = location
          next unless File.exist?(file)
          
          content = File.read(file)
          method_match = content.match(/def\s+#{Regexp.escape(method_name)}.*?(?=def\s+|\z)/m)
          next unless method_match
          
          method_body = method_match[0]
          calls = method_body.scan(/\b([a-z_][a-z0-9_]*)\s*\(/).flatten
          
          call_counts = calls.group_by(&:itself).transform_values(&:count)
          repeated = call_counts.select { |_name, count| count > 2 }
          
          repeated.each do |called, count|
            duplicates << {
              method: method_name,
              file: file,
              calls: called,
              count: count
            }
          end
        end
        
        duplicates
      end

      # Generate audit report
      def to_audit_report
        report = if defined?(Audit::Report)
          Audit::Report.new
        else
          # Fallback if Audit not available
          OpenStruct.new(findings: [])
        end

        # Add findings for unused constants
        unused_constants.each do |const|
          location = @constant_defs[const]
          finding = if defined?(Audit::Finding)
            Audit::Finding.new(
              file: location[0],
              line: location[1],
              severity: :low,
              effort: :easy,
              category: :unused_code,
              message: "Constant '#{const}' is defined but never used",
              suggestion: "Remove if not needed, or use it"
            )
          end
          report.findings << finding if finding
        end

        # Add findings for uncalled methods
        uncalled_methods.each do |method|
          location = @method_defs[method]
          finding = if defined?(Audit::Finding)
            Audit::Finding.new(
              file: location[0],
              line: location[1],
              severity: :medium,
              effort: :moderate,
              category: :unused_code,
              message: "Method '#{method}' is defined but never called",
              suggestion: "Remove if dead code, or add tests"
            )
          end
          report.findings << finding if finding
        end

        report
      end

      private

      def analyze_file(file, content)
        lines = content.lines
        
        lines.each_with_index do |line, idx|
          line_num = idx + 1
          
          # Detect constant definitions (simplified)
          if line =~ /^\s*([A-Z][A-Z0-9_]*)\s*=/
            const_name = $1
            @constant_defs[const_name] = [file, line_num]
          end
          
          # Detect constant uses
          line.scan(/\b([A-Z][A-Z0-9_]*)\b/) do |match|
            const_name = match[0]
            @constant_uses[const_name] ||= []
            @constant_uses[const_name] << [file, line_num]
          end
          
          # Detect method definitions
          if line =~ /^\s*def\s+([a-z_][a-z0-9_?!]*)/
            method_name = $1
            @method_defs[method_name] = [file, line_num]
          end
          
          # Detect method calls (simplified)
          line.scan(/\b([a-z_][a-z0-9_]*)\s*\(/) do |match|
            method_name = match[0]
            @method_calls[method_name] ||= []
            @method_calls[method_name] << [file, line_num]
          end
        end
      end
    end
  end
end
