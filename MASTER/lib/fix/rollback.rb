# frozen_string_literal: true

require "open3"

module Master
  module Fix
    class Rollback
      ROLLBACK_CATEGORIES = %i[validation axiom_violation policy unknown provider_error llm_call_failure].freeze
      ROLLBACK_MSG_TRUNCATE = 120

      def initialize(root:, bus: nil)
        @root = root
        @bus = bus
      end

      def call(result)
        return false unless rollback_eligible?(result)

        category = result.category
        tag = "master:rollback:#{category}:#{Process.pid}"
        @bus&.publish("pipeline:rollback", category: category, message: result.message[0, ROLLBACK_MSG_TRUNCATE], tag: tag)
        @bus&.publish("ops:rollback", category: category, tag: tag)
        Master::Io::Exec.capture2e("git", "-C", @root, "stash", "push", "-u", "-m", tag)
        Master::Io::Exec.capture2e("git", "-C", @root, "reset", "--hard", "HEAD")
        true
      end

      private

      def rollback_eligible?(result)
        return false unless result.respond_to?(:err?) && result.err?

        ROLLBACK_CATEGORIES.include?(result.category) && git_workspace? && dirty?
      end

      def git_workspace?
        @root && Dir.exist?(File.join(@root, ".git"))
      end

      def dirty?
        out, _, status = Master::Io::Exec.capture3("git", "-C", @root, "status", "--porcelain")
        status.success? && !out.strip.empty?
      end
    end
  end
end
