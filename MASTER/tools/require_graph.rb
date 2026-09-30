# frozen_string_literal: true

require "json"

module Operator
  class RequireGraph
    TREES = %w[MASTER RAILS OPENBSD].freeze
    SKIP = %r{/(?:\.git|\.bundle|vendor|node_modules|tmp|log|coverage|storage|cache|output|knowledge|build|dist)(?:/|\z)}
    REQUIRE_RELATIVE = /require_relative\s+["']([^"']+)["']/

    def self.run(root:, trees: TREES)
      files = Array(trees).flat_map { |tree| Dir.glob(File.join(root, tree, "**", "*.rb")) }
                   .reject { |path| path.match?(SKIP) }
                   .sort
      broken = []

      files.each do |path|
        File.read(path).each_line.with_index(1) do |line, line_number|
          match = line.match(REQUIRE_RELATIVE)
          next unless match

          spec = match[1]
          target = File.expand_path(spec, File.dirname(path))
          next if File.file?(target) || File.file?("#{target}.rb")

          broken << {
            "file" => path.delete_prefix("#{root}/"),
            "line" => line_number,
            "require_relative" => spec,
            "target" => target.delete_prefix("#{root}/"),
          }
        end
      end

      {
        "root" => root,
        "scanned" => files.size,
        "broken" => broken,
        "clean" => broken.empty?,
      }
    end
  end
end

if $PROGRAM_NAME == __FILE__
  root = File.expand_path("../..", __dir__)
  report = Operator::RequireGraph.run(root:)
  if ARGV.include?("--json")
    puts JSON.pretty_generate(report)
  else
    report["broken"].each do |row|
      puts "require_graph: #{row["file"]}:#{row["line"]}: "            "require_relative #{row["require_relative"].inspect} "            "does not resolve to #{row["target"]} or #{row["target"]}.rb"
    end
    puts "require_graph: #{report["scanned"]} Ruby files scanned"
    puts "require_graph: #{report["broken"].empty? ? "clean" : "#{report["broken"].size} broken import(s)"}"
  end
  exit(report["clean"] ? 0 : 1)
end
