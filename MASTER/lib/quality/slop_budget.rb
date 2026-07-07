# frozen_string_literal: true

require "open3"
require_relative "../master_paths"

module Quality
  Result = Struct.new(:changed_files, :added_lines, :deleted_lines, :todo_delta, :duplicate_basenames, :violations, keyword_init: true) do
    def ok? = violations.empty?
  end

  class SlopBudget
    DEFAULTS = {
      max_changed_files: 50,
      max_line_delta: 2_000,
      max_todo_delta: 10,
      max_duplicate_basenames: 25,
    }.freeze

    def initialize(root: MasterPaths.repo, budget: DEFAULTS)
      @root = root
      @budget = budget
    end

    def check
      files = changed_files
      added, deleted = line_delta
      todos = todo_delta(files)
      dups = duplicate_basenames
      violations = []
      violations << "changed files #{files.size} > #{@budget[:max_changed_files]}" if files.size > @budget[:max_changed_files]
      violations << "line delta #{added + deleted} > #{@budget[:max_line_delta]}" if added + deleted > @budget[:max_line_delta]
      violations << "TODO/FIXME delta #{todos} > #{@budget[:max_todo_delta]}" if todos > @budget[:max_todo_delta]
      violations << "duplicate basenames #{dups} > #{@budget[:max_duplicate_basenames]}" if dups > @budget[:max_duplicate_basenames]
      Result.new(changed_files: files, added_lines: added, deleted_lines: deleted, todo_delta: todos, duplicate_basenames: dups, violations: violations)
    end

    private

    def git(*args)
      stdout, status = Master::Reach::Exec.capture2e("git", *args, chdir: @root)
      raise "git #{args.join(" ")} failed: #{stdout}" unless status.success?
      stdout
    end

    def changed_files
      git("diff", "--name-only").lines.map(&:strip).reject(&:empty?)
    end

    def line_delta
      added = 0
      deleted = 0
      git("diff", "--numstat").each_line do |line|
        a, d, = line.split("\t")
        added += a.to_i
        deleted += d.to_i
      end
      [added, deleted]
    end

    def todo_delta(files)
      return 0 if files.empty?
      patch = git("diff")
      added = patch.lines.count { |line| line.start_with?("+") && line.match?(/TODO|FIXME/) }
      deleted = patch.lines.count { |line| line.start_with?("-") && line.match?(/TODO|FIXME/) }
      added - deleted
    end

    def duplicate_basenames
      files = Dir.glob(File.join(@root, "**/*")).select { |path| File.file?(path) }
      files.group_by { |path| File.basename(path) }.values.count { |paths| paths.size > 1 }
    end
  end
end
