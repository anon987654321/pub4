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

        # One bounded probe supplies branch, dirtiness and upstream delta.
        # A shell prompt is on the hot path: it must never wait indefinitely or
        # launch three separate git processes for one redraw.
        PROMPT_GIT_TIMEOUT_S = 0.15

        def git_prompt_state
          out, _, status = Master::Io::Exec.capture3(
            "git", "-C", git_root, "status", "--porcelain=v2", "--branch",
            timeout: PROMPT_GIT_TIMEOUT_S
          )
          return unless status.success?

          branch = nil
          ahead = 0
          behind = 0
          dirty = false
          out.each_line do |line|
            case line
            when /^# branch.head (.+)$/
              branch = Regexp.last_match(1)
            when /^# branch.ab \+(\d+) -(\d+)$/
              ahead = Regexp.last_match(1).to_i
              behind = Regexp.last_match(2).to_i
            when /^#/
            else
              dirty = true unless line.strip.empty?
            end
          end
          branch = nil if branch == "(detached)"
          { branch: (branch.to_s.empty? ? "detached" : branch), ahead:, behind:, dirty: }
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "renderer.git_prompt_state")
          nil
        end
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
