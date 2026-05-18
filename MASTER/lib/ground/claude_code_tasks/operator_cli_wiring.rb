# frozen_string_literal: true

module Master
  module Ground
  module ClaudeCodeTasks
  module OperatorCliWiring
    GOAL = "Wire the newly landed operator modules into MASTER's active CLI/runtime paths."

    REQUIRED_FILES = %w[
      lib/now/cli.rb
      lib/ground/repo_map.rb
      lib/ground/unified_diff_editor.rb
      lib/ground/agent_lifecycle.rb
      lib/ground/sandbox_policy.rb
      lib/ground/checkpoint.rb
      lib/ground/tool_approval_policy.rb
      lib/ground/provider_registry.rb
      lib/ground/context_provider.rb
      lib/ground/patch_verifier.rb
      lib/ground/done_checker.rb
    ].freeze

    REQUIRED_CHANGES = [
      "Add /sound-critique to CLI SLASH_COMMANDS and handle_repl_line.",
      "Add run_sound_critique mirroring run_ui_critique but using Master::Judge::Council::SoundCritique.",
      "Add /rebuild to CLI SLASH_COMMANDS and handle_repl_line.",
      "Implement run_rebuild as syntax/load smoke check + session save + Kernel.exec restart.",
      "Add /context command that prints Master::Ground::ContextProvider brief for the last user input.",
      "Add /checkpoint command that snapshots changed lib/web files through Master::Ground::Checkpoint.",
      "Add /verify command that calls Master::Ground::DoneChecker for known recently-landed operator symbols.",
      "Do not create markdown. Do not replace user-curated data. Keep changes surgical."
    ].freeze

    EXPECTED_SYMBOLS = %w[
      Master::Now::CLI#run_sound_critique
      Master::Now::CLI#run_rebuild
      Master::Now::CLI#run_context
      Master::Now::CLI#run_checkpoint
      Master::Now::CLI#run_verify
    ].freeze

    VERIFY = [
      "ruby -c MASTER/lib/now/cli.rb",
      "grep -R \"/sound-critique\" MASTER/lib/now/cli.rb",
      "grep -R \"Master::Judge::Council::SoundCritique\" MASTER/lib/now/cli.rb",
      "grep -R \"Master::Ground::ContextProvider\" MASTER/lib/now/cli.rb",
      "grep -R \"Master::Ground::DoneChecker\" MASTER/lib/now/cli.rb"
    ].freeze

    NEXT_SUGGESTIONS = [
      "Route CLI commands through ToolApprovalPolicy before any risky command execution.",
      "Emit attention/context events when /context, /verify, /sound-critique, or /ui-critique run.",
      "Use Checkpoint before code-writing agent modes, not only manual /checkpoint."
    ].freeze
  end
  end
  end
end
