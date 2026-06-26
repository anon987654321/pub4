# frozen_string_literal: true

require "diffy"
require "fileutils"
require "json"
require "time"

module Master
  module Loop
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
        reload_pending!
      end

      def stage(path:, new_content:, tool: "unknown")
        old_content = File.exist?(path) ? File.read(path) : ""
        return Result.ok("no change") if old_content == new_content

        entry = nil
        @mutex.synchronize do
          @counter += 1
          entry = Entry.new(
            id: @counter,
            path: path,
            old_content: old_content,
            new_content: new_content,
            tool: tool,
            created_at: Time.now
          )
          @pending << entry
        end
        persist_entry(entry)
        @bus&.publish("stage:queued", id: entry.id, path: entry.path, stats: entry.diff_stats)
        Result.ok({ staged: true, id: entry.id, path: entry.path, stats: entry.diff_stats })
      end

      def pending = @pending.dup
      def empty? = @pending.empty?
      def size = @pending.size

      def apply(id: :all)
        targets = @mutex.synchronize { id == :all ? @pending.dup : @pending.select { |e| e.id == id } }
        applied = []
        targets.each do |entry|
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

      def stage_dir
        File.join(@root, ".master", "pending")
      end

      def reload_pending!
        @mutex.synchronize do
          @pending = []
          @counter = 0
          return unless Dir.exist?(stage_dir)

          Dir.glob(File.join(stage_dir, "*.json")).sort_by { |path| File.basename(path, ".json").to_i }.each do |json_path|
            meta = JSON.parse(File.read(json_path))
            id = meta["id"].to_i
            new_path = sidecar_path(id, :new)
            next unless File.exist?(new_path)

            old_path = sidecar_path(id, :old)
            entry = Entry.new(
              id: id,
              path: meta["path"],
              old_content: File.exist?(old_path) ? File.read(old_path) : "",
              new_content: File.read(new_path),
              tool: meta["tool"],
              created_at: Time.iso8601(meta["created_at"])
            )
            @pending << entry
            @counter = id if id > @counter
          end
        end
      rescue StandardError => e
        @bus&.publish("diff_stager:reload_error", error: e.message)
      end

      def persist_entry(entry)
        FileUtils.mkdir_p(stage_dir)
        File.write(
          File.join(stage_dir, "#{entry.id}.json"),
          JSON.generate({
            id: entry.id, path: entry.path, tool: entry.tool,
            created_at: entry.created_at.iso8601,
            stats: entry.diff_stats
          })
        )
        File.write(sidecar_path(entry.id, :old), entry.old_content)
        File.write(sidecar_path(entry.id, :new), entry.new_content)
      rescue StandardError => e
        @bus&.publish("diff_stager:persist_error", error: e.message)
      end

      def sidecar_path(id, kind)
        File.join(stage_dir, "#{id}.#{kind}")
      end

      def remove_persisted(entry)
        %w[json old new].each do |ext|
          path = File.join(stage_dir, "#{entry.id}.#{ext}")
          File.delete(path) if File.exist?(path)
        end
      rescue StandardError => e
        @bus&.publish("diff_stager:cleanup_error", error: e.message)
      end
    end
  end
end