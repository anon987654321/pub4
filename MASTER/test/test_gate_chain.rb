# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"
require "tmpdir"
require_relative "../lib/pub4/gate_chain"
require_relative "../lib/review/council/harvest"

# `bin/pub4 gate` is the one command that runs every gate in the repo, and the
# only thing worse than not having it is having one that reports a pass over
# stages it never reached. Each test pins a property the chain otherwise loses
# in silence: a stage pointing at a script that has moved, a mutating stage
# smuggled into scan-only, a verdict read off the wrong line.
class TestGateChain < Minitest::Test
  G = Pub4::GateChain

  def test_every_stage_runs_a_script_that_exists
    missing = %w[bin/gate bin/pub4 bin/check bin/master tools/sprawl_census.rb tools/dup_census.rb]
              .reject { |path| File.file?(File.join(G::MASTER, path)) }
    missing << "RAILS/gates/runner.rb" unless File.file?(File.join(G::ROOT, "RAILS", "gates", "runner.rb"))

    assert_empty missing, "the chain invokes these and they are not on disk"
  end

  # The whole point of scan-only is that it can be run on a shared checkout
  # without touching another session's work.
  def test_scan_only_declares_no_writing_stage
    writers = G.stages(scan_only: true).select(&:mutates).map(&:name)

    assert_empty writers, "scan-only writes in #{writers.join(", ")}"
  end

  def test_full_fix_declares_exactly_the_stages_that_write
    writers = G.stages(scan_only: false).select(&:mutates).map(&:name)

    assert_equal %w[lexical source sprawl council], writers
  end

  # The panel argues for free or it does not argue; either way the tree stays as
  # it was when nobody asked for a fixing run.
  def test_the_council_acts_on_its_picks_only_in_full_fix
    refute G.council_fix?(scan_only: true)
    assert G.council_fix?(scan_only: false)
  end

  def test_cherry_picks_are_read_out_of_the_harvest_format
    body = Master::Review::Council::Harvest.render(
      mode: :general, files: ["lib/x.rb"], feedback: [], ideas: {}, cherry: ["collapse the two registries"],
    )
    Dir.mktmpdir do |root|
      dir = File.join(root, ".master", "critiques")
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, "general_latest.md"), body)

      assert_equal ["collapse the two registries"], G.picks_in(dir)
    end
  end

  # The tier that cannot answer runs last so it never stands between the rest of
  # the ladder and its verdict, and the fixers run first so everything after
  # them measures the fixed tree.
  def test_the_order_is_fix_first_and_the_unreachable_tier_last
    names = G.stages(scan_only: false).map(&:name)

    assert_equal names.uniq, names
    assert_equal "lexical", names.first
    assert_equal "council", names.last
    assert_operator names.index("suites"), :>, names.index("source")
    assert_operator names.index("sprawl"), :>, names.index("ratchets")
  end

  # Exit 3 is `bin/gate --semantic-only` saying it reached nobody. Read as a
  # failure, it blames the tree for a provider's billing.
  def test_exit_three_is_skipped_and_every_other_failure_is_a_failure
    assert_equal "ok", G.classify(true, 0)
    assert_equal "skipped", G.classify(false, 3)
    assert_equal "failed", G.classify(false, 1)
  end

  # design_baseline prints its summary above its detail, which is how
  # tools/sweep.rb once reported a detail row as the verdict.
  def test_the_verdict_is_the_summary_line_not_the_last_line
    body = ["sprawl_census: lone_dirs 53 (ceiling 53)", "  MASTER/foo.rb"]

    assert_equal "sprawl_census: lone_dirs 53 (ceiling 53)", G.verdict(body)
  end

  def test_generated_paths_are_recognised_in_every_tree_that_has_them
    %w[STUDIO/lora/.cache/x.json RAILS/brgen/app/assets/builds/application.css
       RAILS/amber/public/assets/x.js MASTER/Gemfile.lock].each do |path|
      assert_match G::GENERATED, path
    end
    refute_match G::GENERATED, "MASTER/lib/pub4/gate_chain.rb"
  end

  def test_only_selects_a_subset_and_list_reports_it
    out, = capture_io { G.run(scan_only: true, only: %w[sprawl], list: true) }

    assert_includes out, "sprawl"
    refute_includes out, "lexical"
  end
end
