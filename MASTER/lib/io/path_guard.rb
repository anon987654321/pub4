# frozen_string_literal: true

module Master
  module Io
    module PathGuard
      SACRED_PATHS = begin
        data = Master.load_yaml(Master.data_path("soul.yml"))
        Array(data.dig("absolute", "sacred_paths")).freeze
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "path_guard.sacred_paths")
        raise "path guard: sacred-path policy unreadable: #{e.class}: #{e.message}"
      end

      def self.inside_root?(full, root)
        full == root || full.start_with?(root + File::SEPARATOR)
      end

      # expand_path does not follow symlinks, so a link inside the root that
      # points at /etc passes the prefix check. The realpath of the nearest
      # existing ancestor must sit under the real root too, the same walk
      # Core::World#within makes. `root` is already a realpath.
      def self.inside_real_root?(full, root)
        return false unless inside_root?(full, root)

        existing = full
        existing = File.dirname(existing) until File.exist?(existing)
        inside_root?(File.realpath(existing), root)
      rescue SystemCallError
        false
      end

      # Credential files inside the checkout are refused for reads as well as
      # writes, by the rule Core::World applies to its own reads.
      def self.secret?(path)
        Master::Core::World.secret?(path)
      end

      # Sacred paths are read-yes, write-never: soul.yml and rules.yml are the
      # law MASTER must read before it acts. Only a caller that writes asks.
      def resolve(path, write: true)
        full = File.expand_path(path, @root)
        unless PathGuard.inside_real_root?(full, @root)
          return Result.err("path escapes project root: #{path}", category: :validation)
        end
        return Result.err("credential path refused: #{path}", category: :validation) if PathGuard.secret?(full)

        rel = full.delete_prefix(@root + "/")
        if write && sacred?(rel)
          return Result.err("sacred path — writes forbidden: #{rel}", category: :validation)
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
