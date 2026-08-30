# frozen_string_literal: true

require "json"

module Master
  module Ground
    module Antigravity
      # JsonConfig parses Antigravity skills.json and plugins.json schemas,
      # resolving inherits, entries, path resolution, and regex filtering.
      class JsonConfig
        def self.load(file_path, workspace_root: nil, visited: [])
          new(file_path, workspace_root:, visited:).resolve_entries
        end

        def initialize(file_path, workspace_root: nil, visited: [])
          @file_path = File.expand_path(file_path)
          @workspace_root = workspace_root || Dir.pwd
          @visited = visited
        end

        def resolve_entries
          return [] if @visited.include?(@file_path) || !File.file?(@file_path)

          current_visited = @visited + [@file_path]
          data = parse_json(@file_path)
          return [] unless data.is_a?(Hash)

          entries = []

          # 1. Process inherits
          Array(data["inherits"]).each do |inherit_spec|
            next unless inherit_spec.is_a?(Hash)

            raw_path = inherit_spec["path"].to_s
            next if raw_path.empty?

            resolved_path = resolve_path(raw_path)
            inherited_entries = self.class.load(resolved_path, workspace_root: @workspace_root, visited: current_visited)

            filtered = filter_entries(inherited_entries,
                                      include_only: inherit_spec["include_only"],
                                      exclude: inherit_spec["exclude"])
            entries.concat(filtered)
          end

          # 2. Process local entries
          Array(data["entries"]).each do |entry_spec|
            next unless entry_spec.is_a?(Hash)

            raw_path = entry_spec["path"].to_s
            next if raw_path.empty?

            resolved_path = resolve_path(raw_path)
            entry_obj = {
              path: resolved_path,
              include_only: Array(entry_spec["include_only"]),
              exclude: Array(entry_spec["exclude"]),
            }
            entries << entry_obj
          end

          entries
        end

        def resolve_path(path_str)
          if path_str.start_with?("/")
            path_str
          elsif path_str.start_with?("~/")
            File.expand_path(path_str)
          else
            File.expand_path(path_str, @workspace_root)
          end
        end

        private

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
