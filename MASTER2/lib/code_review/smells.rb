# frozen_string_literal: true

require "yaml"
require_relative "analyzers"

module MASTER
  # Code smell detection - complements Violations with structural analysis
  module Smells
    module_function

    def thresholds
      @thresholds ||= begin
        config = load_config
        {
          max_method_lines: config.dig("thresholds", "method_length") || 20,
          max_file_lines: config.dig("thresholds", "file_lines") || 600,
          max_parameters: config.dig("thresholds", "parameter_count") || 4,
          max_nesting: config.dig("thresholds", "nesting_depth") || 5,
          max_public_methods: config.dig("thresholds", "class_methods") || 10,
          min_duplicate_count: config.dig("thresholds", "min_duplicate_count") || 3,
        }
      end
    end

    def patterns
      @patterns ||= begin
        config = load_config
        bloaters = config["bloaters"] || default_bloaters
        couplers = config["couplers"] || default_couplers
        dispensables = config["dispensables"] || default_dispensables
        architecture = config["architecture"] || default_architecture
        rails = config["rails_specific"] || {}
        pwa = config["pwa_specific"] || {}
        html_css = config["html_css_quality"] || {}

        bloaters.merge(couplers).merge(dispensables).merge(architecture)
          .merge(rails).merge(pwa).merge(html_css)
      end
    end

    class << self
      def all_patterns
        patterns
      end

      def analyze(code, file_path = nil)
        results = []
        lines = code.lines
        limits = thresholds
        smell_patterns = patterns

        results += analyze_ruby_methods(code, lines) if file_path&.end_with?(".rb")

        if lines.size > limits[:max_file_lines]
          results << {
            smell: :god_class,
            message: "File has #{lines.size} lines (> #{limits[:max_file_lines]})",
            fix: smell_patterns.dig(:god_class, :fix) || smell_patterns.dig(:god_class, "fix") || "Extract class",
          }
        end

        code.scan(/def\s+\w+\(([^)]+)\)/) do |params|
          count = params[0].split(",").size
          if count > limits[:max_parameters]
            results << {
              smell: :long_parameter_list,
              message: "Method has #{count} parameters (> #{limits[:max_parameters]})",
              fix: smell_patterns.dig(:long_parameter_list, :fix) || smell_patterns.dig(:long_parameter_list, "fix") || "Parameter object",
            }
          end
        end

        code.scan(/\w+(?:\.\w+){3,}/) do |chain|
          results << {
            smell: :message_chains,
            message: "Long chain: #{chain[0..40]}...",
            fix: smell_patterns.dig(:message_chains, :fix) || smell_patterns.dig(:message_chains, "fix") || "Hide delegate",
          }
        end

        duplicates = Analyzers::RepeatedStringDetector.find(code, min_length: 10, min_count: limits[:min_duplicate_count])
        duplicates.each do |dup|
          str_preview = dup[:string].length > 30 ? "#{dup[:string][0...30]}..." : dup[:string]
          results << {
            smell: :primitive_obsession,
            message: "String #{str_preview} repeated #{dup[:count]}x",
            fix: "Extract to constant",
          }
        end

        results
      end

      def analyze_ruby_methods(code, _lines)
        results = []
        limits = thresholds
        smell_patterns = patterns

        methods_info = Analyzers::MethodLengthAnalyzer.scan(code)
        methods_info.each do |method|
          next unless method[:length] > limits[:max_method_lines]

          results << {
            smell: :long_method,
            message: "def #{method[:name]} is #{method[:length]} lines (> #{limits[:max_method_lines]})",
            line: method[:start_line],
            fix: smell_patterns.dig(:long_method, :fix) || smell_patterns.dig(:long_method, "fix") || "Extract method",
          }
        end

        results
      end

      def deep_nesting?(code, max_depth = nil)
        max_depth ||= thresholds[:max_nesting]
        max_seen = Analyzers::NestingAnalyzer.depth(code)
        max_seen > max_depth
      end

      def cyclic_deps?(files)
        deps = {}

        files.each do |f|
          next unless File.exist?(f)

          code = begin
            File.read(f, encoding: "UTF-8")
          rescue StandardError
            next
          end
          requires = code.scan(/require(?:_relative)?\s+["']([^"']+)["']/).flatten
          deps[File.basename(f)] = requires.map { |r| "#{File.basename(r)}.rb" }
        end

        deps.each do |file, required|
          required.each do |req|
            return { cycle: [file, req] } if deps[req]&.include?(File.basename(file, ".rb"))
          end
        end

        false
      end

      def report(results)
        return "No smells detected." if results.empty?

        output = ["Code Smells (#{results.size})", ""]
        results.each_with_index do |smell_item, idx|
          output << "  #{idx + 1}. #{smell_item[:smell]}"
          output << "     #{smell_item[:message]}"
          output << "     Fix: #{smell_item[:fix]}"
          output << "     Line #{smell_item[:line]}" if smell_item[:line]
          output << ""
        end
        output.join("\n")
      end

      private

      def load_config
        path = Paths.data_file("smells.yml")
        YAML.safe_load_file(path, permitted_classes: [Symbol])
      rescue Errno::ENOENT
        {}
      end

      def default_bloaters
        t = thresholds
        {
          "long_method" => { "check" => "> #{t[:max_method_lines]} lines", "fix" => "Extract method" },
          "god_class" => { "check" => "> #{t[:max_file_lines]} lines", "fix" => "Extract class" },
          "primitive_obsession" => { "check" => "Repeated primitive patterns", "fix" => "Introduce value object" },
          "long_parameter_list" => { "check" => "> #{t[:max_parameters]} parameters", "fix" => "Parameter object" },
        }
      end

      def default_couplers
        {
          "feature_envy" => { "check" => "Method uses other class more than self", "fix" => "Move method" },
          "inappropriate_intimacy" => { "check" => "Classes know too much", "fix" => "Extract class" },
          "message_chains" => { "check" => "Long chains like a.b.c.d", "fix" => "Hide delegate" },
        }
      end

      def default_dispensables
        {
          "dead_code" => { "check" => "Unreachable or unused code", "fix" => "Delete it" },
          "lazy_class" => { "check" => "Class does almost nothing", "fix" => "Inline or merge" },
          "duplicate_code" => { "check" => "Same logic in multiple places", "fix" => "Extract method/class" },
        }
      end

      def default_architecture
        {
          "cyclic_dependency" => { "check" => "A requires B requires A", "fix" => "Dependency inversion" },
          "scattered_functionality" => { "check" => "Related code in many files", "fix" => "Colocate" },
        }
      end
    end
  end
end
