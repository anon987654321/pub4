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
      target = File.join(dir, id)
      FileUtils.mkdir_p(target)
      Array(files).each do |rel|
        src = File.join(root, rel.to_s)
        next unless File.file?(src)

        dst = File.join(target, rel.to_s)
        FileUtils.mkdir_p(File.dirname(dst))
        FileUtils.cp(src, dst)
      end
      manifest = { id: id, label: label, files: Array(files), created_at: Time.now.utc.iso8601 }
      File.write(File.join(target, "manifest.json"), JSON.pretty_generate(manifest))
      manifest
    end

    def list
      Dir.glob(File.join(dir, "*", "manifest.json")).filter_map do |path|
        JSON.parse(File.read(path, encoding: "utf-8"))
      rescue JSON::ParserError
        nil
      end.sort_by { |row| row.fetch("created_at", "") }
    end

    def restore(id)
      manifest_path = File.join(dir, id.to_s, "manifest.json")
      raise ArgumentError, "checkpoint not found: #{id}" unless File.file?(manifest_path)

      manifest = JSON.parse(File.read(manifest_path, encoding: "utf-8"))
      Array(manifest["files"]).each do |rel|
        src = File.join(dir, id.to_s, rel.to_s)
        next unless File.file?(src)

        dst = File.join(root, rel.to_s)
        FileUtils.mkdir_p(File.dirname(dst))
        FileUtils.cp(src, dst)
      end
      manifest
    end

    private

    def slug(text)
      clean = text.to_s.downcase.gsub(/[^a-z0-9]+/, "-")
      clean.gsub(/\A-|-\z/, "")[0, 48]
    end
  end
  end
end
