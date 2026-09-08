# frozen_string_literal: true

require "open3"

module Master
  module Voice
    class Renderer
      module GitStatus
        private

        def git_root = @config["root"] || Dir.pwd

        # A git question the prompt asks in passing: it answers nil when the
        # command fails or the tree is not a repository, and never raises into
        # the render.
        def git_say(context, *argv)
          out, _, status = Master::Io::Exec.capture3("git", "-C", git_root, *argv)
          status.success? ? out.strip : nil
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "renderer.#{context}")
          nil
        end

        def git_rev = git_say("git_rev", "rev-parse", "--short", "HEAD")

        def git_branch = git_say("git_branch", "rev-parse", "--abbrev-ref", "HEAD")

        def git_dirty? = !git_say("git_dirty?", "status", "--porcelain").to_s.empty?

        def git_ahead_behind
          out, _, st = Master::Io::Exec.capture3(
            "git", "-C", git_root,
            "rev-list", "--left-right", "--count", "HEAD...@{u}"
          )
          return [0, 0] unless st.success?
          parts = out.strip.split
          [parts[0].to_i, parts[1].to_i]
        rescue StandardError => _e
          [0, 0]
        end
      end
    end
  end
end
