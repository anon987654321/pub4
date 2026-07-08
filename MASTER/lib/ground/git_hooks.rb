# frozen_string_literal: true

require "fileutils"

module Master
  module Ground
    module GitHooks
      HOOK_BODY = "#!/bin/sh\nroot=\"$(git rev-parse --show-toplevel 2>/dev/null)\"\n" \
                  "exec \"${root}/MASTER/bin/audit\" --profile critical\n".freeze

      module_function

      def ensure_pre_commit!(root: Master::ROOT)
        git_dir = File.join(root, ".git")
        return Result.ok(skipped: :no_git) unless File.directory?(git_dir)

        hook_path = File.join(git_dir, "hooks", "pre-commit")
        return Result.ok(skipped: :exists) if File.exist?(hook_path)

        FileUtils.mkdir_p(File.dirname(hook_path))
        File.write(hook_path, HOOK_BODY)
        File.chmod(0o755, hook_path)
        Result.ok(path: hook_path)
      rescue StandardError => e
        Result.err("pre-commit hook install failed: #{e.message}", category: :infrastructure)
      end
    end
  end
end
