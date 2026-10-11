# frozen_string_literal: true

require "fileutils"

module Master
  module Fix
    class WorktreeSession
      # The operator checkout holds uncommitted edits the isolated run does not
      # see; this reads them, copies them in on request, and tells the worker's
      # changes apart from the copied baseline.
      module DirtyEdits
        private

        def status_paths(root:)
          output = git_raw!("status", "--porcelain=v1", "-z", "--untracked-files=all", chdir: root)
          parse_nul_paths(output)
        end

        # Tracked files under the governed trees that differ from HEAD in the
        # operator's checkout. The isolated checkout is built from origin/main, so
        # none of these edits is in the run unless include_dirty copies them.
        def tracked_dirty(root: @repo_root)
          output = git_raw!("status", "--porcelain=v1", "-z", "--untracked-files=no", chdir: root)
          records = output.to_s.split("\0")
          entries = []
          index = 0
          while index < records.length
            record = records[index]
            break if record.empty?

            code = record[0, 2].to_s
            path = record[3..].to_s
            if code.match?(/[RC]/)
              index += 1
              entries << [" D", records[index].to_s] if code.include?("R") && !records[index].to_s.empty?
            end
            entries << [code, path] if TREES.include?(path.split("/").first)
            index += 1
          end
          entries
        end

        def announce_dirty(worktree, include_dirty:)
          entries = tracked_dirty
          return {} if entries.empty?

          paths = entries.map(&:last)
          shown = paths.first(8).join(", ") + (paths.size > 8 ? ", +#{paths.size - 8} more" : "")
          unless include_dirty
            announce("#{paths.size} uncommitted edit(s) in #{shown} are NOT in this run; --include-dirty copies them in")
            return {}
          end

          announce("#{paths.size} uncommitted edit(s) in #{shown} copied into this run (--include-dirty), not committed")
          copy_dirty(worktree, paths)
        end

        # Copies working-tree content of tracked files, never untracked ones, and
        # returns each path's content digest so own_dirty can tell the copied
        # baseline from what the worker changed.
        def copy_dirty(worktree, paths)
          paths.to_h do |path|
            source = File.join(@repo_root, path)
            target = File.join(worktree, path)
            if File.file?(source)
              FileUtils.mkdir_p(File.dirname(target))
              FileUtils.cp(source, target, preserve: true)
              [path, File.binread(target).hash]
            else
              FileUtils.rm_f(target)
              [path, nil]
            end
          end
        end

        def own_dirty(worktree, included)
          status_paths(root: worktree).reject do |path|
            next false unless included.key?(path)

            file = File.join(worktree, path)
            included[path].nil? ? !File.exist?(file) : (File.file?(file) && File.binread(file).hash == included[path])
          end
        end

        def parse_nul_paths(output)
          records = output.to_s.split("\0")
          paths = []
          index = 0
          while index < records.length
            record = records[index]
            break if record.empty?

            status = record[0, 2].to_s
            path = record[3..].to_s
            paths << path unless path.empty?
            if status.match?(/[RC]/)
              index += 1
              renamed = records[index].to_s
              paths << renamed unless renamed.empty?
            end
            index += 1
          end
          paths
        end
      end
    end
  end
end
