# frozen_string_literal: true

require_relative "test_helper"

class TestAxioms < Minitest::Test
  def setup
    @rules = Master::Ground::Rules.new
  end

  def test_kernel_not_empty
    refute @rules.kernel.empty?, "kernel axioms must be present"
  end

  def test_kernel_has_preserve_first
    assert @rules.kernel.key?("PRESERVE_FIRST")
  end

  def test_philosophy_sorted_by_priority
    items = @rules.philosophy
    refute items.empty?
    priorities = items.map { |a| a["priority"].to_i }
    assert_equal priorities.sort, priorities
  end

  def test_kernel_block_formatted
    block = @rules.kernel_block
    assert block.include?("## Kernel Rules")
    assert block.include?("PRESERVE_FIRST")
  end

  def test_philosophy_block_limit
    block = @rules.philosophy_block(limit: 3)
    assert block.include?("(top 3)")
  end

  def test_lookup_kernel
    val = @rules.lookup("PRESERVE_FIRST")
    refute_nil val
    assert val.length > 5
  end
  # voice.yml carried a shadow copy of soul absolute.anti_simulation that the
  # accessor read only if soul lost the key — and it had drifted a word. The
  # shadow is deleted (2026-08-21); soul is the one source, and this holds it.
  def test_constitution_carries_anti_simulation_from_soul
    anti = @rules.constitution["anti_simulation"]
    refute_nil anti, "soul absolute.anti_simulation must reach the constitution accessor"
    assert_equal %w[will would could might], anti["forbidden"]
    assert anti.dig("require_evidence", "completion"), "evidence contract must survive"
  end

end
