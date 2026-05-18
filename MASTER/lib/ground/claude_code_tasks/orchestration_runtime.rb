# frozen_string_literal: true

module Master
  module Ground
  module ClaudeCodeTasks
  module OrchestrationRuntime
    GOAL = "Turn attention context, prompt archaeology patterns, and multi-LLM orchestration into active Ruby runtime policy."

    REQUIRED_NEW_RUBY = %w[
      lib/ground/intent_router.rb
      lib/ground/attention_context.rb
      lib/ground/unfinished_ledger.rb
      lib/ground/orchestration_policy.rb
    ].freeze

    REQUIRED_INTEGRATIONS = {
      "lib/now/cli.rb" => [
        "emit attention context on long-running slash commands",
        "show unfinished ledger suggestions in proposer/status path when relevant"
      ],
      "lib/ground/provider_registry.rb" => [
        "add cheap/fast/strong/local/browser_local task tiers",
        "select provider by task risk and capability, not fixed default only"
      ],
      "lib/judge/council/deliberation.rb" => [
        "accept orchestration policy brief and task-risk metadata",
        "use council only when risk tier requires it"
      ],
      "lib/ground/context_provider.rb" => [
        "use attention target to select repo_map, memory_search, or brain_overlay context"
      ]
    }.freeze

    INTENTS = %i[
      codify_policy
      refactor_to_ruby
      wire_existing_module
      create_facade
      delete_redundant_config
      verify_patch_landed
      run_sound_review
      run_ui_review
      apply_user_style_rules
      create_claude_code_task_pr
    ].freeze

    RISK_TIERS = {
      low: %i[classification summarization cluster_labeling ui_copy],
      medium: %i[docs config preview_browser_modules],
      high: %i[file_mutation autonomous_actions auth security production_runtime],
      critical: %i[destructive_commands secret_handling permission_changes public_deployment]
    }.freeze

    STANDING_SEMANTICS = {
      "go ahead" => :continue_prior_plan,
      "land it" => :write_repo_changes,
      "codify" => :make_executable_ruby_policy,
      "ruby where possible" => :prefer_ruby_for_behavior,
      "actual work" => :avoid_report_only_output,
      "wire" => :connect_facade_to_callers,
      "verify" => :read_back_files_and_symbols
    }.freeze

    CONSTRAINTS = [
      "No markdown deliverables unless user explicitly asks.",
      "Runtime policy belongs in Ruby, not YAML, when it changes behavior.",
      "Prompt archaeology must extract abstract patterns only; do not copy vendor prompt text.",
      "Do not ask redundant clarifying questions after user says go ahead.",
      "Every landed change must have file, symbol, caller, and verification evidence.",
      "User standing orders outrank older inferred defaults."
    ].freeze

    VERIFY = [
      "ruby -c MASTER/lib/ground/intent_router.rb",
      "ruby -c MASTER/lib/ground/attention_context.rb",
      "ruby -c MASTER/lib/ground/unfinished_ledger.rb",
      "ruby -c MASTER/lib/ground/orchestration_policy.rb",
      "grep -R \"codify_policy\|refactor_to_ruby\|wire_existing_module\" MASTER/lib/ground/intent_router.rb",
      "grep -R \"browser_local\|strong\|cheap\" MASTER/lib/ground/provider_registry.rb",
      "grep -R \"unfinished\|ledger\" MASTER/lib MASTER/web || true"
    ].freeze
  end
  end
  end
end
