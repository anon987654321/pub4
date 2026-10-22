# frozen_string_literal: true

require_relative "test_helper"
require "cli/pipeline/pass"

# /fix delivers when its proof holds, and main is rarely green: the proof is
# judged against the same proof run before the repair. These stub the check
# runner and the suites; the real ladder takes minutes and is not the subject.
class TestProofBaseline < Minitest::Test
  Proof = Master::CLI::Pipeline::Proof
  Reading = Proof::Reading

  RAILS_RED = [
    "checks0 at rails: running production",
    "checks0 at rails: 10 pass, 3 fail, 0 skip, 7 inconclusive, 0 error in 102.0s, autofix off; " \
    "failed=generated_asset,release,layout_suite; inconclusive=deploy_drift,flow_journey",
  ].freeze

  def setup
    Proof.forget_all
    @saved = ENV.delete(Proof::PROOF_ENV)
    @delivered = []
  end

  def teardown
    Proof.forget_all
    ENV[Proof::PROOF_ENV] = @saved
  end

  def test_studio_tree_has_a_full_tree_proof_runner
    target = File.join(Operator::CheckChain::ROOT, "STUDIO")
    name, runner = Master::CLI::Pipeline::Pass.allocate.proof_runner(target)

    assert_equal "STUDIO", name
    assert_respond_to runner, :call
  end

  def test_the_runner_verdict_names_each_failed_check
    reading = Reading.parse(false, RAILS_RED)

    assert reading.measured?
    assert_equal %w[generated_asset layout_suite release].to_set, reading.failing
    assert_equal [10, 20], [reading.passed, reading.total]
  end

  # A check the runner could not measure is neither passed nor failed, and is named as such.
  def test_the_runner_verdict_names_each_unmeasured_check
    assert_equal %w[deploy_drift flow_journey].to_set, Reading.parse(false, RAILS_RED).unmeasured
  end

  def test_a_baseline_red_pass_with_no_new_failure_delivers
    pass = pass_with(RAILS_RED)
    baseline = pass.send(:proof_baseline, Master::RAILS_ROOT)
    _title, body = pass.send(:proof_section, Master::RAILS_ROOT, baseline)

    assert_empty pass.instance_variable_get(:@failed_stages)
    assert_equal "proof: 10 of 20; 3 failing already at baseline (generated_asset, layout_suite, release); " \
                 "no new failures", body.lines.first.chomp
    assert_equal [body.lines.first.chomp], @delivered, "a proof that held delivered nothing"
  end

  def test_a_new_failing_check_refuses
    pass = pass_with(RAILS_RED)
    baseline = pass.send(:proof_baseline, Master::RAILS_ROOT)
    worse = [RAILS_RED.last.sub("release,layout_suite;", "release,layout_suite,schema_migration;")
                           .sub("10 pass, 3 fail", "9 pass, 4 fail")]
    pass.define_singleton_method(:proof_runner) { |_abs| ["rails checks", -> { [false, worse] }] }
    _title, body = pass.send(:proof_section, Master::RAILS_ROOT, baseline)

    assert_equal ["proof"], pass.instance_variable_get(:@failed_stages)
    assert_match(/new failures: schema_migration/, body) # source-assertion: ok — the verdict line the pass printed
    assert_empty @delivered
  end

  def test_a_new_failing_test_refuses_though_its_suite_was_already_red
    before = suite_run(false, "TestA#test_old")
    after = suite_run(false, "TestA#test_old", "TestB#test_new")
    held, line = Proof.judge(Reading.parse(false, after), Reading.parse(false, before))

    refute held
    assert_match(/new failures: TestB#test_new/, line) # source-assertion: ok — the verdict line judge returned
  end

  def test_a_worse_ratchet_row_refuses
    before = suite_run(false, "TestA#test_old") + ["  [DENSITY] 2"]
    after = suite_run(false, "TestA#test_old") + ["  [DENSITY] 3"]
    held, line = Proof.judge(Reading.parse(false, after), Reading.parse(false, before))

    refute held
    assert_match(/worse: selftest DENSITY 2 to 3/, line) # source-assertion: ok — the verdict line judge returned
  end

  def test_a_suite_that_crashed_after_the_repair_refuses
    before = suite_run(false, "TestA#test_old")
    crashed = ["proof suite MASTER: FAIL", "cannot load such file -- missing"]
    held, line = Proof.judge(Reading.parse(false, crashed), Reading.parse(false, before))

    refute held
    assert_match(/crashed/, line) # source-assertion: ok — the verdict line judge returned
  end

  def test_an_unmeasurable_baseline_falls_back_to_green
    crashed = Reading.parse(false, ["proof suite MASTER: FAIL", "LoadError"])
    refute crashed.measured?

    red, = Proof.judge(Reading.parse(false, suite_run(false, "TestA#test_old")), crashed)
    green, line = Proof.judge(Reading.parse(true, ["proof suite MASTER: ok", "5 runs, 9 assertions, 0 failures"]),
                              crashed)
    refute red, "a red proof held against a baseline nobody could read"
    assert green
    assert_match(/no baseline/, line) # source-assertion: ok — the verdict line judge returned
  end

  def test_a_baseline_is_kept_until_origin_main_moves
    pass = pass_with(RAILS_RED)
    runs = 0
    pass.define_singleton_method(:proof_runner) { |_abs| ["rails checks", -> { runs += 1; [false, RAILS_RED] }] }
    2.times { pass.send(:proof_baseline, Master::RAILS_ROOT) }
    assert_equal 1, runs, "the baseline ran twice on an unmoved origin/main"

    pass.define_singleton_method(:origin_main) { "b" * 40 }
    pass.send(:proof_baseline, Master::RAILS_ROOT)
    assert_equal 2, runs, "a baseline outlived a move of origin/main"
  end

  def test_a_baseline_outlives_the_passes_own_commits
    Dir.mktmpdir("proof_baseline") do |repo|
      git = ->(*args) { system("git", "-C", repo, *args, out: File::NULL, err: File::NULL) || flunk("git #{args.first}") }
      git.call("init", "-q")
      commit = lambda do |subject|
        git.call("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", subject)
        `git -C #{repo} rev-parse HEAD`.strip
      end
      first = commit.call("start")
      Proof.remember("rails checks", sha: first, reading: :kept)
      own = commit.call("#{Proof::OWN_SUBJECT} pass 1")
      assert_equal :kept, Proof.recall("rails checks", sha: own, repo:)

      other = commit.call("feat(rails): another session")
      assert_nil Proof.recall("rails checks", sha: other, repo:)
    end
  end

  def test_the_delivery_commit_carries_the_verdict
    pass = Master::CLI::Pipeline::Pass.allocate
    message = pass.send(:delivery_message, Master::RAILS_ROOT, verdict: "proof: 10 of 20; no new failures",
                                                              paths: ["RAILS/a.rb"])

    assert_equal "#{Proof::OWN_SUBJECT} deliver RAILS, proof held", message.lines.first.chomp
    assert_includes message.lines.map(&:chomp), "proof: 10 of 20; no new failures"
  end

  # A baseline suite proof runs minutes with its output captured: it speaks on
  # the check heartbeat cadence like the rails checks do.
  def test_a_suite_proof_runs_under_the_check_heartbeat
    chain = Object.new
    chain.define_singleton_method(:suite_jobs) { |_trees| [["suite MASTER", ["true"], "/", {}, "MASTER", false]] }
    chain.define_singleton_method(:capture) { |*, **| [true, ["fine"]] }
    labels = []
    around = ->(label, **, &block) { labels << label; block.call({}) }

    ok, framed = Operator::CheckHeartbeat.stub(:around, around) do
      Master::CLI::Pipeline::Pass.allocate.send(:suite_proof, chain, "MASTER")
    end

    assert ok
    assert_equal ["MASTER suites"], labels
    assert_includes framed, "proof suite suite MASTER: ok"
  end

  def pass_with(out)
    delivered = @delivered
    pass = Master::CLI::Pipeline::Pass.allocate
    pass.instance_variable_set(:@failed_stages, [])
    pass.define_singleton_method(:proof_runner) { |_abs| ["rails checks", -> { [false, out] }] }
    pass.define_singleton_method(:origin_main) { "a" * 40 }
    pass.define_singleton_method(:deliver_leftovers) { |_abs, verdict| delivered << verdict; "delivery: stubbed" }
    pass
  end

  def suite_run(ok, *failing)
    heads = failing.flat_map { |name| ["  1) Failure:", "#{name} [test/x.rb:1]:", "Expected true"] }
    ["proof suite MASTER: #{ok ? "ok" : "FAIL"}", *heads,
     "9 runs, 9 assertions, #{failing.size} failures, 0 errors, 0 skips",
     "check0 at master0: 1 failure(s), test"]
  end
end
