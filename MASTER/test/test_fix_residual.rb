# frozen_string_literal: true

require "tmpdir"
require_relative "test_helper"

# A /fix run leaves its target a residual, and the next run starts from it.
class TestFixResidual < Minitest::Test
  Residual = Master::CLI::Pipeline::Residual
  Focus = Master::Fix::GateFocus

  def setup
    @saved = ENV["MASTER_FIX_RESIDUAL"]
    @dir = Dir.mktmpdir
    ENV["MASTER_FIX_RESIDUAL"] = File.join(@dir, "residual.json")
    Focus.reset!
  end

  def teardown
    ENV["MASTER_FIX_RESIDUAL"] = @saved
    FileUtils.remove_entry(@dir)
    Focus.reset!
  end

  def test_a_hard_gate_left_red_points_the_next_run_at_the_blocker_lane
    proof = { verdict: "proof: 9 of 20", hard: %w[release], soft: %w[layout_suite] }

    entry = Residual.write(target: "RAILS", scorecard: "fix partial · …", proof:, named: %w[app/a.rb])

    assert_equal "MASTER/bin/fix-here RAILS --blockers", entry["next"]
    assert_equal %w[release], Residual.read("RAILS")["hard_red"]
  end

  def test_the_next_run_starts_with_the_files_the_last_one_named
    Residual.write(target: "MASTER", scorecard: "fix partial · …", proof: nil, named: %w[lib/fix/c.rb])

    Master::CLI::CommandRegistry.resume_from_residual("MASTER")

    assert Focus.covers?("/r/MASTER/lib/fix/c.rb")
  end
end
