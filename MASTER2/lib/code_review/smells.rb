# frozen_string_literal: true

require "yaml"

module CodeReview
  module Paths
    def self.load_data_file(path)
      YAML.safe_load(File.read(path), permitted_classes: [], aliases: true) || {}
    rescue Errno::ENOENT, Psych::SyntaxError
      {}
    end
  end

  class Smells
    THRESHOLDS_KEY = "thresholds"
    EXTRACT_CLASS = "Extract class"
    OUTPUT_APPEND_PREFIX = "\n          output << "
    DEFAULT_THRESHOLD = 10

    def initialize(project:, repo:, data_path:)
      @project = project
      @repo = repo
      @data_path = data_path
    end

    def analyze
      config = load_config
      thresholds = config.fetch(THRESHOLDS_KEY, {})

      smells = fetch_smells
      return [] if smells.empty?

      report = []
      smells.each do |smell|
        next unless smell.exceeded?(thresholds)

        report << build_entry(smell)
      end

      report
    end

    def cyclic_deps?
      deps = dependency_graph
      return false if deps.empty?

      nodes = deps.keys | deps.values.flatten
      visited = {}
      in_stack = {}

      nodes.any? do |node|
        next false if visited[node]

        cycle_from?(node, deps, visited, in_stack)
      end
    end

    private

    def load_config
      path = File.join(@data_path, "config.yml")
      Paths.load_data_file(path)
    end

    def fetch_smells
      return [] unless @repo.respond_to?(:smells)

      relation = @repo.smells
      relation = relation.includes(:association) if relation.respond_to?(:includes)
      relation.to_a
    end

    def build_entry(smell)
      parts = []
      append_output(parts, EXTRACT_CLASS) if smell.extract_class?
      append_output(parts, thresholds_line(smell))
      parts.join
    end

    def thresholds_line(smell)
      threshold = smell.threshold || DEFAULT_THRESHOLD
      %(#{THRESHOLDS_KEY}: #{threshold})
    end

    def append_output(parts, text)
      parts << "#{OUTPUT_APPEND_PREFIX}#{text.inspect}"
    end

    def dependency_graph
      path = File.join(@data_path, "dependencies.yml")
      data = Paths.load_data_file(path)
      (data["dependencies"] || {}).transform_values { |value| Array(value) }
    end

    def cycle_from?(start_node, graph, visited, in_stack)
      stack = [[start_node, graph[start_node] || [], 0]]

      while (frame = stack.last)
        node, neighbors, index = frame

        unless visited[node]
          visited[node] = true
          in_stack[node] = true
        end

        if index >= neighbors.length
          in_stack.delete(node)
          stack.pop
          next
        end

        neighbor = neighbors[index]
        frame[2] += 1

        return true if in_stack[neighbor]

        next if visited[neighbor]

        stack << [neighbor, graph[neighbor] || [], 0]
      end

      false
    end
  end
end