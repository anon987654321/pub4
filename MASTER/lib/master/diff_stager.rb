# frozen_string_literal: true

require "diffy"
require "fileutils"
require "json"

module Master
  # DiffStager — intercepts file writes and stores diffs for human review.
  # When staging_enabled? in config, tools push here instead of writing directly.
  # CLI commands: /stage (list), /apply [n|all], /discard [n|all]
  class DiffStager
    Entry = Struct.new(:id, :path, :old_content, :new_content, :tool, :created_at, keyword_init: true) do
      def diff
        Diffy::Diff.new(old_content.to_s, new_content.to_s, context: 3)
      end

      def diff_stats
        lines  = diff.to_s.lines
        added  = lines.count { |l| l.start_with?("+") && !l.start_with?("+++") }
        removed = lines.count { |l| l.start_with?("-") && !l.start_with?("---") }
        "+#{added}/-#{removed}"
      end
    end

    def initialize(root:, event_bus: nil)
      @root    = root
      @bus     = event_bus
      @pending = []
      @counter = 0
    end

    # Called by tools instead of writing directly. Returns a Result.
    def stage(path:, new_content:, tool: "unknown")
      old_content = File.exist?(path) ? File.read(path) : ""
      return Result.ok("no change") if old_content == new_content

      @counter += 1
      entry = Entry.new(
        id:          @counter,
        path:        path,
        old_content: old_content,
        new_content: new_content,
        tool:        tool,
        created_at:  Time.now
      )
      @pending << entry
      persist_entry(entry)
      @bus&.publish("stage:queued", id: entry.id, path: path, stats: entry.diff_stats)
      Result.ok({ staged: true, id: entry.id, path: path, stats: entry.diff_stats })
    end

    def pending = @pending.dup
    def empty?  = @pending.empty?
    def size    = @pending.size

    # Apply one or all entries. Returns array of applied paths.
    def apply(id: :all)
      targets = id == :all ? @pending.dup : @pending.select { |e| e.id == id }
      applied = []
      targets.each do |entry|
        FileUtils.mkdir_p(File.dirname(entry.path))
        File.write(entry.path, entry.new_content)
        @pending.delete(entry)
        remove_persisted(entry)
        @bus&.publish("stage:applied", id: entry.id, path: entry.path)
        applied << entry.path
      end
      applied
    end

    # Discard one or all without writing.
    def discard(id: :all)
      targets = id == :all ? @pending.dup : @pending.select { |e| e.id == id }
      targets.each do |entry|
        @pending.delete(entry)
        remove_persisted(entry)
        @bus&.publish("stage:discarded", id: entry.id, path: entry.path)
      end
      targets.map(&:path)
    end

    # Colored summary for CLI display
    def summary(pastel)
      return pastel.dim("  (no staged changes)") if @pending.empty?
      @pending.map do |e|
        short = e.path.sub(@root + "/", "")
        "  #{pastel.yellow("[#{e.id}]")} #{pastel.white(short)} #{pastel.dim(e.diff_stats)} #{pastel.dim("via #{e.tool}")}"
      end.join("\n")
    end

    # Colored unified diff for one entry
    def render_diff(id, pastel)
      entry = @pending.find { |e| e.id == id }
      return pastel.red("no staged change with id #{id}") unless entry

      short = entry.path.sub(@root + "/", "")
      header = "#{pastel.bold(short)} #{pastel.dim(entry.diff_stats)}\n"
      diff_lines = entry.diff.to_s.lines.map do |line|
        case line[0]
        when "+" then pastel.green(line.chomp)
        when "-" then pastel.red(line.chomp)
        when "@" then pastel.cyan(line.chomp)
        else          pastel.dim(line.chomp)
        end
      end
      header + diff_lines.join("\n")
    end

    private

    def stage_dir
      File.join(@root, ".master", "pending")
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
    rescue StandardError
      nil
    end

    def remove_persisted(entry)
      f = File.join(stage_dir, "#{entry.id}.json")
      File.delete(f) if File.exist?(f)
    rescue StandardError
      nil
    end
  end
end
