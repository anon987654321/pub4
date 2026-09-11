# frozen_string_literal: true

require_relative "test_helper"

# Every command the registry builds must be able to run.
#
# Command#call ends in `@receiver.public_send(@method_name, ...)`, so a symbol
# that names no public method fails when a person types the verb rather than
# when the registry is built. Nothing checked that, and the gap is not
# theoretical: on 2026-09-11 five live dispatchers — dispatch_commit,
# dispatch_pair, dispatch_doctor, dispatch_rules and dispatch_tree — were nearly
# deleted with the dead slash tables they share a file with, because a grep for
# the table's name says nothing about a method dispatched as `command(:dispatch_doctor, root)`.
# The suite was green throughout; only booting the runtime would have caught it.
#
# Static rather than built: building the registry wants the whole dependency
# graph, and the question here is narrower than a boot.
class TestCommandRegistryDispatch < Minitest::Test
  REGISTRY = File.expand_path("../lib/cli/command_registry.rb", __dir__)

  def dispatched_symbols
    File.read(REGISTRY).scan(/command\(:(\w+)/).flatten.uniq
  end

  def test_every_dispatched_symbol_names_a_public_method
    unresolvable = dispatched_symbols.reject do |name|
      Master::CLI::CommandRegistry.respond_to?(name)
    end

    assert_empty unresolvable,
                 "the registry dispatches these by symbol and nothing answers them: #{unresolvable.join(', ')}"
  end

  # A guard that finds nothing because it is looking in the wrong place is the
  # failure this file exists to prevent, so the population is asserted too.
  def test_the_guard_reads_a_real_population
    assert_operator dispatched_symbols.size, :>=, 10,
                    "build dispatches at least the ten verbs help advertises; a smaller number means the scan broke"
  end

  # A table under command_registry/ is merged by a builder or it is unreachable,
  # and seven of the ten are unreachable. `build` merges control_commands and
  # nothing else; `build_fast` returns status and help; `slash_commands` is built
  # from HELP_TOPICS. The subtraction list in TODO.md named three of these —
  # memory, system and media, unreachable since 7c23a5ee5 cut the slash surface
  # to eight verbs — and the measurement says four more.
  #
  # None is deletable as a FILE. Each holds live dispatchers beside its dead
  # table: system_commands.rb alone carries dispatch_commit, dispatch_pair,
  # dispatch_doctor and dispatch_rules, all of which `build` reaches by symbol.
  #
  # This pins the set so a new table cannot join it quietly, and so closing one
  # has to come here and say so.
  ROOT = File.expand_path("..", __dir__)
  SEARCHED = %w[lib web bin tools].freeze

  def test_the_unmerged_command_tables_are_the_seven_we_know_about
    tables = Dir.glob(File.join(ROOT, "lib/cli/command_registry/*_commands*.rb"))
                .map { |path| File.basename(path, ".rb") }

    unmerged = tables.reject { |table| production_call_site?(table) }

    assert_equal %w[agent_commands core_commands media_commands memory_commands
                    reach_commands system_commands work_commands_extra],
                 unmerged.sort,
                 "the unmerged set moved — wire the new one, or record here why it is unreachable"
  end

  # A require names a file and a def names itself; neither is a call.
  def production_call_site?(table)
    dirs = SEARCHED.map { |dir| File.join(ROOT, dir) }.select { |dir| File.exist?(dir) }
    lines = IO.popen(["grep", "-rn", "--", table, *dirs], err: File::NULL, &:read).split("\n")

    lines.any? do |line|
      next false if line.include?("require_relative") || line.include?("def #{table}")

      true
    end
  end
end
