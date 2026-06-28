# frozen_string_literal: true

module Master
  module Reach
    module PathGuard
      SACRED_PATHS = begin
        data = Master.load_yaml(Master.data_path("soul.yml"))
        Array(data.dig("absolute", "sacred_paths")).freeze
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "path_guard.sacred_paths")
        %w[data/ data/SOUL.md lib/judge/scan/ bin/cli].freeze
      end

      def self.inside_root?(full, root)
        full == root || full.start_with?(root + File::SEPARATOR)
      end

      def resolve(path)
        full = File.expand_path(path, @root)
        unless PathGuard.inside_root?(full, @root)
          return Result.err("path escapes project root: #{path}", category: :validation)
        end

        rel = full.delete_prefix(@root + "/")
        if sacred?(rel)
          return Result.err("path is sacred and cannot be written: #{rel}", category: :validation)
        end

        Result.ok(full)
      end

      private

      def sacred?(rel_path)
        Master::Ground::Immutability.blocked?(rel_path, root: @root) ||
          SACRED_PATHS.any? { |path| rel_path.start_with?(path) || rel_path == path.chomp("/") }
      end
    end
  end
end
