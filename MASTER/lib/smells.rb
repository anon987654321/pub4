# frozen_string_literal: true

module MASTER
  module Smells
    MAX_METHOD_LINES = 20
    MAX_FILE_LINES = 300
    MAX_PARAMETERS = 4
    MAX_NESTING = 5
    MAX_PUBLIC_METHODS = 10
    MIN_DUPLICATE_COUNT = 3

    BLOATERS = {
      long_method: { check: "> #{MAX_METHOD_LINES} lines or > #{MAX_NESTING} nesting levels", fix: "Extract method" },
      god_class: { check: "> #{MAX_FILE_LINES} lines or > #{MAX_PUBLIC_METHODS} public methods", fix: "Extract class" },
      primitive_obsession: { check: "Repeated primitive patterns", fix: "Introduce value object" },
      long_parameter_list: { check: "> #{MAX_PARAMETERS} parameters", fix: "Parameter object" }
    }.freeze

    COUPLERS = {
      feature_envy: { check: "Method uses other class more than self", fix: "Move method" },
      inappropriate_intimacy: { check: "Classes know too much about each other", fix: "Extract class" },
      message_chains: { check: "Long chains like a.b.c.d", fix: "Hide delegate" }
    }.freeze

    DISPENSABLES = {
      dead_code: { check: "Unreachable or unused code", fix: "Delete it" },
      lazy_class: { check: "Class does almost nothing", fix: "Inline or merge" },
      duplicate_code: { check: "Same logic in multiple places", fix: "Extract method/class" }
    }.freeze

    ARCHITECTURE = {
      cyclic_dependency: { check: "A requires B requires A", fix: "Dependency inversion" },
      scattered_functionality: { check: "Related code in many files", fix: "Colocate" }
    }.freeze

    class << self
      # Load anti-patterns from principle YAML files
      def principle_patterns
        @principle_patterns ||= Principle.anti_patterns
      end

      def all_patterns
        static = BLOATERS.merge(COUPLERS).merge(DISPENSABLES).merge(ARCHITECTURE)
        dynamic = principle_patterns.each_with_object({}) do |ap, hash|
          key = ap[:name]&.to_sym
          hash[key] = { check: ap[:smell], fix: ap[:fix], principle: true } if key
        end
        static.merge(dynamic)
      end

      def analyze(code, file_path = nil)
        results = []
        lines = code.lines
        
        # Long method detection
        if file_path&.end_with?(".rb")
          results += analyze_ruby_methods(code, lines)
        end
        
        # Long file (god class indicator)
        if lines.size > MAX_FILE_LINES
          results << {
            smell: :god_class,
            message: "File has #{lines.size} lines (> #{MAX_FILE_LINES})",
            fix: BLOATERS[:god_class][:fix]
          }
        end
        
        # Long parameter lists
        code.scan(/def\s+\w+\(([^)]+)\)/) do |params|
          count = params[0].split(",").size
          if count > MAX_PARAMETERS
            results << {
              smell: :long_parameter_list,
              message: "Method has #{count} parameters (> #{MAX_PARAMETERS})",
              fix: BLOATERS[:long_parameter_list][:fix]
            }
          end
        end
        
        # Message chains (3+ chained calls)
        code.scan(/\w+(?:\.\w+){3,}/) do |chain|
          results << {
            smell: :message_chains,
            message: "Long chain: #{chain[0..40]}...",
            fix: COUPLERS[:message_chains][:fix]
          }
        end
        
        # Duplicate string literals (primitive obsession indicator)
        strings = code.scan(/"[^"]{10,}"/).flatten
        dupes = strings.group_by(&:itself).select { |_, v| v.size >= MIN_DUPLICATE_COUNT }
        dupes.each do |str, occurrences|
          results << {
            smell: :primitive_obsession,
            message: "String #{str[0..30]}... repeated #{occurrences.size}x",
            fix: "Extract to constant"
          }
        end
        
        results
      end
      
      def analyze_ruby_methods(code, lines)
        results = []
        method_starts = []
        nesting = 0
        
        lines.each_with_index do |line, idx|
          stripped = line.strip
          
          if stripped =~ /^\s*def\s+/
            method_starts << { line: idx + 1, nesting: nesting, name: stripped }
            nesting += 1
          elsif stripped == "end"
            if method_starts.any? && nesting > 0
              start = method_starts.pop
              length = idx - start[:line]
              if length > 20
                results << {
                  smell: :long_method,
                  message: "#{start[:name]} is #{length} lines (> 20)",
                  line: start[:line],
                  fix: BLOATERS[:long_method][:fix]
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
      
      def deep_nesting?(code, max_depth = 5)
        nesting = 0
        max_seen = 0
        
        code.each_line do |line|
          stripped = line.strip
          if stripped =~ /^\s*(def|class|module|if|unless|case|while|until|for|begin|do)\b/
            nesting += 1
            max_seen = [max_seen, nesting].max
          elsif stripped == "end"
            nesting = [0, nesting - 1].max
          end
        end
        
        max_seen > max_depth
      end
      
      def cyclic_deps?(files)
        deps = {}
        
        files.each do |f|
          next unless File.exist?(f)
          code = File.read(f, encoding: "UTF-8") rescue next
          requires = code.scan(/require(?:_relative)?\s+["']([^"']+)["']/).flatten
          deps[File.basename(f)] = requires.map { |r| File.basename(r) + ".rb" }
        end
        
        # Simple cycle detection
        deps.each do |file, required|
          required.each do |req|
            if deps[req]&.include?(File.basename(file, ".rb"))
              return { cycle: [file, req] }
            end
          end
        end
        
        nil
      end
      
      def report(results)
        return "No smells detected." if results.empty?
        
        output = "Found #{results.size} smell(s):\n\n"
        results.each_with_index do |r, i|
          output += "#{i + 1}. #{r[:smell]}: #{r[:message]}\n"
          output += "   Fix: #{r[:fix]}\n"
          output += "   Line: #{r[:line]}\n" if r[:line]
          output += "\n"
        end
        output
      end
    end
  end
end
