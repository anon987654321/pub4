# frozen_string_literal: true

require 'yaml'

module MASTER
  # Code smell detection - complements Violations with structural analysis
  module Smells
    extend self

    def thresholds
      @thresholds ||= begin
        config = load_config
        {
          max_method_lines: config.dig('thresholds', 'method_length') || 20,
          max_file_lines: config.dig('thresholds', 'file_lines') || 300,
          max_parameters: config.dig('thresholds', 'parameter_count') || 4,
          max_nesting: config.dig('thresholds', 'nesting_depth') || 5,
          max_public_methods: config.dig('thresholds', 'class_methods') || 10,
          min_duplicate_count: config.dig('thresholds', 'min_duplicate_count') || 3
        }
      end
    end

    def patterns
      @patterns ||= begin
        config = load_config
        bloaters = config['bloaters'] || default_bloaters
        couplers = config['couplers'] || default_couplers
        dispensables = config['dispensables'] || default_dispensables
        architecture = config['architecture'] || default_architecture
        rails = config['rails_specific'] || {}
        pwa = config['pwa_specific'] || {}
        html_css = config['html_css_quality'] || {}
        
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
        t = thresholds
        p = patterns

        results += analyze_ruby_methods(code, lines) if file_path&.end_with?('.rb')

        if lines.size > t[:max_file_lines]
          results << {
            smell: :god_class,
            message: "File has #{lines.size} lines (> #{t[:max_file_lines]})",
            fix: p.dig(:god_class, :fix) || p.dig(:god_class, 'fix') || 'Extract class'
          }
        end

        code.scan(/def\s+\w+\(([^)]+)\)/) do |params|
          count = params[0].split(',').size
          if count > t[:max_parameters]
            results << {
              smell: :long_parameter_list,
              message: "Method has #{count} parameters (> #{t[:max_parameters]})",
              fix: p.dig(:long_parameter_list, :fix) || p.dig(:long_parameter_list, 'fix') || 'Parameter object'
            }
          end
        end

        code.scan(/\w+(?:\.\w+){3,}/) do |chain|
          results << {
            smell: :message_chains,
            message: "Long chain: #{chain[0..40]}...",
            fix: p.dig(:message_chains, :fix) || p.dig(:message_chains, 'fix') || 'Hide delegate'
          }
        end

        strings = code.scan(/"[^"]{10,}"/).flatten
        dupes = strings.group_by(&:itself).select { |_, v| v.size >= t[:min_duplicate_count] }
        dupes.each do |str, occurrences|
          results << {
            smell: :primitive_obsession,
            message: "String #{str[0..30]}... repeated #{occurrences.size}x",
            fix: 'Extract to constant'
          }
        end

        results
      end

      def analyze_ruby_methods(code, lines)
        results = []
        method_starts = []
        nesting = 0
        t = thresholds
        p = patterns

        lines.each_with_index do |line, idx|
          stripped = line.strip

          if stripped =~ /^\s*def\s+/
            method_starts << { line: idx + 1, nesting: nesting, name: stripped }
            nesting += 1
          elsif stripped == 'end'
            if method_starts.any? && nesting.positive?
              start = method_starts.pop
              length = idx - start[:line]
              if length > t[:max_method_lines]
                results << {
                  smell: :long_method,
                  message: "#{start[:name]} is #{length} lines (> #{t[:max_method_lines]})",
                  line: start[:line],
                  fix: p.dig(:long_method, :fix) || p.dig(:long_method, 'fix') || 'Extract method'
                }
              end
            end
            nesting = [0, nesting - 1].max
          elsif stripped =~ /^\s*(class|module|if|unless|case|while|until|for|begin|do)\b/
            nesting += 1
          end
        end

        results
      end

      def deep_nesting?(code, max_depth = nil)
        max_depth ||= thresholds[:max_nesting]
        nesting = 0
        max_seen = 0

        code.each_line do |line|
          stripped = line.strip
          if stripped =~ /^\s*(def|class|module|if|unless|case|while|until|for|begin|do)\b/
            nesting += 1
            max_seen = [max_seen, nesting].max
          elsif stripped == 'end'
            nesting = [0, nesting - 1].max
          end
        end

        max_seen > max_depth
      end

      def cyclic_deps?(files)
        deps = {}

        files.each do |f|
          next unless File.exist?(f)

          code = File.read(f, encoding: 'UTF-8') rescue next
          requires = code.scan(/require(?:_relative)?\s+["']([^"']+)["']/).flatten
          deps[File.basename(f)] = requires.map { |r| "#{File.basename(r)}.rb" }
        end

        deps.each do |file, required|
          required.each do |req|
            return { cycle: [file, req] } if deps[req]&.include?(File.basename(file, '.rb'))
          end
        end

        nil
      end

      def report(results)
        return 'No smells detected.' if results.empty?

        output = ["Code Smells (#{results.size})", '']
        results.each_with_index do |r, i|
          output << "  #{i + 1}. #{r[:smell]}"
          output << "     #{r[:message]}"
          output << "     Fix: #{r[:fix]}"
          output << "     Line #{r[:line]}" if r[:line]
          output << ''
        end
        output.join("\n")
      end

      private

      def load_config
        path = File.join(MASTER.root, 'data', 'smells.yml')
        YAML.load_file(path)
      rescue Errno::ENOENT
        {}
      end

      def default_bloaters
        t = thresholds
        {
          'long_method' => { 'check' => "> #{t[:max_method_lines]} lines", 'fix' => 'Extract method' },
          'god_class' => { 'check' => "> #{t[:max_file_lines]} lines", 'fix' => 'Extract class' },
          'primitive_obsession' => { 'check' => 'Repeated primitive patterns', 'fix' => 'Introduce value object' },
          'long_parameter_list' => { 'check' => "> #{t[:max_parameters]} parameters", 'fix' => 'Parameter object' }
        }
      end

      def default_couplers
        {
          'feature_envy' => { 'check' => 'Method uses other class more than self', 'fix' => 'Move method' },
          'inappropriate_intimacy' => { 'check' => 'Classes know too much', 'fix' => 'Extract class' },
          'message_chains' => { 'check' => 'Long chains like a.b.c.d', 'fix' => 'Hide delegate' }
        }
      end

      def default_dispensables
        {
          'dead_code' => { 'check' => 'Unreachable or unused code', 'fix' => 'Delete it' },
          'lazy_class' => { 'check' => 'Class does almost nothing', 'fix' => 'Inline or merge' },
          'duplicate_code' => { 'check' => 'Same logic in multiple places', 'fix' => 'Extract method/class' }
        }
      end

      def default_architecture
        {
          'cyclic_dependency' => { 'check' => 'A requires B requires A', 'fix' => 'Dependency inversion' },
          'scattered_functionality' => { 'check' => 'Related code in many files', 'fix' => 'Colocate' }
        }
      end
    end
  end
end
