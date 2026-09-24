# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require_relative "restructure/plan"
require_relative "restructure/proof"

module Master
  module Fix
    # Applies one multi-file restructure (a split, a merge, a flattened
    # directory, code gathered from where it had scattered) and keeps it only
    # when a hostile review approves the diff and the proof holds. Otherwise
    # every file is put back as it was. One commit per restructure, so a bad
    # one is one revert.
    #
    # The single-file repair loop cannot do this: it returns one corrected file
    # per answer, and a split answered as one file came back UNCHANGED.
    class Restructure
      MAX_FILES = 12
      # The kernel and the rule catalogue are read, never written by an effect.
      IMMUTABLE = %w[MASTER/data/rules.yml MASTER/data/soul.yml].freeze
      REVIEW_DIFF_LINES = 800

      # Master and the directory modules open nearly every file, so a search for
      # what names a moved file leaves them out or finds the whole tree.
      def self.namespaces(master_root)
        @namespaces ||= {}
        @namespaces[master_root] ||= ["Master", *Dir.glob(File.join(master_root, "lib", "**", "*/")).map do |dir|
          File.basename(dir).split("_").map(&:capitalize).join
        end].uniq
      end

      def initialize(repo_root:, tree: "MASTER", git: nil, proof: nil)
        @root = repo_root
        @tree = tree
        @git = git || Io::GitOperations.new(repo_root)
        @proof = proof || Proof.new(master_root: File.join(repo_root, tree))
      end

      # review takes the applied diff and answers nil to approve, or a reason.
      def call(plan, message:, review:)
        refusal = refusal_for(plan)
        return Result.err("restructure refused: #{refusal}", category: :policy) if refusal

        before = @proof.baseline(plan)
        originals = snapshot(plan)
        apply(plan)
        failure = review.call(diff(plan, originals)) || @proof.failure(plan, before)
        return undo(originals, failure) if failure

        commit(plan, message)
      rescue StandardError => e
        originals ? undo(originals, "#{e.class}: #{e.message}") : Result.err("restructure: #{e.message}")
      end

      private

      def refusal_for(plan)
        return "the plan names no files" if plan.empty?
        return "#{plan.paths.size} files, more than #{MAX_FILES}" if plan.paths.size > MAX_FILES

        path_refusal(plan)
      end

      def path_refusal(plan)
        outside = plan.paths.reject { |path| inside_tree?(path) }
        return "outside #{@tree}/ or immutable: #{outside.first(3).join(", ")}" unless outside.empty?

        missing = plan.deletes.reject { |path| File.file?(File.join(@root, path)) }
        return "deletes what does not exist: #{missing.join(", ")}" unless missing.empty?

        dirty = plan.paths & changed_paths
        "has uncommitted changes: #{dirty.join(", ")}" unless dirty.empty?
      end

      def inside_tree?(path)
        path.start_with?("#{@tree}/") && !path.split("/").include?("..") && !IMMUTABLE.include?(path)
      end

      def changed_paths
        @git.status_lines(nil).map { |line| line[3..].to_s.strip }
      end

      def snapshot(plan)
        plan.paths.to_h { |path| [path, read(path)] }
      end

      def apply(plan)
        plan.writes.each do |path, content|
          FileUtils.mkdir_p(File.dirname(full(path)))
          File.write(full(path), content)
        end
        plan.deletes.each { |path| File.delete(full(path)) }
      end

      def undo(originals, failure)
        originals.each do |path, content|
          if content
            FileUtils.mkdir_p(File.dirname(full(path)))
            File.write(full(path), content)
          elsif File.exist?(full(path))
            File.delete(full(path))
          end
        end
        Result.err("restructure undone: #{failure}", category: :validation)
      end

      def commit(plan, message)
        @git.git!("add", "-A", "--", *plan.paths)
        @git.git!("commit", "-m", message, "-m", Master::Core::World::COMMIT_TRAILER, "--", *plan.paths)
        @git.push
        Result.ok(summary: plan.summary, files: plan.paths.size, head: @git.head)
      end

      # The whole change as one unified diff, new and deleted files included.
      def diff(plan, originals)
        Dir.mktmpdir("restructure") do |dir|
          lines = plan.paths.flat_map { |path| file_diff(dir, path, originals[path]) }
          next lines.join if lines.size <= REVIEW_DIFF_LINES

          "#{lines.first(REVIEW_DIFF_LINES).join}… #{lines.size - REVIEW_DIFF_LINES} more lines\n"
        end
      end

      def file_diff(dir, path, original)
        before = File.join(dir, "before")
        after = File.join(dir, "after")
        File.write(before, original.to_s)
        File.write(after, File.exist?(full(path)) ? File.read(full(path)) : "")
        out, = Master::Io::Exec.capture2e("git", "diff", "--no-index", "--no-color", "-U4", before, after)
        ["--- #{original ? path : "/dev/null"}\n+++ #{File.exist?(full(path)) ? path : "/dev/null"}\n",
         *out.lines.drop_while { |line| !line.start_with?("@@") }]
      end

      def read(path) = File.file?(full(path)) ? File.read(full(path)) : nil
      def full(path) = File.join(@root, path)
    end
  end
end
