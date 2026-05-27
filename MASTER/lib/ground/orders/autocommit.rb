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
        commit_message = "auto: standing-order commit (#{out.lines.size} file(s))"
        _, st = Open3.capture2e("git", "-C", repo, "commit", "-m", commit_message)
        return Result.err("commit failed") unless st.success?
        push_out, push_st = Open3.capture2e("git", "-C", repo, "push")
        if push_st.success?
          bus&.publish("autocommit:pushed", files: out.lines.size)
          Result.ok(committed: true, pushed: true)
        else
          bus&.publish("autocommit:push_failed", error: push_out.strip[0, 200])
          Result.ok(committed: true, pushed: false, push_error: push_out.strip)
        end
      rescue StandardError => e
        Result.err(e.message)
      end
    end
  end
  end
end
