# frozen_string_literal: true

require_relative "test_helper"

# The RSS limit sheds /fix's model work. It was a flat 768 MB, sized for vm23's
# 1 GB, so on a laptop pass 1 alone crossed it and no model fix ever ran. It now
# scales with the machine and keeps the old figures as its floor.
class TestFixResourceBudgetRss < Minitest::Test
  def budget(memory_mb:, config: {})
    Master::Fix::ResourceBudget.new(root: Dir.pwd, config:, memory_mb:)
  end

  def limits(budget) = [budget.send(:rss_limit, "warn"), budget.send(:rss_limit, "crit")]

  def test_a_one_gigabyte_server_keeps_the_original_figures
    assert_equal [512, 768], limits(budget(memory_mb: 1000))
  end

  def test_a_laptop_gets_a_share_of_its_memory
    assert_equal [1638, 3277], limits(budget(memory_mb: 16_384))
  end

  def test_the_floor_holds_on_a_machine_smaller_than_the_server
    assert_equal [512, 768], limits(budget(memory_mb: 256))
  end

  def test_configuration_still_wins
    config = { "load" => { "master_rss_mb" => { "warn" => 300, "crit" => 900 } } }

    assert_equal [300, 900], limits(budget(memory_mb: 16_384, config:))
  end

  def test_pass_one_of_a_fix_run_is_no_longer_critical_on_a_laptop
    critical = budget(memory_mb: 8192).send(:classify_one_check, :ok, :rss_mb, 791, *limits(budget(memory_mb: 8192)))

    assert_equal [:ok, nil], critical
  end
end
