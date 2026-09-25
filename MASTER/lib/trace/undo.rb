# frozen_string_literal: true

require "json"
require "fileutils"

module Master
  module Trace
  # Persistent undo: snapshots file content before writes, restores on demand.
  # Journal survives restarts via .master/undo_journal.jsonl.
  #
  # File-level, not turn-level. The branch is shared, so a turn's commit need
  # not be HEAD by the time anyone asks, and resetting it drops what landed after;
  # `git revert` of a commit a person names is that move. Fold writes go through
  # Core::World#do_write, which journals nothing, so after a fold turn undo!
  # restores the newest tool-path snapshot, which may be an earlier session's.
    class Undo
      include Master::Io::AtomicWrite

      MAX_JOURNAL = 50

      def initialize(session:, event_bus: nil, root: Dir.pwd)
        @session = session
        @bus = event_bus
        @root = root
        @journal = File.join(root, ".master", "undo_journal.jsonl")
        @stack = load_journal
      end

      def snapshot(path)
        @bus&.publish("voice:catchphrase", phrase: "Backing up first.", path:)
        content = File.exist?(path) ? File.read(path) : nil
        @session.snapshot(path, content)
        @stack << { "path" => path, "content" => content, "ts" => Time.now.to_i }
        @stack.shift while @stack.size > MAX_JOURNAL
        persist_journal
        Result.ok(path)
      rescue StandardError => e
        Result.err("undo snapshot: #{e.message}", category: :unknown)
      end

      def undo!(steps: 1) = replay(@stack, "undo", steps)

      def history(limit: 10)
        @stack.last(limit).reverse.map.with_index(1) do |entry, i|
          time = entry["ts"] ? Time.at(entry["ts"]).strftime("%H:%M:%S") : "?"
          "#{i}. #{entry["path"]} (#{time})"
        end
      end

      private

      # Pop the file's previous content off the stack and put it back.
      def replay(from, verb, steps)
        return Result.err("nothing to #{verb}", category: :validation) if from.empty?

        paths = []
        [steps, from.size].min.times do
          entry = from.pop
          restore(entry["path"], entry["content"])
          paths << entry["path"]
          @bus&.publish("#{verb}:applied", path: paths.last)
        end

        persist_journal
        Result.ok(paths.size == 1 ? paths.first : paths)
      end

      def restore(path, content)
        if content.nil?
          File.delete(path) if File.exist?(path)
        else
          write_atomic(path, content)
        end
      rescue StandardError => e
        delete_tmp_file(tmp_path) if defined?(tmp_path)
        raise
      end

      def load_journal
        return [] unless File.exist?(@journal)
        File.readlines(@journal).filter_map do |line|
          JSON.parse(line.strip)
        rescue JSON::ParserError => e
          Master::Ground::Swallow.log(e, context: "Undo.load_journal")
          nil
        end
      rescue StandardError => e
        @bus&.publish("undo:read_error", error: e.message) if defined?(@bus)
        []
      end

      def persist_journal
        write_atomic(@journal, @stack.map { |entry| "#{JSON.generate(entry)}\n" }.join)
      rescue StandardError => e
        delete_tmp_file(tmp_path) if defined?(tmp_path)
        raise
      end

      def delete_tmp_file(path)
        File.delete(path) if path && File.exist?(path)
      rescue StandardError => e
        @bus&.publish("undo:tmp_delete_error", error: e.message, path:)
      end
    end
  end
end
