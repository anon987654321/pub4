# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "gate_fixture"
require_relative "../../gates/lib/source/phantom_foreign_keys"

# A foreign key pointing at a table name no migration creates.
#
# `add_foreign_key "posts", "listings"` reads as correct and is not: the table
# is `marketplace_listings`, because the vertical is an engine with a table
# prefix. Rails only resolves the real name at migrate time, so the defect ships
# in schema.rb and surfaces as a failed migration on the box.
#
# The gate reads `RAILS/*/db/schema.rb` off a ROOT constant fixed at load time
# and takes no root argument, so these tests rewrite ROOT around the call.
class PhantomForeignKeysGateTest < Minitest::Test
  include GateFixture

  GATE = Deploy::PhantomForeignKeysGate

  def over(*schemas)
    Dir.mktmpdir do |dir|
      schemas.each_with_index do |body, index|
        plant(dir, "RAILS/app#{index}/db/schema.rb", body)
      end
      with_constants(GATE, ROOT: dir) { GATE.run }
    end
  end

  def schema(foreign_keys)
    "ActiveRecord::Schema[8.0].define(version: 2026_01_01_000000) do\n#{foreign_keys}end\n"
  end

  def test_a_key_pointing_at_an_unprefixed_engine_table_fails
    result = over(schema(%(  add_foreign_key "posts", "listings"\n)))

    refute result.ok?, "a phantom foreign key passed"
    assert_equal 1, result.failures.size
    assert_match(/listings/, result.failures.first)
    assert_match(/phantom/, result.failures.first)
  end

  def test_the_same_key_pointing_at_the_prefixed_table_passes
    result = over(schema(%(  add_foreign_key "posts", "marketplace_listings"\n)))

    assert result.ok?, result.failures.join(", ")
    assert_equal 1, result.checks_ran
  end

  # Every schema in the tree, not the first one. A loop that stopped early would
  # pass on a fixture whose only defect is in the second app.
  def test_a_defect_in_the_second_schema_is_found_too
    result = over(schema(""), schema(%(  add_foreign_key "carts", "buyers"\n)))

    refute result.ok?
    assert_equal 2, result.checks_ran
    assert_match(/buyers/, result.failures.first)
  end

  # No schema at all is an unread tree, not a clean one: every app keeps one, so
  # an empty glob means the path moved under the gate.
  def test_an_empty_tree_is_inconclusive_rather_than_clean
    result = Dir.mktmpdir { |dir| with_constants(GATE, ROOT: dir) { GATE.run } }

    assert result.measured_nothing?, "an empty glob reported a pass"
    assert_equal :inconclusive, result.outcome
    assert_match(/nothing was read/, result.unchecked.first)
  end
end
