# frozen_string_literal: true

require_relative "test_helper"

class TestAxioms < Minitest::Test
  def setup
    @axioms = Master::Axioms.new
  end

  def test_kernel_not_empty
    refute @axioms.kernel.empty?, "kernel axioms must be present"
  end

  def test_kernel_has_preserve_first
    assert @axioms.kernel.key?("PRESERVE_FIRST")
  end

  def test_philosophy_sorted_by_priority
    items = @axioms.philosophy
    refute items.empty?
    priorities = items.map { |a| a["priority"].to_i }
    assert_equal priorities.sort, priorities
  end

  def test_kernel_block_formatted
    block = @axioms.kernel_block
    assert block.include?("## Kernel Axioms")
    assert block.include?("PRESERVE_FIRST")
  end

  def test_philosophy_block_limit
    block = @axioms.philosophy_block(limit: 3)
    assert block.include?("## Core Philosophy (top 3)")
  end

  def test_lookup_kernel
    val = @axioms.lookup("PRESERVE_FIRST")
    refute_nil val
    assert val.length > 5
  end
end
