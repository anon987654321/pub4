# frozen_string_literal: true

require "open3"

module Master
  module Loop
    class FixLoop
      class FileCollector
        SKIP_DIRS = %w[vendor/ knowledge/ node_modules/ .git/ .bundle/ tmp/ log/ dist/].freeze

        def initialize(root:, bus: nil)
          @root = root
          @bus  = bus
        end

        def collect(target)
          tracked = collect_tracked(target)
          return tracked unless tracked.empty?

          Dir.glob(File.join(target, "**", "*"))
             .select { |f| File.file?(f) }
             .reject { |f| skipped?(f) }
             .sort
        end

        def collect_changed(target)
          changed = changed_since_last_commit(target)
          return collect(target) if changed.empty?
          changed
        rescue StandardError => e
          @bus&.publish("fix_loop:incremental_fallback", error: e.message)
          collect(target)
        end

        def mtimes(files)
          files.to_h { |path| [path, File.exist?(path) ? File.mtime(path).to_f : nil] }
        end

        def quiescent?(files, before)
          mtimes(files) == before
        rescue StandardError
          false
        end

        private

        def collect_tracked(target)
          out, _, status = Open3.capture3("git", "-C", @root, "ls-files", "-z")
          return [] unless status.success?

          out.split("\0").map { |rel| File.join(@root, rel) }
             .select { |file| File.file?(file) && under_path?(file, target) }
             .reject { |file| skipped?(file) }
             .sort
        rescue StandardError
          []
        end

        def changed_since_last_commit(target)
          out, _, status = Open3.capture3("git", "-C", @root, "diff", "--name-only", "HEAD")
          return [] unless status.success?

          out.lines.map(&:strip).reject(&:empty?)
             .map { |rel| File.join(@root, rel) }
             .select { |f| File.exist?(f) && f.start_with?(target) }
             .reject { |f| skipped?(f) }
             .sort
        end

        def skipped?(path)
          SKIP_DIRS.any? { |dir| path.include?(dir) } || binary?(path)
        end

        def binary?(path)
          File.file?(path) && File.binary?(path)
        rescue StandardError
          true
        end

        def under_path?(path, root)
          exp = File.expand_path(path)
          exp_root = File.expand_path(root)
          exp == exp_root || exp.start_with?("#{exp_root}#{File::SEPARATOR}")
        end
      end
    end
  end
end
