# frozen_string_literal: true

require_relative "test_helper"
require "yaml"
require_relative "../gates/support/token_reads"

# A threshold a gate cannot find reads as zero, and a zero threshold is a check
# that returns early. TokenReads is what turns that silence into a failure, so
# each case here is one read and the verdict it has to produce.
class TestTokenReads < Minitest::Test
  TR = Deploy::TokenReads

  def setup
    TR.reset!
    @map = TR.wrap("typography" => { "hierarchy" => { "max_font_weights" => 3 } }, "flag" => false)
  end

  def teardown = TR.reset!

  def test_a_read_that_resolves_passes_and_returns_the_value
    assert_equal 3, @map.dig("typography", "hierarchy", "max_font_weights")
    assert_equal false, @map.dig("flag")
    assert_empty TR.missed
    assert_equal :passed, TR.result.outcome
  end

  def test_an_undeclared_miss_fails_and_names_the_key
    assert_nil @map.dig("typography", "letter_spacing", "all_caps_min_em")
    result = TR.result

    assert_equal :failed, result.outcome
    assert_match(/typography\.letter_spacing\.all_caps_min_em/, result.failures.join)
  end

  def test_a_declared_miss_warns_with_its_reason_and_does_not_fail
    key = TR::UNSET.keys.first
    assert_nil @map.dig(*key.split("."))
    result = TR.result

    assert_equal :passed, result.outcome
    assert_includes result.warnings.join, TR::UNSET.fetch(key)
  end

  def test_a_declaration_the_file_has_outgrown_fails_as_stale
    key = TR::UNSET.keys.first
    set = key.split(".").reverse.reduce(1.4) { |value, part| { part => value } }
    TR.wrap(set).dig(*key.split("."))

    assert_equal [key], TR.stale
    assert_equal :failed, TR.result.outcome
  end

  def test_a_ladder_that_read_nothing_is_inconclusive_not_a_pass
    assert_equal :inconclusive, TR.result.outcome
  end

  # The shipped file against the shipped declaration: nothing UNSET names may
  # resolve, or the list has become a second copy of a value.
  def test_no_declared_unset_key_is_set_in_the_shipped_tokens
    tokens = YAML.safe_load_file(File.expand_path("../data/tokens.yml", __dir__), aliases: true).fetch("tokens")

    TR::UNSET.each_key { |key| assert_nil tokens.dig(*key.split(".")), "#{key} is set; delete it from UNSET" }
  end
end
