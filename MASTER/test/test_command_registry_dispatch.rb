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

  # A table is a method returning verb => Command, and it is reachable only if
  # `build` merges it. Seven were not — agent, core, domain, media, memory,
  # reach and system — and the suite passed for weeks, because their tests
  # called the tables directly. They and their dispatchers are gone; the live
  # dispatchers that shared their files stayed. This fails the moment a table
  # is defined that command_registry.rb does not call.
  REGISTRY_DIR = File.expand_path("../lib/cli/command_registry", __dir__)

  def test_every_table_is_merged_by_the_registry
    sources = [REGISTRY, *Dir[File.join(REGISTRY_DIR, "**", "*.rb")]]
    # A def whose body builds Commands; slash_commands returns names, not a table.
    tables = sources.flat_map do |path|
      File.read(path).split(/^(?=\s*def )/).filter_map do |body|
        body[/\A\s*def (\w+_commands)\b/, 1] if body.include?("command(:")
      end
    end.uniq
    registry = File.read(REGISTRY).lines.reject { |line| line =~ /^\s*def / }.join

    assert_includes tables, "control_commands", "the scan must find the one table build merges"
    unmerged = tables.reject { |name| registry.match?(/\b#{name}\(/) }
    assert_empty unmerged, "defined and merged by nothing, so no person can type them: #{unmerged.join(", ")}"
  end
end
