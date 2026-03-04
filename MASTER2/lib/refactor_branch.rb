# frozen_string_literal: true

require "open3"

module MASTER
  # Ensures file mutations in refactor mode happen on a dedicated branch,
  # never directly on main/master/develop.
  #
  # Called by file_write before the first write when:
  #   Capabilities.level >= 2 AND intent == :refactor
  #
  # Behaviour:
  #   - Already on a safe branch (not main/master/develop) → no-op
  #   - On a protected branch → create master/refactor/<request_id> and check it out
  #   - Not in a git repo → no-op (warn only)
  module RefactorBranch
    PROTECTED = %w[main master develop].freeze

    class << self
      # Ensure we are not on a protected branch before writing.
      # Returns :ok, :created, :already_safe, or :not_git.
      def ensure_safe_branch(request_id: nil)
        return :not_git unless git_repo?

        current = current_branch
        return :already_safe unless PROTECTED.include?(current)

        branch = branch_name(request_id)
        create_and_checkout(branch)
        Logging.dmesg_log("refactor_branch", message: "created branch=#{branch} from=#{current}")
        :created
      rescue StandardError => e
        Logging.warn("RefactorBranch.ensure_safe_branch failed: #{e.message}", subsystem: "refactor_branch")
        :not_git
      end

      def current_branch
        out, _, status = Open3.capture3("git", "rev-parse", "--abbrev-ref", "HEAD")
        status.success? ? out.strip : "unknown"
      end

      private

      def git_repo?
        _, _, status = Open3.capture3("git", "rev-parse", "--git-dir")
        status.success?
      end

      def branch_name(request_id)
        slug = request_id.to_s.gsub(/[^a-z0-9]/, "")[0, 12]
        slug = Time.now.strftime("%Y%m%d%H%M%S") if slug.empty?
        "master/refactor/#{slug}"
      end

      def create_and_checkout(branch)
        _, stderr, status = Open3.capture3("git", "checkout", "-b", branch)
        raise "git checkout -b #{branch} failed: #{stderr.strip}" unless status.success?
      end
    end
  end
end
