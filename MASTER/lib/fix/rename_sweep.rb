# frozen_string_literal: true

require "digest"
require_relative "name_review"
require_relative "file_rename"

module Master
  module Fix
    # /fix reviews names as part of structural cleanup. A tree-level run gets a
    # bounded first review; later passes rotate through the remaining names.
    # Suspect names go first: vague or sequential words and scratch prefixes that
    # say nothing about the content.
    #
    # MASTER_FIX_RENAMES=0 switches it off; MASTER_FIX_RENAME_REVIEWS caps the
    # files reviewed per run, each costing two model calls.
    class RenameSweep
      REVIEWS = Integer(ENV.fetch("MASTER_FIX_RENAME_REVIEWS", 6))
      RENAMES = 2
      FIRST_REVIEWS = 1
      FIRST_RENAMES = 1
      SUSPECT = /(?:\A_?(?:zen|x|my|new|old|tmp|temp|misc)_|(?:_|\A_?)(?:util|utils|misc|stuff|things|manager|handler|helper2|copy|final|latest|bak|v\d+)(?:_|\z)|\d+\z)/

      def initialize(agent:, repo_root:, bus: nil, review: nil, rename: nil)
        @repo_root = repo_root
        @bus = bus
        @review = review || NameReview.new(agent:)
        @rename = rename || FileRename.new(repo_root:)
      end

      def run(target:, run_id:, phase: :normal)
        return [] if ENV["MASTER_FIX_RENAMES"] == "0"

        reviews = phase == :structure_first ? FIRST_REVIEWS : REVIEWS
        limit = phase == :structure_first ? FIRST_RENAMES : RENAMES
        sweep_targets(target).flat_map do |tree_target|
          renamed = []
          candidates(tree_target, "#{run_id}-#{File.basename(tree_target)}").first(reviews).each do |path, reason|
            break if renamed.size >= limit

            result = rename_one(path, reason)
            renamed << result.value! if result&.ok?
          end
          renamed
        end
      end

      def sweep_targets(target)
        expanded = File.expand_path(target.to_s, @repo_root)
        return %w[MASTER RAILS OPENBSD STUDIO].filter_map do |tree|
          path = File.join(@repo_root, tree)
          path if File.directory?(path)
        end if expanded == File.expand_path(@repo_root)

        return [] unless %w[MASTER RAILS OPENBSD STUDIO].include?(File.basename(expanded))
        return [] unless File.dirname(expanded) == File.expand_path(@repo_root)

        [expanded]
      end

      def candidates(target, run_id)
        files = eligible(target)
        suspect, plain = files.partition { |path| File.basename(path).sub(/\..*\z/, "").match?(SUSPECT) }
        rotated = plain.empty? ? [] : plain.rotate(Digest::SHA256.hexdigest(run_id.to_s)[0, 8].to_i(16) % plain.size)
        suspect.map { |path| [path, "its name matches a vague, sequential or prefix-only pattern"] } +
          rotated.map { |path| [path, "routine review: does the name say what the file holds?"] }
      end

      private

      def eligible(target)
        base = File.expand_path(target.to_s, @repo_root)
        Dir.glob(File.join(base, "**", "*")).select { |path| File.file?(path) && FileRename.kind(path) }.sort
      end

      def rename_one(path, reason)
        name = @review.propose(path, reason:)
        return unless name

        result = @rename.call(path.delete_prefix("#{@repo_root}/"), name, reason: "#{File.basename(path)} -> #{name}: #{reason}")
        report(path, name, result)
        result
      end

      def report(path, name, result)
        line = result.ok? ? "renamed #{File.basename(path)} -> #{name}" : result.message
        Master::Trace::Dmesg.status("rename0", line)
        @bus&.publish("fix_loop:rename", path:, name:, ok: result.ok?, message: result.ok? ? nil : result.message)
      end
    end
  end
end
