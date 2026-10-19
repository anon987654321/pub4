# frozen_string_literal: true

require_relative "test_helper"

# The fleet check starts the RAILS layout browser sweep, which takes minutes and says nothing about one
# Ruby file. It belongs to a whole-tree run, not to any path that happens to sit inside a tree.
class TestReachabilityScope < Minitest::Test
  # A Reachability whose fleet check records that it ran instead of starting a browser.
  def reachability(sweeps)
    Master::Fix::Reachability.new(root: Master::ROOT).tap do |reach|
      reach.define_singleton_method(:verify_fleet!) { sweeps << :fleet }
    end
  end

  def collected(target) = Master::Fix::FixLoop::FileCollector.new(root: Master::ROOT).collect(target)

  def test_a_file_inside_a_tree_does_not_start_the_fleet_sweep
    sweeps = []
    file = File.join(Master::ROOT, "lib", "cli", "fold_risk.rb")

    reachability(sweeps).verify!(file, files: [file])

    assert_empty sweeps
  end

  def test_a_directory_inside_a_tree_does_not_start_the_fleet_sweep
    sweeps = []
    dir = File.join(Master::ROOT, "lib", "cli", "pipeline")

    reachability(sweeps).verify!(dir, files: collected(dir))

    assert_empty sweeps
  end

  def test_the_whole_tree_still_starts_it
    sweeps = []

    reachability(sweeps).verify!(Master::ROOT, files: collected(Master::ROOT))

    assert_equal [:fleet], sweeps
  end
end
