# frozen_string_literal: true

module Master
  module Io
    # Applies a governed replacement across text files and optional filenames.
    class BatchReplace
      include Master::Ground::AtomicWrite
      include PathGuard

      TIER = :guarded
      NAME = "replace".freeze
      DESCRIPTION = "Find and replace text across all files in a directory.".freeze
      SAFE_EXTENSIONS = %w[.rb .erb .yml .yaml .md .sh .js .css .html .json .txt].freeze

      def initialize(root:, governor:, event_bus: nil)
        @root = File.realpath(root)
        @governor = governor
        @bus = event_bus
      end

      def call(old_str:, new_str:, dir: nil, rename_files: false)
        permission = @governor.permit?(NAME, TIER, "#{old_str} → #{new_str}")
        return permission if permission.err?

        target = resolve_target(dir)
        return target if target.err?

        @bus&.publish("tool:before", tool: NAME, old: old_str, new: new_str)
        @refused = []
        changed = replace_contents(target.value!, old_str, new_str)
        changed += rename_paths(target.value!, old_str, new_str) if rename_files
        Result.ok("replaced in #{changed} file(s)#{refused_note}")
      rescue StandardError => e
        Result.err("replace: #{e.message}", category: :unknown)
      end

      private

      def resolve_target(directory)
        target = directory ? File.expand_path(directory, @root) : @root
        return Result.ok(target) if PathGuard.inside_root?(target, @root)

        Result.err("replace: path escapes root: #{directory}", category: :validation)
      end

      # This tool predates Io::Base and writes through AtomicWrite, so it misses
      # commit_write's guard. A bulk edit is the easiest way to introduce the
      # same violation in fifty files at once, so it is the last one that should
      # be exempt. Per file, not per batch: one refusal must not lose the rest.
      def replace_contents(target, old_string, new_string)
        candidate_paths(target).count do |path|
          content = read_text(path)
          next false unless content&.include?(old_string)

          updated = content.gsub(old_string, new_string)
          verdict = Master::Review::Scan::WriteGuard.default.verdict(path:, content: updated)
          next refuse(path, verdict) if verdict.blocked?

          write_atomic(path, updated)
          record_change(path)
          true
        end
      end

      def refuse(path, verdict)
        @refused << path
        @bus&.publish("write:guard", path:, introduced: verdict.introduced.size, blocked: true)
        false
      end

      def refused_note
        return "" if @refused.empty?

        " — #{@refused.size} refused, each would introduce a finding: #{@refused.join(", ")}"
      end

      def rename_paths(target, old_string, new_string)
        candidate_paths(target).count do |path|
          next false unless File.basename(path).include?(old_string)

          destination = File.join(File.dirname(path), File.basename(path).gsub(old_string, new_string))
          next rename_conflict(path, destination) if File.exist?(destination)

          File.rename(path, destination)
          record_change(destination)
          true
        end
      end

      def candidate_paths(target)
        Dir.glob(File.join(target, "**", "*")).select do |path|
          File.file?(path) && SAFE_EXTENSIONS.include?(File.extname(path)) && !sacred?(relative(path))
        end
      end

      def read_text(path)
        File.read(path, encoding: "UTF-8")
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "batch_replace.read", event_bus: @bus, path:)
        nil
      end

      def record_change(path)
        Master::Trace::WriteTracker.current&.record(path)
        @bus&.publish("tool:after", tool: NAME, path:)
      end

      def rename_conflict(source, destination)
        @bus&.publish("tool:rename_conflict", tool: NAME, source:, destination:)
        false
      end

      def relative(path) = path.delete_prefix(@root + File::SEPARATOR)
    end
  end
end
