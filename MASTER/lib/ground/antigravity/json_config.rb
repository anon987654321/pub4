# frozen_string_literal: true

require "json"

module Master
  module Ground
    module Antigravity
      # JsonConfig parses the Antigravity skills.json schema, resolving inherits,
      # entries, path resolution, and regex filtering.
      class JsonConfig
        def self.load(file_path, workspace_root: nil, visited: [])
          new(file_path, workspace_root:, visited:).resolve_entries
        end

        def initialize(file_path, workspace_root: nil, visited: [])
          @file_path = File.expand_path(file_path)
          @workspace_root = workspace_root || Dir.pwd
          @visited = visited
        end

        # Inherited entries first, then local ones: a config's own entries take
        # precedence over what it inherits, and the caller keeps the last of a
        # duplicate name.
        def resolve_entries
          return [] if @visited.include?(@file_path) || !File.file?(@file_path)

          data = parse_json(@file_path)
          return [] unless data.is_a?(Hash)

          inherited_entries(Array(data["inherits"])) + local_entries(Array(data["entries"]))
        end

        def resolve_path(path_str)
          return path_str if path_str.start_with?("/")
          return File.expand_path(path_str) if path_str.start_with?("~/")

          File.expand_path(path_str, @workspace_root)
        end

        private

        def inherited_entries(specs)
          visited = @visited + [@file_path]
          specs.flat_map do |spec|
            next [] unless spec.is_a?(Hash)

            path = spec["path"].to_s
            next [] if path.empty?

            loaded = self.class.load(resolve_path(path), workspace_root: @workspace_root, visited:)
            filter_entries(loaded, include_only: spec["include_only"], exclude: spec["exclude"])
          end
        end

        def local_entries(specs)
          specs.filter_map do |spec|
            next unless spec.is_a?(Hash)

            path = spec["path"].to_s
            next if path.empty?

            { path: resolve_path(path),
              include_only: Array(spec["include_only"]),
              exclude: Array(spec["exclude"]) }
          end
        end

        def parse_json(path)
          JSON.parse(File.read(path, encoding: "UTF-8"))
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "antigravity.json_config.parse", path:)
          nil
        end

        def filter_entries(entries, include_only:, exclude:)
          inc_patterns = Array(include_only).map { |p| Regexp.new(p) }
          exc_patterns = Array(exclude).map { |p| Regexp.new(p) }

          entries.select do |entry|
            base = File.basename(entry[:path])
            matches_inc = inc_patterns.empty? || inc_patterns.any? { |r| r.match?(base) }
            matches_exc = exc_patterns.any? { |r| r.match?(base) }
            matches_inc && !matches_exc
          end
        end
      end
    end
  end
end
