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
    assert_match(/\A#compdef master cli$/, File.read(File.join(COMPLETIONS, "_master")))
  end

  def test_operator_completes_every_subcommand
    source = File.read(File.join(Master::ROOT, "bin", "operator"))
    subcommands = source.scan(/^when "([a-z?-]+)"/).flatten.sort

    assert_operator subcommands.size, :>=, 10, "a short list means the scan of bin/operator broke"
    assert_equal subcommands, completed("_operator")
  end
end
