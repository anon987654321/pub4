# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require_relative "restructure/plan"
require_relative "restructure/syntax"
require_relative "restructure/proof"
require_relative "restructure/master_proof"
require_relative "restructure/rails_proof"
require_relative "restructure/script_proof"

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
      MAX_FILES = 48
      MAX_DELETES = 32
      MAX_WRITES = 24
      # What rules.yml paths.immutable names (the catalogue, the soul, the core
      # spine), from the repository root. An effect reads them and never writes.
      def self.immutable
        @immutable ||= Array((Master.load_rules || {}).dig("paths", "immutable")).map { |entry| "MASTER/#{entry}" }
      end
      REVIEW_DIFF_LINES = 800
      # Paths that mean something outside the tree. OPENBSD/etc, var, usr, home
      # and dotfiles mirror the box file for file; RAILS migrations and schema
      # are history the database has already run; STUDIO data and LoRA sets are
      # read by name and trained on.
      OFF_LIMITS = %r{\A(?:OPENBSD/(?:etc|var|usr|home|dotfiles)/|RAILS/.+/db/(?:migrate|schema)|
                     MASTER/tools/(?:lora|dilla/data)/)}x

      # Master and the directory modules open nearly every file, so a search for
      # what names a moved file leaves them out or finds the whole tree.
      def self.namespaces(tree_root)
        @namespaces ||= {}
        @namespaces[tree_root] ||= ["Master", *Dir.glob(File.join(tree_root, "lib", "**", "*/")).map do |dir|
          File.basename(dir).split("_").map(&:capitalize).join
        end].uniq
      end

      def initialize(repo_root:, tree: "MASTER", git: nil, proof: nil)
        @root = repo_root
        @tree = tree
        @git = git || Io::GitOperations.new(repo_root)
        @proof = proof || Proof.for(tree, repo_root)
      end

      # review takes the applied diff and answers nil to approve, or a reason.
      def call(plan, message:, review:)
        plan = ratcheted_plan(plan)
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
        return "#{plan.deletes.size} deletions, more than #{MAX_DELETES}" if plan.deletes.size > MAX_DELETES
        return "#{plan.writes.size} writes, more than #{MAX_WRITES}" if plan.writes.size > MAX_WRITES

        path_refusal(plan)
      end

      def ratcheted_plan(plan)
        return plan unless @tree == "MASTER"

        path = "MASTER/data/spine.yml"
        body = read(path)
        return plan unless body

        ceiling = body[/^  core_recursive_files: (\d+)$/, 1]&.to_i
        return plan unless ceiling

        predicted = core_recursive_files - plan.deletes.count { |entry| core_recursive_path?(entry) } +
                    plan.writes.count { |entry, _| core_recursive_path?(entry) && !File.exist?(full(entry)) }
        return plan unless predicted < ceiling

        writes = plan.writes.dup
        writes[path] = body.sub(/^  core_recursive_files: \d+$/, "  core_recursive_files: #{predicted}")
        Restructure::Plan.new(summary: plan.summary, writes:, deletes: plan.deletes)
      end

      def core_recursive_files
        Dir.glob(File.join(@root, "MASTER", "lib", "core", "**", "*.rb")).size
      end

      def core_recursive_path?(path)
        path.start_with?("MASTER/lib/core/") && path.end_with?(".rb")
      end

      def path_refusal(plan)
        outside = plan.paths.reject { |path| inside_tree?(path) }
        return "outside #{@tree}/, immutable or off limits: #{outside.first(3).join(", ")}" unless outside.empty?

        missing = plan.deletes.reject { |path| File.file?(File.join(@root, path)) }
        return "deletes what does not exist: #{missing.join(", ")}" unless missing.empty?

        dirty = plan.paths & changed_paths
        "has uncommitted changes: #{dirty.join(", ")}" unless dirty.empty?
      end

      def inside_tree?(path)
        path.start_with?("#{@tree}/") && !path.split("/").include?("..") && !immutable?(path) &&
          !path.match?(OFF_LIMITS)
      end

      def immutable?(path)
        Restructure.immutable.any? { |entry| entry.end_with?("/") ? path.start_with?(entry) : path == entry }
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
