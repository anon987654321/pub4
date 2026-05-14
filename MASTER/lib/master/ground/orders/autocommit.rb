# frozen_string_literal: true

require "open3"

module Master
  module Ground
  module Orders
    class Autocommit < Base
      def call
        repo = File.expand_path(File.join(root, ".."))
        out, _, status = Open3.capture3("git", "-C", repo, "status", "--porcelain")
        return Result.ok(skipped: true) unless status.success? && !out.strip.empty?
        Open3.capture2e("git", "-C", repo, "add", "-A")
        msg = "auto: standing-order commit (#{out.lines.size} file(s))"
        _, st = Open3.capture2e("git", "-C", repo, "commit", "-m", msg)
        st.success? ? Result.ok(committed: true) : Result.err("commit failed")
      rescue StandardError => e
        Result.err(e.message)
      end
    end
  end
  end
end
