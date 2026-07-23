# frozen_string_literal: true

require "diffy"
require "fileutils"
require "json"
require "time"

module Master
  module Fix
  # Intercepts file writes and stores diffs for human review.
  # When staging_enabled? in config, tools push here instead of writing directly.
  # CLI commands: /stage (list), /apply [n|all], /discard [n|all]
    class DiffStager
      Entry = Struct.new(:id, :path, :old_content, :new_content, :tool, :created_at, keyword_init: true) do
        def diff
          Diffy::Diff.new(old_content.to_s, new_content.to_s, context: 3)
        end

        def diff_stats
          lines = diff.to_s.lines
          added = lines.count { |l| l.start_with?("+") && !l.start_with?("+++") }
          removed = lines.count { |l| l.start_with?("-") && !l.start_with?("---") }
          "+#{added}/-#{removed}"
        end
      end

      def initialize(root:, event_bus: nil)
        @root = root
        @bus = event_bus
        @mutex = Mutex.new
        @pending = []
        @counter = 0
        load_persisted!
      end

      def stage(path:, new_content:, tool: "unknown")
        if Master::Ground::Immutability.blocked?(path, root: @root)
          return Result.err("immutable: #{relative(path)} is constitutionally protected", category: :validation)
        end

        old_content = File.exist?(path) ? File.read(path) : ""
        return Result.ok("no change") if old_content == new_content

        entry = build_entry(path:, old_content:, new_content:, tool:)
        persist_entry(entry)
        @bus&.publish("stage:queued", id: entry.id, path: entry.path, stats: entry.diff_stats)
        Result.ok({ staged: true, id: entry.id, path: entry.path, stats: entry.diff_stats })
      end

      def build_entry(path:, old_content:, new_content:, tool:)
        @mutex.synchronize do
          @counter += 1
          entry = Entry.new(
            id: @counter,
            path:,
            old_content:,
            new_content:,
            tool:,
            created_at: Time.now,
          )
          @pending << entry
          entry
        end
      end

      def pending = @pending.dup
      def empty? = @pending.empty?
      def size = @pending.size

      def apply(id: :all)
        targets = @mutex.synchronize { id == :all ? @pending.dup : @pending.select { |e| e.id == id } }
        applied = []
        targets.each do |entry|
          next if Master::Ground::Immutability.blocked?(entry.path, root: @root)

          FileUtils.mkdir_p(File.dirname(entry.path))
          tmp_path = "#{entry.path}.tmp.#{Process.pid}"
          File.write(tmp_path, entry.new_content)
          File.rename(tmp_path, entry.path)
          @mutex.synchronize { @pending.delete(entry) }
          remove_persisted(entry)
          @bus&.publish("stage:applied", id: entry.id, path: entry.path)
          applied << entry.path
        end
        applied
      end

      def discard(id: :all)
        targets = @mutex.synchronize { id == :all ? @pending.dup : @pending.select { |e| e.id == id } }
        targets.each do |entry|
          @mutex.synchronize { @pending.delete(entry) }
          remove_persisted(entry)
          @bus&.publish("stage:discarded", id: entry.id, path: entry.path)
        end
        targets.map(&:path)
      end

      def summary(pastel)
        return pastel.dim("  (no staged changes)") if @pending.empty?
        @pending.map do |e|
          short = e.path.sub(@root + "/", "")
          "  #{pastel.yellow("[#{e.id}]")} #{pastel.white(short)}" \
          " #{pastel.dim(e.diff_stats)} #{pastel.dim("via #{e.tool}")}"
        end.join("\n")
      end

      def render_diff(id, pastel)
        entry = @pending.find { |e| e.id == id }
        return pastel.red("no staged change with id #{id}") unless entry

        short = entry.path.sub(@root + "/", "")
        header = "#{pastel.bold(short)} #{pastel.dim(entry.diff_stats)}\n"
        diff_text = entry.diff.to_s
        diff_lines = diff_text.lines.map do |line|
          case line[0]
          when "+" then pastel.green(line.chomp)
          when "-" then pastel.red(line.chomp)
          when "@" then pastel.cyan(line.chomp)
          else pastel.dim(line.chomp)
          end
        end
        header + diff_lines.join("\n")
      end

      private

      def relative(path)
        File.expand_path(path, @root).delete_prefix(@root + File::SEPARATOR)
      end

      def stage_dir
        File.join(@root, ".master", "pending")
      end

      def persist_entry(entry)
        FileUtils.mkdir_p(stage_dir)
        File.write(
          File.join(stage_dir, "#{entry.id}.json"),
          JSON.generate({
            id: entry.id, path: entry.path, tool: entry.tool,
            old_content: entry.old_content, new_content: entry.new_content,
            created_at: entry.created_at.iso8601,
            stats: entry.diff_stats
          }),
        )
      rescue StandardError => e
        @bus&.publish("diff_stager:persist_error", error: e.message)
      end

      # Restores @pending from .master/pending/*.json sidecars written by a
      # prior process, so staged-but-not-yet-applied/discarded edits survive
      # a restart instead of silently vanishing from `pending`/`size` while
      # their sidecar files remain on disk forever.
      def load_persisted!
        return unless Dir.exist?(stage_dir)

        loaded = Dir.glob(File.join(stage_dir, "*.json")).filter_map { |f| load_entry(f) }
        return if loaded.empty?

        @pending = loaded.sort_by(&:id)
        @counter = @pending.map(&:id).max
      end

      def load_entry(path)
        data = JSON.parse(File.read(path), symbolize_names: true)
        Entry.new(
          id: data[:id], path: data[:path], tool: data[:tool],
          old_content: data[:old_content], new_content: data[:new_content],
          created_at: Time.parse(data[:created_at]),
        )
      rescue StandardError => e
        @bus&.publish("diff_stager:load_error", path:, error: e.message)
        nil
      end

      def remove_persisted(entry)
        persist_file = File.join(stage_dir, "#{entry.id}.json")
        # Removed after apply (written) or discard (abandoned) — safe to delete.
        File.delete(persist_file) if File.exist?(persist_file)
      rescue StandardError => e
        @bus&.publish("diff_stager:cleanup_error", error: e.message)
      end
    end
  end
end
