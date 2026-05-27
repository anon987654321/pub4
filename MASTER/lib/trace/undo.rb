# frozen_string_literal: true

require "json"
require "fileutils"

module Master
  module Trace
  # Persistent undo: snapshots file content before writes, restores on demand.
  # Journal survives restarts via .master/undo_journal.jsonl.
  class Undo
    MAX_JOURNAL = 50

    def initialize(session:, event_bus: nil, root: Dir.pwd)
      @session = session
      @bus = event_bus
      @root = root
      @journal = File.join(root, ".master", "undo_journal.jsonl")
      @stack = load_journal
      @redo = []
    end

    def snapshot(path)
      content = File.exist?(path) ? File.read(path) : nil
      @session.snapshot(path, content)
      @stack << { "path" => path, "content" => content, "ts" => Time.now.to_i }
      @stack.shift while @stack.size > MAX_JOURNAL
      persist_journal
      Result.ok(path)
    rescue StandardError => e
      Result.err("undo snapshot: #{e.message}", category: :unknown)
    end

    def undo!(steps: 1)
      return Result.err("nothing to undo", category: :validation) if @stack.empty?

      steps = [steps, @stack.size].min
      paths = []

      steps.times do
        entry = @stack.pop
        current = File.exist?(entry["path"]) ? File.read(entry["path"]) : nil
        @redo << { "path" => entry["path"], "content" => current, "ts" => Time.now.to_i }
        restore(entry["path"], entry["content"])
        paths << entry["path"]
        @bus&.publish("undo:applied", path: paths.last)
      end

      persist_journal
      Result.ok(paths.size == 1 ? paths.first : paths)
    end

    def redo!(steps: 1)
      return Result.err("nothing to redo", category: :validation) if @redo.empty?

      steps = [steps, @redo.size].min
      paths = []
      steps.times do
        entry = @redo.pop
        current = File.exist?(entry["path"]) ? File.read(entry["path"]) : nil
        @stack << { "path" => entry["path"], "content" => current, "ts" => Time.now.to_i }
        restore(entry["path"], entry["content"])
        paths << entry["path"]
        @bus&.publish("redo:applied", path: paths.last)
      end

      persist_journal
      Result.ok(paths.size == 1 ? paths.first : paths)
    end

    def depth = @stack.size

    def history(limit: 10)
      @stack.last(limit).reverse.map.with_index(1) do |entry, i|
        time = entry["ts"] ? Time.at(entry["ts"]).strftime("%H:%M:%S") : "?"
        "#{i}. #{entry["path"]} (#{time})"
      end
    end

    private

    def restore(path, content)
      if content.nil?
        File.delete(path) if File.exist?(path)
      else
        tmp_path = "#{path}.tmp.#{Process.pid}"
        File.write(tmp_path, content)
        File.rename(tmp_path, path)
      end
    rescue StandardError => e
      File.delete(tmp_path) if defined?(tmp_path) && File.exist?(tmp_path) rescue nil
      raise
    end

    def load_journal
      return [] unless File.exist?(@journal)
      File.readlines(@journal).filter_map do |line|
        JSON.parse(line.strip)
      rescue JSON::ParserError
        nil
      end
    rescue StandardError => e
      @bus&.publish("undo:read_error", error: e.message) if defined?(@bus)
      []
    end

    def persist_journal
      FileUtils.mkdir_p(File.dirname(@journal))
      tmp_path = "#{@journal}.tmp.#{Process.pid}"
      File.open(tmp_path, "w") { |f| @stack.each { |entry| f.puts(JSON.generate(entry)) } }
      File.rename(tmp_path, @journal)
    rescue StandardError => e
      File.delete(tmp_path) if defined?(tmp_path) && File.exist?(tmp_path) rescue nil
      raise
    end
  end
  end
end
