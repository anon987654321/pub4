# frozen_string_literal: true

module MASTER
  # GHHelper - GitHub CLI integration for PR creation and git operations
  module GHHelper
    class << self
      def create_pr(title:, body:, draft: true)
        cmd = ["gh", "pr", "create"]
        cmd << "--title" << title
        cmd << "--body" << body
        cmd << "--draft" if draft
        
        system(*cmd)
      end

      def create_pr_with_context(title, description, files_changed)
        body = <<~BODY
          #{description}

          ## Files Changed
          #{files_changed.map { |f| "- `#{f}`" }.join("\n")}

          ## Automated Tests
          - [ ] Syntax validation passed
          - [ ] No new violations introduced
          - [ ] All existing tests pass

          ---
          *Created by MASTER2 CLI*
        BODY

        create_pr(title: title, body: body)
      end

      def pr_status
        `gh pr status --json number,title,state`
      end

      def current_branch
        `git branch --show-current`.strip
      end

      def has_uncommitted_changes?
        !`git status --porcelain`.strip.empty?
      end

      def commit_and_push(message, files = nil)
        if files
          system("git", "add", *files)
        else
          system("git", "add", "-A")
        end

        system("git", "commit", "-m", message)
        system("git", "push")
      end

      def gh_available?
        system("which gh > /dev/null 2>&1")
      end
    end
  end
end
