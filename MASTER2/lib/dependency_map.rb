# frozen_string_literal: true

module MASTER
  # Scans lib/ for require_relative, class/module definitions, and
  # MASTER:: references to build a dependency graph. Used to assess
  # whether a file is safe to split without breaking dependents.
  module DependencyMap
    DEPENDENT_RISK_THRESHOLD = 5

    module_function

    # Build the full dependency graph for all .rb files under root/lib
    def build(root: MASTER.root)
      lib_dir = File.join(root, "lib")
      files = Dir.glob(File.join(lib_dir, "**", "*.rb"))

      graph = {}
      files.each do |file|
        graph[file] = scan_file(file)
      end
      graph
    end

    # Determine if a file is safe to split based on how many other
    # files depend on symbols it defines.
    def safe_to_split?(file, graph: nil)
      graph ||= build
      entry = graph[file]
      return { dependents: 0, risk: :low } unless entry

      defined_symbols = entry[:defines]
      dependents = count_dependents(file, defined_symbols, graph)

      risk = dependents > DEPENDENT_RISK_THRESHOLD ? :high : :low
      { dependents: dependents, risk: risk }
    end

    # Parse a single file for its require_relative, definitions, and references
    def scan_file(file)
      return { requires: [], defines: [], references: [] } unless File.exist?(file)

      content = File.read(file)
      {
        requires: extract_requires(content),
        defines: extract_definitions(content),
        references: extract_references(content),
      }
    end

    def extract_requires(content)
      content.scan(/require_relative\s+["']([^"']+)["']/).flatten
    end

    def extract_definitions(content)
      content.scan(/(?:class|module)\s+([\w:]+)/).flatten
    end

    def extract_references(content)
      content.scan(/MASTER::\w+/).uniq
    end

    # Count how many files in the graph reference symbols defined by target
    def count_dependents(target_file, defined_symbols, graph)
      return 0 if defined_symbols.empty?

      pattern = Regexp.union(defined_symbols)
      graph.count do |file, entry|
        next false if file == target_file

        entry[:references].any? { |ref| ref.match?(pattern) }
      end
    end
  end
end
