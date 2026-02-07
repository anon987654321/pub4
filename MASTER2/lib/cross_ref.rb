# frozen_string_literal: true

module MASTER
  # CrossRef - Cross-file static analysis
  # Builds constant-usage maps and method call graphs across Ruby files
  # Detects unused constants, uncalled public methods, and duplicate calls
  module CrossRef
    extend self

    class Analyzer
      attr_reader :files, :constants, :methods, :calls

      def initialize(files = [])
        @files = files
        @constants = {}      # { const_name => { defined_in: file, used_in: [files] } }
        @methods = {}        # { method_name => { defined_in: file, visibility: :public/:private, called_in: [files] } }
        @calls = {}          # { file => { method => count } }
        @scanned = false
      end

      def scan
        @files.each do |file|
          next unless File.exist?(file) && file.end_with?(".rb")

          begin
            code = File.read(file, encoding: "UTF-8")
            scan_file(file, code)
          rescue StandardError => e
            Logging.warn("CrossRef: Failed to scan #{file}: #{e.message}") if defined?(Logging)
          end
        end
        @scanned = true
        self
      end

      def unused_constants
        return [] unless @scanned

        @constants.select do |name, info|
          info[:used_in].empty? && !special_constant?(name)
        end.keys
      end

      def uncalled_public_methods
        return [] unless @scanned

        @methods.select do |name, info|
          info[:visibility] == :public &&
            info[:called_in].empty? &&
            !special_method?(name)
        end.keys
      end

      def duplicate_calls_in_method
        return {} unless @scanned

        duplicates = {}

        @calls.each do |file, method_calls|
          method_calls.each do |method, count|
            duplicates[file] ||= []
            duplicates[file] << { method: method, count: count } if count >= 3
          end
        end

        duplicates.select { |_, v| v.any? }
      end

      def generate_audit_report
        return nil unless defined?(MASTER::Audit)

        report = Audit::Report.new

        # Add findings for unused constants
        unused_constants.each do |const|
          info = @constants[const]
          report.add(Audit::Finding.new(
            type: :unused_constant,
            severity: :minor,
            effort: :low,
            file: info[:defined_in],
            message: "Constant #{const} is defined but never used",
            fix_suggestion: "Remove unused constant",
          ))
        end

        # Add findings for uncalled public methods
        uncalled_public_methods.each do |method|
          info = @methods[method]
          report.add(Audit::Finding.new(
            type: :uncalled_method,
            severity: :minor,
            effort: :low,
            file: info[:defined_in],
            message: "Public method #{method} is never called",
            fix_suggestion: "Make private or remove if unused",
          ))
        end

        # Add findings for duplicate calls
        duplicate_calls_in_method.each do |file, duplicates|
          duplicates.each do |dup|
            report.add(Audit::Finding.new(
              type: :duplicate_call,
              severity: :info,
              effort: :low,
              file: file,
              message: "Method #{dup[:method]} called #{dup[:count]} times in same scope",
              fix_suggestion: "Consider caching result",
            ))
          end
        end

        report
      end

      private

      def scan_file(file, code)
        lines = code.lines

        # Track constants
        code.scan(/^\s*([A-Z][A-Z_0-9]*)\s*=/) do |match|
          const_name = match[0]
          @constants[const_name] ||= { defined_in: file, used_in: [] }
        end

        # Track constant usage
        @constants.keys.each do |const|
          if code.match?(/\b#{Regexp.escape(const)}\b/) && !code.match?(/#{Regexp.escape(const)}\s*=/)
            @constants[const][:used_in] << file unless @constants[const][:used_in].include?(file)
          end
        end

        # Track method definitions
        code.scan(/^\s*def\s+(self\.)?(\w+)/) do |match|
          is_class_method = match[0]
          method_name = match[1]
          @methods[method_name] ||= {
            defined_in: file,
            visibility: :public,
            called_in: [],
          }
        end

        # Track private methods
        in_private = false
        lines.each do |line|
          in_private = true if line.strip == "private"
          in_private = false if line.strip =~ /^(public|protected)$/

          if in_private && line =~ /^\s*def\s+(\w+)/
            method_name = Regexp.last_match(1)
            @methods[method_name][:visibility] = :private if @methods[method_name]
          end
        end

        # Track method calls
        @methods.keys.each do |method|
          calls_in_file = code.scan(/\b#{Regexp.escape(method)}\b/).size
          # Subtract definition line
          calls_in_file -= 1 if code.match?(/def\s+#{Regexp.escape(method)}\b/)

          if calls_in_file > 0
            @methods[method][:called_in] << file unless @methods[method][:called_in].include?(file)
            @calls[file] ||= {}
            @calls[file][method] = calls_in_file
          end
        end
      end

      def special_constant?(name)
        # Constants that should not be flagged as unused
        %w[VERSION MODES FIXERS].include?(name)
      end

      def special_method?(name)
        # Methods that should not be flagged as uncalled
        %w[initialize setup teardown to_s inspect].include?(name) ||
          name.start_with?("test_")
      end
    end

    def analyze(files)
      analyzer = Analyzer.new(files)
      analyzer.scan
      Result.ok(analyzer: analyzer)
    rescue StandardError => e
      Result.err("CrossRef analysis failed: #{e.message}")
    end
  end
end
