# frozen_string_literal: true

require "fileutils"
require "json"
require "time"

module Master
  module Ground
    class Checkpoint
      attr_reader :root, :dir

      def initialize(root: Master::ROOT, dir: File.join(Master::ROOT, ".master", "checkpoints"))
        @root = root
        @dir = dir
      end

      def create(label:, files: [])
        id = "#{Time.now.utc.strftime("%Y%m%d%H%M%S")}-#{slug(label)}"
        normalized = Array(files).map { |path| normalize_relative(path) }
        target = File.join(dir, id)
        FileUtils.mkdir_p(target)
        copy_files(normalized, from: root, to: target)
        manifest = { id:, label:, files: normalized, created_at: Time.now.utc.iso8601 }
        File.write(File.join(target, "manifest.json"), JSON.pretty_generate(manifest))
        manifest
      end

      def list
        Dir.glob(File.join(dir, "*", "manifest.json")).filter_map do |path|
          JSON.parse(File.read(path, encoding: "utf-8"))
        rescue JSON::ParserError => e
          Master::Ground::Swallow.log(e, context: "Checkpoint.list")
          nil
        end.sort_by { |row| row.fetch("created_at", "") }
      end

      def restore(id)
        checkpoint_dir = safe_checkpoint_dir(id)
        manifest_path = File.join(checkpoint_dir, "manifest.json")
        raise ArgumentError, "checkpoint not found: #{id}" unless File.file?(manifest_path)

        manifest = JSON.parse(File.read(manifest_path, encoding: "utf-8"))
        files = Array(manifest["files"]).map { |path| normalize_relative(path) }
        copy_files(files, from: checkpoint_dir, to: root)
        manifest
      end

      private

      def slug(text)
        clean = text.to_s.downcase.gsub(/[^a-z0-9]+/, "-")
        clean.gsub(/\A-|-\z/, "")[0, 48]
      end

      def normalize_relative(path)
        full = File.expand_path(path.to_s, root)
        unless full.start_with?(File.expand_path(root) + File::SEPARATOR)
          raise ArgumentError, "checkpoint path escapes root: #{path}"
        end

        full.delete_prefix(File.expand_path(root) + File::SEPARATOR)
      end

      def safe_checkpoint_dir(id)
        path = File.expand_path(id.to_s, dir)
        unless path.start_with?(File.expand_path(dir) + File::SEPARATOR)
          raise ArgumentError, "checkpoint id escapes store: #{id}"
        end

        path
      end

      def copy_files(files, from:, to:)
        files.each do |relative|
          source = File.join(from, relative)
          next unless File.file?(source)

          destination = File.join(to, relative)
          FileUtils.mkdir_p(File.dirname(destination))
          FileUtils.cp(source, destination)
        end
      end
    end
  end
end
