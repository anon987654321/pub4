# frozen_string_literal: true

require "date"
require "psych"
require "rbconfig"
require_relative "../review/scan/engines/path_filter"

module Master
  module Fix
    # Cheap, deterministic integrity checks that run before an expensive fix pass.
    # Findings are repairable; this is not a second policy engine. The scanner and
    # constitutional self-test remain the sources of rule findings.
    class Preflight
      RUBY_EXTENSIONS = %w[.rb .rake .ru .gemspec].freeze
      YAML_EXTENSIONS = %w[.yml .yaml].freeze

      def initialize(root:, bus: nil)
        @root = File.expand_path(root)
        @bus = bus
      end

      def findings(paths)
        Array(paths).filter_map do |path|
          next unless File.file?(path)
          next if Review::Scan::PathFilter.skip_path?(path, root: @root)

          return ruby_finding(path) if Master.language_for(path) == "ruby"

          case File.extname(path).downcase
          when *RUBY_EXTENSIONS
            ruby_finding(path)
          when *YAML_EXTENSIONS
            yaml_finding(path)
          end
        end
      end

      private

      def ruby_finding(path)
        source = File.read(path, encoding: "UTF-8", invalid: :replace, undef: :replace)
        if defined?(RubyVM::InstructionSequence)
          RubyVM::InstructionSequence.compile(source, path)
        else
          system(RbConfig.ruby, "-c", path, out: File::NULL, err: File::NULL) ||
            raise(SyntaxError, "Ruby syntax check failed")
        end
        nil
      rescue SyntaxError => e
        line = e.respond_to?(:lineno) ? e.lineno.to_i : 1
        finding(path:, line: line.positive? ? line : 1, message: "Ruby syntax error: #{e.message.lines.first.to_s.strip}")
      rescue StandardError => e
        finding(path:, line: 1, message: "Ruby preflight failed: #{e.class}: #{e.message}")
      end

      def yaml_finding(path)
        Psych.parse_file(path, filename: path)
        nil
      rescue Psych::Exception => e
        finding(path:, line: psych_line(e), message: "YAML parse error: #{e.message.lines.first.to_s.strip}")
      rescue StandardError => e
        finding(path:, line: 1, message: "YAML preflight failed: #{e.class}: #{e.message}")
      end

      def psych_line(error)
        location = error.respond_to?(:problem) ? error.problem : nil
        if error.respond_to?(:line) && error.line
          error.line.to_i
        elsif location.respond_to?(:line) && location.line
          location.line.to_i
        else
          1
        end
      rescue StandardError
        1
      end

      def finding(path:, line:, message:)
        relative = path.delete_prefix("#{@root}/")
        @bus&.publish("fix_loop:preflight_finding", file: relative, line:, message:)
        { rule: "PREFLIGHT", file: path, line:, message:, severity: :critical }
      end
    end
  end
end
