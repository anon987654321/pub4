# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "time"
require "securerandom"
require_relative "../io/atomic_write"

module Master
  module Fix
    class Checkpoint
      include ::Master::Io::AtomicWrite

      MANIFEST_VERSION = 2

      class IntegrityError < StandardError; end

      attr_reader :root, :dir

      def initialize(root: Master::ROOT, dir: File.join(Master::ROOT, ".master", "checkpoints"))
        @root = File.expand_path(root)
        @dir = File.expand_path(dir)
      end

      def create(label:, files: [])
        id = "#{Time.now.utc.strftime("%Y%m%d%H%M%S")}-#{slug(label)}-#{SecureRandom.hex(4)}"
        normalized = Array(files).map { |path| normalize_relative(path) }
        target = File.join(dir, id)
        FileUtils.mkdir_p(target)
        copy_files(normalized, from: root, to: target)
        sha256 = file_checksums(normalized, from: target)
        manifest = {
          id:, label:, format_version: MANIFEST_VERSION,
          files: sha256.keys, sha256:, created_at: Time.now.utc.iso8601,
        }
        write_atomic(File.join(target, "manifest.json"), JSON.pretty_generate(manifest) + "\n", mode: 0o600)
        manifest
      end

      def list
        Dir.glob(File.join(dir, "*", "manifest.json")).filter_map do |path|
          JSON.parse(File.read(path, encoding: "UTF-8"))
        rescue JSON::ParserError => e
          Master::Ground::Swallow.log(e, context: "Checkpoint.list")
          nil
        end.sort_by { |row| row.fetch("created_at", "") }
      end

      def restore(id)
        checkpoint_dir = safe_checkpoint_dir(id)
        manifest_path = File.join(checkpoint_dir, "manifest.json")
        raise ArgumentError, "checkpoint not found: #{id}" unless File.file?(manifest_path)

        manifest = JSON.parse(File.read(manifest_path, encoding: "UTF-8"))
        files = Array(manifest["files"]).map { |path| normalize_relative(path) }
        verify_checksums!(manifest, files, checkpoint_dir:)
        copy_files(files, from: checkpoint_dir, to: root)
        manifest
      end

      private

      def file_checksums(files, from:)
        files.each_with_object({}) do |relative, checksums|
          path = File.join(from, relative)
          checksums[relative] = Digest::SHA256.file(path).hexdigest if File.file?(path)
        end
      end

      def verify_checksums!(manifest, files, checkpoint_dir:)
        # Manifests predating version 2 have no integrity metadata. Preserve
        # their historical restore behavior; every new checkpoint is verified
        # before any destination file is replaced.
        return if manifest["format_version"].nil? && !manifest.key?("sha256")

        unless manifest["format_version"] == MANIFEST_VERSION
          raise IntegrityError, "unsupported checkpoint manifest version: #{manifest["format_version"].inspect}"
        end

        checksums = manifest["sha256"]
        raise IntegrityError, "checkpoint manifest lacks SHA-256 checksums" unless checksums.is_a?(Hash)

        normalized = checksums.each_with_object({}) do |(relative, expected), result|
          result[normalize_relative(relative)] = expected
        end
        unless normalized.keys.sort == files.sort
          raise IntegrityError, "checkpoint manifest file list does not match its checksum list"
        end

        normalized.each do |relative, expected|
          source = File.join(checkpoint_dir, relative)
          raise IntegrityError, "checkpoint file is missing: #{relative}" unless File.file?(source)

          unless expected.is_a?(String) && expected.match?(/\A[0-9a-f]{64}\z/) &&
                 Digest::SHA256.file(source).hexdigest == expected
            raise IntegrityError, "checkpoint SHA-256 mismatch: #{relative}"
          end
        end
      end

      def slug(text)
        clean = text.to_s.downcase.gsub(/[^a-z0-9]+/, "-")
        clean.gsub(/\A-|-\z/, "")[0, 48]
      end

      # Expand lexically first, then reject symlinks in every existing path
      # component. File.expand_path alone leaves a path such as root/link/file
      # inside root even when link points outside it; restore would then write
      # through that link. Refuse symlinks rather than trying to infer whether
      # each target happens to remain inside the checkout.
      def normalize_relative(path)
        canonical_root = File.realpath(root)
        full = File.expand_path(path.to_s, canonical_root)
        unless full.start_with?(canonical_root + File::SEPARATOR)
          raise ArgumentError, "checkpoint path escapes root: #{path}"
        end

        relative = full.delete_prefix(canonical_root + File::SEPARATOR)
        current = canonical_root
        relative.split(File::SEPARATOR).each do |part|
          current = File.join(current, part)
          if File.symlink?(current)
            raise ArgumentError, "checkpoint path traverses symlink: #{path}"
          end
        end
        relative
      end

      def safe_checkpoint_dir(id)
        base = File.expand_path(dir)
        path = File.expand_path(id.to_s, base)
        unless path.start_with?(base + File::SEPARATOR)
          raise ArgumentError, "checkpoint id escapes store: #{id}"
        end

        if File.symlink?(path)
          raise ArgumentError, "checkpoint directory cannot be a symlink: #{id}"
        end
        if File.exist?(path)
          real_base = File.realpath(base)
          real_path = File.realpath(path)
          unless real_path.start_with?(real_base + File::SEPARATOR)
            raise ArgumentError, "checkpoint id escapes store: #{id}"
          end
        end

        path
      end

      def copy_files(files, from:, to:)
        files.each do |relative|
          source = File.join(from, relative)
          next unless File.file?(source)

          destination = File.join(to, relative)
          FileUtils.mkdir_p(File.dirname(destination))
          mode = File.stat(source).mode & 0o7777
          write_atomic(destination, File.binread(source), mode:)
        end
      end
    end
  end
end
