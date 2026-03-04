# frozen_string_literal: true

require "set"
require "pathname"

module MultiRefactor
  DEFAULT_GLOB = "**/*.rb"
  DEFAULT_ENCODING = "UTF-8"
  MAX_TOPO_SORT_PASSES = 10_000

  Result = Struct.new(
    :processed_files,
    :changed_files,
    :errors,
    keyword_init: true
  )

  class RefactorRunner
    def initialize(root_dir:, file_glob: DEFAULT_GLOB, strict: false, logger: Logging)
      @root_dir = Pathname(root_dir)
      @file_glob = file_glob
      @strict = strict
      @logger = logger
    end

    def run(rewrite_rules: nil)
      rewrite_rules = load_rewrite_rules(rewrite_rules)
      target_files = discover_files

      dependency_graph = build_dependency_graph(target_files, rewrite_rules)
      ordered_files = topological_sort(dependency_graph)

      result = Result.new(processed_files: [], changed_files: [], errors: [])
      ordered_files.each do |file_path|
        file_result = refactor_file(file_path, rewrite_rules)
        result.processed_files << file_path.to_s
        result.changed_files << file_path.to_s if file_result[:changed]
        result.errors << file_result[:error] if file_result[:error]
      end

      result
    end

    def strict_rewrite(source_text, rewrite_rules, file_path: nil)
      return source_text if source_text.nil? || source_text.empty?
      return source_text if rewrite_rules.nil? || rewrite_rules.empty?

      rewrite_rules.reduce(source_text) do |current_text, rule|
        apply_rule_strictly(current_text, rule, file_path:)
      end
    end

    def discover_files
      return [] unless @root_dir.exist?

      Dir.glob(@root_dir.join(@file_glob).to_s)
         .map { |p| Pathname(p) }
         .select(&:file?)
         .sort
    end

    private

    def load_rewrite_rules(explicit_rules)
      return explicit_rules unless explicit_rules.nil?

      if defined?(RewriteRule) && RewriteRule.respond_to?(:includes)
        RewriteRule.includes(:templates).to_a
      else
        []
      end
    rescue StandardError => e
      @logger.warn("MultiRefactor failed to load rewrite rules: #{e.class}: #{e.message}")
      []
    end

    def build_dependency_graph(file_paths, rewrite_rules)
      nodes = file_paths.map(&:to_s)
      graph = nodes.to_h { |n| [n, Set.new] }

      file_paths.each do |path|
        deps = parse_dependencies(path, rewrite_rules)
        deps.each do |dep|
          next unless graph.key?(dep)

          graph[path.to_s] << dep
        end
      end

      graph
    end

    def parse_dependencies(file_path, rewrite_rules)
      contents = safe_read(file_path)
      return [] if contents.nil? || contents.empty?

      references = []
      rewrite_rules.each do |rule|
        next unless rule.respond_to?(:dependency_patterns)

        patterns = rule.dependency_patterns
        next if patterns.nil?

        Array(patterns).each do |pattern|
          next unless pattern.is_a?(Regexp)

          contents.scan(pattern) { references << Regexp.last_match(1) if Regexp.last_match(1) }
        end
      end

      references.compact.uniq.map { |ref| @root_dir.join(ref).to_s }
    end

    def topological_sort(graph)
      incoming = Hash.new(0)
      graph.each_value { |deps| deps.each { |dep| incoming[dep] += 1 } }

      queue = graph.keys.select { |n| incoming[n].zero? }.sort
      output = []

      passes = 0
      until queue.empty?
        passes += 1
        raise "Topological sort exceeded safety limit" if passes > MAX_TOPO_SORT_PASSES

        node = queue.shift
        output << node

        graph.fetch(node, Set.new).each do |dep|
          incoming[dep] -= 1
          queue << dep if incoming[dep].zero?
        end

        queue.sort!
      end

      remaining = graph.keys - output
      output + remaining.sort
    end

    def refactor_file(file_path, rewrite_rules)
      original = safe_read(file_path)
      return { changed: false, error: nil } if original.nil?

      rewritten = @strict ? strict_rewrite(original, rewrite_rules, file_path:) : rewrite(original, rewrite_rules)
      return { changed: false, error: nil } if rewritten == original

      safe_write(file_path, rewritten)
      { changed: true, error: nil }
    rescue StandardError => e
      @logger.warn("MultiRefactor failed for #{file_path}: #{e.class}: #{e.message}")
      { changed: false, error: "#{file_path}: #{e.class}: #{e.message}" }
    end

    def rewrite(source_text, rewrite_rules)
      return source_text if rewrite_rules.nil? || rewrite_rules.empty?

      rewrite_rules.reduce(source_text) do |current_text, rule|
        apply_rule_leniently(current_text, rule)
      end
    end

    def apply_rule_leniently(source_text, rule)
      return source_text unless rule.respond_to?(:apply)

      rule.apply(source_text)
    rescue StandardError => e
      @logger.warn("MultiRefactor rule failed (lenient): #{rule_name(rule)}: #{e.class}: #{e.message}")
      source_text
    end

    def apply_rule_strictly(source_text, rule, file_path: nil)
      return source_text unless rule.respond_to?(:apply)

      rule.apply(source_text)
    rescue StandardError => e
      location = file_path ? " for #{file_path}" : ""
      @logger.warn("MultiRefactor rule failed (strict)#{location}: #{rule_name(rule)}: #{e.class}: #{e.message}")
      raise
    end

    def rule_name(rule)
      return rule.name if rule.respond_to?(:name) && rule.name

      rule.class.name || "AnonymousRule"
    end

    def safe_read(pathname)
      pathname.read(encoding: DEFAULT_ENCODING)
    rescue StandardError => e
      @logger.warn("MultiRefactor could not read #{pathname}: #{e.class}: #{e.message}")
      nil
    end

    def safe_write(pathname, contents)
      pathname.write(contents, mode: "wb")
      true
    rescue StandardError => e
      @logger.warn("MultiRefactor could not write #{pathname}: #{e.class}: #{e.message}")
      nil
    end
  end
end