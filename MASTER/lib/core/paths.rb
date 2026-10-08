# frozen_string_literal: true

require "yaml"

module Master
  module Core
    # One source for paths that are constitutionally protected.
    #
    # soul.yml owns identity and sacred paths. This class is deliberately small:
    # readers can ask for the declarations or whether one path is protected
    # without knowing how soul.yml is laid out.
    class Paths
      MANIFEST = "data/soul.yml"

      def self.sacred_paths(root:)
        new(root:).sacred_paths
      end

      def self.sacred?(path, root:)
        new(root:).sacred?(path)
      end

      def initialize(root:)
        @root = File.expand_path(root)
      end

      def sacred_paths
        @sacred_paths ||= begin
          manifest = File.join(@root, MANIFEST)
          soul = YAML.safe_load_file(manifest, aliases: true) || {}
          Array(soul.dig("absolute", "sacred_paths")).map(&:to_s).map { |path| normalize(path) }.uniq.freeze
        rescue Errno::ENOENT
          [].freeze
        end
      end

      def sacred?(path)
        relative = normalize(path)
        sacred_paths.any? do |entry|
          relative == entry || relative.start_with?("#{entry.delete_suffix("/")}/")
        end
      rescue ArgumentError
        true
      end

      private

      def normalize(path)
        full = File.expand_path(path.to_s, @root)
        raise ArgumentError, "path escapes root: #{path}" unless full == @root || full.start_with?("#{@root}/")

        full == @root ? "" : full.delete_prefix("#{@root}/")
      end
    end
  end
end
