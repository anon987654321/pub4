# frozen_string_literal: true

require "digest"
require_relative "name_review"
require_relative "file_rename"

module Master
  module Fix
    # After /fix's passes, reviews a few file names under the target and renames
    # the ones a clearer name would serve. Suspect names go first: the words the
    # naming rules call vague or sequential, and brand or scratch prefixes that
    # say nothing about the content. The rest take turns, a rotating slice per
    # run, so every eligible file is reviewed over enough runs.
    #
    # MASTER_FIX_RENAMES=0 switches it off; MASTER_FIX_RENAME_REVIEWS caps the
    # files reviewed per run, each costing two model calls.
    class RenameSweep
      REVIEWS = Integer(ENV.fetch("MASTER_FIX_RENAME_REVIEWS", 6))
      RENAMES = 2
      SUSPECT = /(?:\A_?(?:zen|x|my|new|old|tmp|temp|misc)_|(?:_|\A_?)(?:util|utils|misc|stuff|things|manager|handler|helper2|copy|final|latest|bak|v\d+)(?:_|\z)|\d+\z)/

      def initialize(agent:, repo_root:, bus: nil, review: nil, rename: nil)
        @repo_root = repo_root
        @bus = bus
        @review = review || NameReview.new(agent:)
        @rename = rename || FileRename.new(repo_root:)
      end

      def run(target:, run_id:)
        return [] if ENV["MASTER_FIX_RENAMES"] == "0"

        renamed = []
        candidates(target, run_id).first(REVIEWS).each do |path, reason|
          break if renamed.size >= RENAMES

          result = rename_one(path, reason)
          renamed << result.value! if result&.ok?
        end
        renamed
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
