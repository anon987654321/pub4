# frozen_string_literal: true

require "yaml"

module Master
  module Ground
    # Answers whether a path falls under the sacred paths data/soul.yml declares:
    # the files no automated writer may change. Git history, not a checksum
    # store, records how a person changed them.
    class Immutability
      MANIFEST_REL = "data/soul.yml"
      Violation = Class.new(StandardError)

      def self.blocked?(path, root: Master::ROOT) = new(root:).blocked?(path)

      def initialize(root:)
        @root = File.expand_path(root)
      end

      def blocked?(relative_or_absolute)
        relative = normalize_relative(relative_or_absolute)
        sacred_declarations.any? do |declaration|
          prefix = declaration.delete_suffix("/")
          relative == prefix || relative.start_with?(prefix + File::SEPARATOR)
        end
      rescue ArgumentError
        true
      end

      private

      def sacred_declarations = declarations_in(manifest_path)

      # A root with no manifest of its own (a scratch tree, a test's tmpdir) is
      # held to MASTER's, so a missing file never makes a sacred path writable
      # and never refuses every write either. A manifest that exists and cannot
      # be read, or declares nothing, still fails closed.
      def manifest_path
        own = File.expand_path(MANIFEST_REL, @root)
        File.exist?(own) ? own : Master.data_path("soul.yml")
      end

      def declarations_in(path)
        raise Violation, "immutability: sacred manifest missing or unreadable: #{path}" unless File.readable?(path)

        soul = Master.load_yaml(path)
        paths = Array(soul&.dig("absolute", "sacred_paths"))
        raise Violation, "immutability: sacred manifest has no sacred_paths: #{path}" if paths.empty?

        paths.map { |entry| normalize_relative(entry) }.uniq
      end

      def normalize_relative(path)
        full = File.expand_path(path.to_s, @root)
        inside = full == @root || full.start_with?(@root + File::SEPARATOR)
        raise ArgumentError, "path escapes root: #{path}" unless inside

        full.delete_prefix(@root + File::SEPARATOR)
      end
    end
  end
end
