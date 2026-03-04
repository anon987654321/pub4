# frozen_string_literal: true

require "json"
require "fileutils"
require "time"

module DbJsonl
  class Tables
    DEFAULT_EXT = ".jsonl"

    def initialize(root_dir:, ext: DEFAULT_EXT)
      @root_dir = root_dir.to_s
      @ext = ext.to_s
      FileUtils.mkdir_p(@root_dir)
    end

    def list
      Dir.glob(File.join(@root_dir, "*#{@ext}"))
         .map { |p| File.basename(p, @ext) }
         .sort
    end

    def table_path(name)
      return if name.nil? || name.to_s.strip.empty?

      File.join(@root_dir, "#{name}#{@ext}")
    end

    def ensure_table(name)
      path = table_path(name)
      return unless path

      FileUtils.mkdir_p(File.dirname(path))
      FileUtils.touch(path)
      path
    end

    def insert(table, row, meta: {})
      path = ensure_table(table)
      return unless path
      return unless row.is_a?(Hash)

      record = build_record(row, meta)
      json = JSON.generate(record)

      File.open(path, "a:utf-8") { |f| f.puts(json) }
      true
    rescue Errno::ENOENT, Errno::EACCES
      false
    rescue JSON::GeneratorError
      false
    end

    def each_row(table)
      return enum_for(__method__, table) unless block_given?

      path = table_path(table)
      return unless path && File.file?(path)

      File.foreach(path, encoding: "utf-8") do |line|
        line = line.strip
        next if line.empty?

        obj = parse_json(line)
        next unless obj

        yield obj
      end
      nil
    end

    def count(table)
      path = table_path(table)
      return 0 unless path && File.file?(path)

      File.foreach(path, encoding: "utf-8").count { |line| !line.strip.empty? }
    rescue Errno::ENOENT, Errno::EACCES
      0
    end

    def delete(table)
      path = table_path(table)
      return false unless path && File.exist?(path)

      File.delete(path)
      true
    rescue Errno::ENOENT
      false
    rescue Errno::EACCES
      false
    end

    private

    def build_record(row, meta)
      created_at = meta.fetch(:created_at, nil) || now_iso8601
      updated_at = meta.fetch(:updated_at, nil) || created_at

      {
        "data" => row,
        "meta" => {
          "created_at" => created_at,
          "updated_at" => updated_at,
          "source" => meta.fetch(:source, nil)
        }.compact
      }
    end

    def parse_json(line)
      JSON.parse(line)
    rescue JSON::ParserError
      nil
    end

    def now_iso8601
      Time.now.utc.iso8601
    end
  end
end