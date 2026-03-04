# frozen_string_literal: true

require_relative "test_helper"

class TestWebSearchPrioritization < Minitest::Test
  def test_prioritize_research_domains_adds_default_sources
    scoped = MASTER::ToolDispatch.prioritize_research_domains("ruby ast parser")
    assert_equal "ruby ast parser (site:github.com OR site:ar5iv.org)", scoped
  end

  def test_prioritize_research_domains_preserves_explicit_github_scope
    scoped = MASTER::ToolDispatch.prioritize_research_domains("site:github.com ruby lsp")
    assert_equal "site:github.com ruby lsp", scoped
  end

  def test_permissions_allow_zsh_git_and_gh_in_refactor_tier
    assert MASTER::Security::Permissions.permitted?(:shell_command, tier: :refactor, command: "zsh -lc 'print ok'")
    assert MASTER::Security::Permissions.permitted?(:shell_command, tier: :refactor, command: "git commit -m test")
    assert MASTER::Security::Permissions.permitted?(:shell_command, tier: :refactor, command: "gh pr list")
  end
end
