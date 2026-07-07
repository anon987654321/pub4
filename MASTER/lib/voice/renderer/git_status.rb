# frozen_string_literal: true

require "open3"

module Master
  module Voice
    class Renderer
      module GitStatus
        private

        def git_root = @config["root"] || Dir.pwd

        def git_rev
          out, _, st = Master::Reach::Exec.capture3("git", "-C", git_root, "rev-parse", "--short", "HEAD")
          st.success? ? out.strip : nil
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "renderer.git_rev")
          nil
        end

        def git_branch
          out, _, st = Master::Reach::Exec.capture3("git", "-C", git_root, "rev-parse", "--abbrev-ref", "HEAD")
          st.success? ? out.strip : nil
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "renderer.git_branch")
          nil
        end

        def git_dirty?
          out, _, st = Master::Reach::Exec.capture3("git", "-C", git_root, "status", "--porcelain")
          st.success? && !out.strip.empty?
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "renderer.git_dirty?")
          false
        end

        def git_ahead_behind
          out, _, st = Master::Reach::Exec.capture3(
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
