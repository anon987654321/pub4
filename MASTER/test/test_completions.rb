# frozen_string_literal: true

require_relative "test_helper"

# The zsh completions are a copy of two lists that live in code, so each is
# held to its source: _master to the verbs CommandRegistry.build returns, and
# _operator to the subcommands bin/operator dispatches.
class TestCompletions < Minitest::Test
  COMPLETIONS = File.join(Master::ROOT, "completions")

  def completed(file)
    File.read(File.join(COMPLETIONS, file)).scan(/^\s+'([a-z?-]+):/).flatten.sort
  end

  def test_master_completes_the_built_slash_surface
    built = Master::CLI::CommandRegistry.build(
      infra: { session: Master::Trace::Session.new, config: {}, root: Master::ROOT, bus: nil },
      ai: { agent: nil },
      root: Master::ROOT,
    )
    exits = Master::CLI::CommandRegistry.slash_commands.map { |c| c.delete_prefix("/") } - built.keys

    assert_equal (built.keys + exits).sort, completed("_master")
  end

  def test_master_completion_serves_both_entrypoints
    assert_match(/\A#compdef master$/, File.read(File.join(COMPLETIONS, "_master")))
  end

  def test_operator_check_is_the_ladder_command
    source = File.read(File.join(Master::ROOT, "bin", "operator"))
    assert_match(/^when "check"$/, source)
    assert_includes source, "bin/operator check [--scan-only]"
    assert_includes File.read(File.join(COMPLETIONS, "_operator")), "'check:"
  end

  def test_operator_completes_every_subcommand
    source = File.read(File.join(Master::ROOT, "bin", "operator"))
    subcommands = source.scan(/^when (.+)$/).flatten.flat_map { |clause| clause.scan(/"([a-z?-]+)"/).flatten }.sort

    assert_operator subcommands.size, :>=, 10, "a short list means the scan of bin/operator broke"
    assert_equal subcommands, completed("_operator")
  end

  def test_master_help_completion_describes_the_master_registry
    line = File.readlines(File.join(COMPLETIONS, "_master")).find { |entry| entry.include?("'help:") }

    assert_includes line, "MASTER commands"
    assert_includes line, "syntax"
    refute_includes line, "OpenBSD Operator"
  end

  def test_operator_completions_describe_live_behavior
    source = File.read(File.join(COMPLETIONS, "_operator"))

    assert_includes source, "'land:commit path-scoped, re-check, push current branch'"
    assert_includes source, "'worktree:create, list or remove managed isolated worktrees'"
    assert_includes source, "report merge/delete candidates"
    refute_includes source, "worktree:refused"
    refute_includes source, "push main'"
  end
end
