# frozen_string_literal: true

require "digest"
require "fileutils"
require "yaml"

module Master
  module Ground
    # Verifies checksums for the sacred paths declared in data/soul.yml.
    class Immutability
      STORE_REL = "data/checksums.yml"
      SHA256 = /\A[0-9a-f]{64}\z/.freeze
      Violation = Class.new(StandardError)

      def self.verify!(root: Master::ROOT) = new(root:).verify!
      def self.regen!(root: Master::ROOT) = new(root:).regen!
      def self.blocked?(path, root: Master::ROOT) = new(root:).blocked?(path)

      def initialize(root:)
        @root = File.expand_path(root)
      end

      def verify!
        store = load_store
        return Result.ok(:no_checksums) if store.empty?

        drift = checksum_drift(store)
        return Result.ok(:clean) if drift.empty?

        raise Violation, format_drift(drift)
      end

      def regen!
        files = sacred_files
        return Result.err("immutability: no sacred files found", category: :validation) if files.empty?

        digests = build_digests(files)
        return digests if digests.is_a?(Result::Err)

        path = absolute(STORE_REL)
        write_store(path, digests)
        Result.ok(path)
      end

      def blocked?(relative_or_absolute)
        relative = normalize_relative(relative_or_absolute)
        return true if relative == STORE_REL

        sacred_declarations.any? do |declaration|
          prefix = declaration.delete_suffix("/")
          relative == prefix || relative.start_with?(prefix + File::SEPARATOR)
        end
      rescue ArgumentError
        true
      end

      private

      def checksum_drift(store)
        current = sacred_files
        paths = (store.keys + current).uniq.sort
        paths.filter_map do |relative|
          expected = store[relative]
          actual = current.include?(relative) ? sha256(absolute(relative)) : nil
          next if expected == actual && expected&.match?(SHA256)

          [relative, expected, actual]
        end
      end

      def load_store
        path = absolute(STORE_REL)
        return {} unless File.readable?(path)

        data = Master.load_yaml(path)
        raise Violation, "immutability: malformed checksum store" unless data.is_a?(Hash)

        data.transform_keys(&:to_s)
      end

      def sacred_declarations
        path = absolute("data/soul.yml")
        return [] unless File.readable?(path)

        soul = Master.load_yaml(path)
        Array(soul.dig("absolute", "sacred_paths")).map { |path| normalize_relative(path) }.uniq
      end

      def sacred_files
        files = sacred_declarations.flat_map do |declaration|
          full = absolute(declaration)
          File.directory?(full) ? files_under(full) : [declaration].select { File.file?(full) }
        end
        files.uniq.sort.reject { |relative| relative == STORE_REL }
      end

      def files_under(directory)
        Dir.glob(File.join(directory, "**", "*"), File::FNM_DOTMATCH)
           .select { |path| File.file?(path) }
           .map { |path| normalize_relative(path) }
           .reject { |relative| relative.split(File::SEPARATOR).any? { |part| part.start_with?(".") } }
      end

      def normalize_relative(path)
        full = File.expand_path(path.to_s, @root)
        unless full == @root || full.start_with?(@root + File::SEPARATOR)
          raise ArgumentError, "path escapes root: #{path}"
        end

        full.delete_prefix(@root + File::SEPARATOR)
      end

      def absolute(relative)
        File.expand_path(relative, @root)
      end

      def sha256(path)
        return unless File.readable?(path)

        Digest::SHA256.file(path).hexdigest
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "immutability.sha256", path:)
        nil
      end

      def build_digests(files)
        digests = files.to_h { |relative| [relative, sha256(absolute(relative))] }
        unreadable = digests.select { |_relative, digest| digest.nil? }.keys
        return digests if unreadable.empty?

        Result.err(
          "immutability: unreadable sacred files: #{unreadable.join(', ')}",
          category: :infrastructure,
        )
      end

      def write_store(path, digests)
        FileUtils.mkdir_p(File.dirname(path))
        temporary = "#{path}.tmp.#{Process.pid}"
        File.write(temporary, YAML.dump(digests), mode: "w", perm: 0o600)
        File.rename(temporary, path)
      ensure
        File.delete(temporary) if temporary && File.exist?(temporary)
      end

      def format_drift(drift)
        details = drift.map do |relative, expected, actual|
          "  #{relative}: expected #{short(expected)}, got #{short(actual)}"
        end
        ["immutability: #{drift.size} sacred file(s) drifted from checksums.yml:", *details,
         "Amend via: soul propose -> soul approve -> Immutability.regen!"].join("\n")
      end

      def short(value) = value&.slice(0, 12) || "(missing)"
    end
  end
end
