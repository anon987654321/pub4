# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"
require "open3"
require "rbconfig"
require "tmpdir"
require_relative "../lib/operator/check_chain"
require_relative "../lib/review/council/harvest"

# `bin/operator check` is the one command that runs every check in the repo, and the
# only thing worse than not having it is having one that reports a pass over
# stages it never reached. Each test pins a property the chain otherwise loses
# in silence: a stage pointing at a script that has moved, a mutating stage
# smuggled into scan-only, a verdict read off the wrong line.
class TestCheckChain < Minitest::Test
  G = Operator::CheckChain

  def test_every_stage_runs_a_script_that_exists
    missing = %w[bin/operator bin/check bin/master lib/operator/sprawl_census.rb tools/audit/dup_census.rb lib/operator/check_ladder.rb]
              .reject { |path| File.file?(File.join(G::MASTER, path)) }
    missing << "MASTER/checks/runner.rb" unless File.file?(File.join(G::ROOT, "MASTER", "checks", "runner.rb"))
    missing << "OPENBSD/bin/check-openbsd" unless File.file?(File.join(G::ROOT, "OPENBSD", "bin", "check-openbsd"))

    assert_empty missing, "the chain invokes these and they are not on disk"
  end

  # The whole point of scan-only is that it can be run on a shared checkout
  # without touching another session's work.
  def test_scan_only_declares_no_writing_stage
    writers = G.stages(scan_only: true).select(&:mutates).map(&:name)

    assert_empty writers, "scan-only writes in #{writers.join(", ")}"
  end

  def test_lexical_stage_describes_its_actual_write_mode
    readonly = G.stages(scan_only: true).find { |stage| stage.name == "lexical" }
    writable = G.stages(scan_only: false).find { |stage| stage.name == "lexical" }

    refute readonly.mutates
    assert_includes readonly.purpose, "measuring without writes"
    refute_includes readonly.purpose, "autofixing"
    assert writable.mutates
    assert_includes writable.purpose, "autofixing"
  end

  def test_fix_verification_can_be_limited_to_named_stages
    previous = ENV.delete("MASTER_FIX_CHECK_STAGES")
    everything = G.verification_stages("RAILS").map(&:name)

    assert_includes everything, "source"

    ENV["MASTER_FIX_CHECK_STAGES"] = "lexical, sprawl"

    assert_equal %w[lexical sprawl], G.verification_stages("RAILS").map(&:name)
    refute_includes G.verification_stages("RAILS").map(&:name), "source"
  ensure
    previous ? ENV["MASTER_FIX_CHECK_STAGES"] = previous : ENV.delete("MASTER_FIX_CHECK_STAGES")
  end

  def test_invalid_or_inapplicable_verification_filters_are_rejected
    previous = ENV["MASTER_FIX_CHECK_STAGES"]

    ENV["MASTER_FIX_CHECK_STAGES"] = "lexical,not_a_stage"
    error = assert_raises(G::InvalidVerificationScope) { G.verification_stages("RAILS") }
    assert_includes error.message, "not_a_stage"

    ENV["MASTER_FIX_CHECK_STAGES"] = "council"
    error = assert_raises(G::InvalidVerificationScope) { G.verification_stages("RAILS") }
    assert_match(/council/, error.message)

    ENV["MASTER_FIX_CHECK_STAGES"] = "suites"
    error = assert_raises(G::InvalidVerificationScope) { G.verification_stages("RAILS") }
    assert_match(/do not apply/, error.message)
  ensure
    previous.nil? ? ENV.delete("MASTER_FIX_CHECK_STAGES") : ENV["MASTER_FIX_CHECK_STAGES"] = previous
  end

  def test_the_baseline_cache_is_not_shared_between_stage_selections
    previous = ENV.delete("MASTER_FIX_CHECK_STAGES")
    full = G.baseline_key("RAILS")
    ENV["MASTER_FIX_CHECK_STAGES"] = "lexical"

    refute_equal full, G.baseline_key("RAILS")
  ensure
    previous ? ENV["MASTER_FIX_CHECK_STAGES"] = previous : ENV.delete("MASTER_FIX_CHECK_STAGES")
  end

  def test_full_fix_declares_exactly_the_stages_that_write
    writers = G.stages(scan_only: false).select(&:mutates).map(&:name)

    assert_equal %w[lexical source sprawl council], writers
  end

  # --tree exists to run less. Its whole risk is running less than the caller
  # thinks: a narrowed ladder that still calls itself a check, or a typo that
  # narrows it to nothing and exits clean.
  def test_tree_scoping_drops_the_stages_that_prove_another_tree
    scoped = G.stages(scan_only: true, trees: %w[MASTER]).map(&:name)

    refute_includes scoped, "source", "the RAILS check runner says nothing about MASTER"
    refute_includes scoped, "openbsd", "the OpenBSD check runner says nothing about MASTER"
    refute_includes scoped, "rehearse", "the deploy rehearsal covers RAILS and OPENBSD only"
    assert_includes scoped, "ratchets", "the ratchets are repo-wide by definition and cheap"
    assert_equal %w[MASTER tools], G.suite_jobs(%w[MASTER]).map(&:first)
    assert_equal ["RAILS contracts", "brgen suite", "amber suite", "bsdports suite"],
                 G.suite_jobs(%w[RAILS]).map(&:first)
  end

  def test_all_four_tree_suite_jobs_are_reachable
    jobs = G.suite_jobs(G::TREES)
    assert_includes jobs.map(&:first), "tools"
    assert_includes jobs.map(&:first), "STUDIO media"
    assert_equal 8, jobs.size
  end

  def test_every_suite_has_a_bounded_timeout_and_operator_overrides_are_respected
    assert_equal 1_800, G.suite_timeout_s("MASTER")
    assert_equal 1_200, G.suite_timeout_s("brgen suite")
    assert_equal 900, G.suite_timeout_s("STUDIO media")

    key = "PUB4_CHECK_TIMEOUT_STUDIO_MEDIA"
    previous = ENV[key]
    ENV[key] = "45"
    assert_equal 45, G.suite_timeout_s("STUDIO media")
  ensure
    previous.nil? ? ENV.delete(key) : ENV[key] = previous
  end

  # Every other test stubs disk_state; a load-order fault in it refused every stage of a real check run,
  # where Io::Exec has already been required.
  def test_disk_state_measures_in_a_process_that_loads_only_the_check_chain
    lib = File.expand_path("../lib", __dir__)
    script = 'require "io/exec"; require "operator/check_chain"; g = Operator::CheckChain; ' \
             "print g.disk_state([g::ROOT])[:free_gb].class"
    out, status = Open3.capture2e(RbConfig.ruby, "-I", lib, "-e", script)

    assert status.success?, out
    assert_equal "Float", out.lines.last.to_s.strip
  end

  def test_check_capture_refuses_to_start_a_child_when_disk_is_critical
    Dir.mktmpdir do |dir|
      G.stub(:disk_state, ->(*) { { free_gb: 1.0, critical: true } }) do
        Master::Trace::Dmesg.stub(:status, ->(*) {}) do
          ok, lines, status = G.capture(
            RbConfig.ruby, "-e", "File.write('sentinel', 'bad')", chdir: dir
          )

          refute ok
          assert_equal 1, status
          assert_match(/disk preflight/, lines.join("\n"))
          refute File.exist?(File.join(dir, "sentinel")), "child wrote despite critical disk pressure"
        end
      end
    end
  end

  def test_check_capture_kills_a_child_that_exceeds_its_deadline_and_names_it
    Dir.mktmpdir do |dir|
      messages = []
      G.stub(:disk_state, ->(*) { { free_gb: 10.0, critical: false } }) do
        Master::Trace::Dmesg.stub(:status, ->(unit, message, **) { messages << "#{unit}: #{message}" }) do
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          ok, lines, status = G.capture(
            RbConfig.ruby, "-e", "sleep 30", chdir: dir, timeout_s: 0.1, disk_poll_s: 0.01,
            label: "regression child", heartbeat_unit: "suite0"
          )
          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

          refute ok
          assert_equal 124, status
          assert_match(/regression child: check child timeout/, lines.join("\n"))
          assert_includes messages, "suite0: regression child running"
          assert_operator elapsed, :<, 3, "the check child was left running after its deadline"
        end
      end
    end
  end

  def test_check_capture_stops_a_running_child_when_disk_becomes_critical
    Dir.mktmpdir do |dir|
      reads = 0
      lock = Mutex.new
      state = lambda do |*|
        count = lock.synchronize { reads += 1 }
        count == 1 ? { free_gb: 10.0, critical: false } : { free_gb: 1.0, critical: true }
      end

      G.stub(:disk_state, state) do
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        ok, lines, status = G.capture(
          RbConfig.ruby, "-e", "sleep 30", chdir: dir, timeout_s: 5, disk_poll_s: 0.01
        )
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

        refute ok
        assert_equal 1, status
        assert_match(/disk guard/, lines.join("\n"))
        assert_operator elapsed, :<, 3, "the check child continued writing after disk pressure"
      end
    end
  end

  def test_openbsd_suite_discovers_nested_tests
    Dir.mktmpdir do |root|
      nested = File.join(root, "test", "nested")
      FileUtils.mkdir_p(nested)
      File.write(File.join(nested, "test_marker.rb"), 'File.write("nested-ran", "ok")')

      output, status = Open3.capture2e(RbConfig.ruby, "-e", G::OPENBSD_SUITE, chdir: root)

      assert status.success?, output
      assert_equal "ok", File.read(File.join(root, "nested-ran"))
    end
  end

  def test_openbsd_suite_refuses_to_pass_with_zero_tests
    Dir.mktmpdir do |root|
      output, status = Open3.capture2e(RbConfig.ruby, "-e", G::OPENBSD_SUITE, chdir: root)

      refute status.success?, "an empty test discovery must not report green"
      assert_includes output, "no test files discovered"
    end
  end

  def test_suite_stage_has_a_human_readable_purpose
    assert_equal "complete test suites over all four trees", G.suite_purpose(G::TREES)
    assert_equal "complete test suites over MASTER, RAILS, OPENBSD", G.suite_purpose(%w[MASTER RAILS OPENBSD])
  end

  def test_openbsd_scope_has_a_check_stage
    scoped = G.stages(scan_only: true, trees: %w[OPENBSD]).map(&:name)

    assert_includes scoped, "openbsd"
    refute_includes scoped, "source"
    assert_equal %w[lexical openbsd rehearse suites ratchets sprawl council], scoped
  end

  def test_fix_verification_leaves_the_suites_to_the_pass_proof
    lexical = G::Stage.new(name: "lexical", purpose: "lexical", mutates: false, run: -> {})
    suites = G::Stage.new(name: "suites", purpose: "suites", mutates: false, run: -> {})
    captured = nil

    G.stub(:stages, [lexical, suites]) do
      G.stub(:report, ->(selected, **_kwargs) { captured = selected; [0, []] }) do
        G.verify_fix(target: "MASTER")
      end
    end

    assert_equal %w[lexical], captured.map(&:name)
  end

  def committed_repo(root)
    %w[MASTER RAILS].each { |tree| FileUtils.mkdir_p(File.join(root, tree)) }
    File.write(File.join(root, "MASTER", "a.rb"), "A = 1\n")
    File.write(File.join(root, "RAILS", "b.rb"), "B = 1\n")
    git = ->(*args) { system("git", "-C", root, *args, out: File::NULL, err: File::NULL) }
    git.call("init", "-q")
    git.call("add", ".")
    git.call("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "base")
  end

  def test_the_baseline_key_ignores_changes_outside_the_target_trees
    Dir.mktmpdir do |root|
      committed_repo(root)
      key = -> { G.baseline_key("MASTER", root:, trees: ["MASTER"]) }
      before = key.call

      File.write(File.join(root, "RAILS", "b.rb"), "B = 2\n")
      assert_equal before, key.call

      File.write(File.join(root, "MASTER", "a.rb"), "A = 2\n")
      refute_equal before, key.call
    end
  end

  def test_pre_repair_baseline_names_its_read_only_phase_and_subsequent_repair
    stage = G::Stage.new(name: "lexical", purpose: "measurement", mutates: false, run: -> {})
    captured = nil
    fake_report = lambda do |selected, scan_only:, trees:, return_results:|
      captured = [selected, scan_only, trees, return_results]
      G.instance_variable_set(:@last_results, [])
      [0, []]
    end

    G.stub(:verification_stages, [stage]) do
      G.stub(:trees_for_target, ["MASTER"]) do
        G.stub(:baseline_key, "baseline-test") do
          G.stub(:read_baseline, nil) do
            G.stub(:report, fake_report) do
              G.stub(:write_baseline, true) do
                output, = capture_io { G.baseline(target: "MASTER") }
                assert_includes output, "baseline0: read-only pre-repair proof starting"
                assert_includes output, "repair follows"
                assert_includes output, "baseline0: pre-repair proof captured, clean baseline"
              end
            end
          end
        end
      end
    end

    assert_equal [[stage], true, ["MASTER"], true], captured
  end

  def test_check_verdict_prefers_aggregate_rails_counts_over_success_detail
    aggregate = "checks0 at rails: 17 pass, 8 fail, 0 skip, 0 inconclusive, 0 error in 1504.5s"

    assert_equal aggregate, G.verdict([
      "Failures:",
      "  - layout_suite failed",
      "ok: page UI/UX simulations clean across inventory",
      aggregate,
    ])
  end

  def test_pre_repair_baseline_blocks_mutation_of_a_preexisting_dirty_path_outside_target
    stage = G::Stage.new(name: "source", purpose: "measurement", mutates: false, run: -> {})
    # The target key holds while a root-level path outside it changes.
    fake_report = lambda do |_selected, scan_only:, trees:, return_results:|
      G.instance_variable_set(:@last_results, [
        G::Result.new(stage: "source", state: "ok", summary: "no attributed change", changed: [], body: ["source: clean"])
      ])
      [0, []]
    end

    stubs = {
      verification_stages: [stage], trees_for_target: ["MASTER"], baseline_key: "target-same",
      checkout_snapshot: {}, read_baseline: nil, report: fake_report,
      checkout_changes: ["README-untracked.md"],
      write_baseline: ->(*) { flunk("a mutated root-level file must not become the baseline") }
    }

    with_stubs(G, stubs) do
      error = assert_raises(G::BaselineMutation) { G.baseline(target: "MASTER") }
      assert_match(/changed checkout state/, error.message)
      assert_includes error.message, "README-untracked.md"
    end
  end

  # A committed repository with a MASTER file, a RAILS file and a root README; answers git.
  def checkout_fixture(root)
    { "MASTER/a.rb" => "A = 1\n", "RAILS/b.rb" => "B = 1\n", "README.md" => "before\n" }.each do |path, text|
      FileUtils.mkdir_p(File.dirname(File.join(root, path)))
      File.write(File.join(root, path), text)
    end
    git = ->(*args) { Open3.capture2e("git", "-C", root, *args).tap { |out, st| assert st.success?, out } }

    git.call("init", "-q")
    [%w[user.name Test], %w[user.email test@example.invalid]].each { |pair| git.call("config", *pair) }
    git.call("add", "--all")
    git.call("commit", "-q", "-m", "baseline")
    git
  end

  def test_checkout_changes_see_root_level_edits_but_not_another_sessions_commit
    Dir.mktmpdir("checkout-snapshot") do |root|
      git = checkout_fixture(root)
      File.write(File.join(root, "MASTER", "a.rb"), "A = 2\n")
      baseline = G.checkout_snapshot(root:)

      git.call("commit", "-q", "-m", "another session", "--", "MASTER/a.rb")
      assert_empty G.checkout_changes(baseline, root:), "a commit is not the measurement writing"
      File.write(File.join(root, "README.md"), "after\n")
      assert_equal ["README.md"], G.checkout_changes(baseline, root:), "root-level tracked change was missed"

      File.write(File.join(root, "README.md"), "before\n")
      File.write(File.join(root, "operator-note.txt"), "untracked\n")
      assert_equal ["operator-note.txt"], G.checkout_changes(baseline, root:), "root-level untracked file was missed"
    end
  end

  def test_regression_proof_cannot_pass_when_any_selected_stage_is_unmeasured
    source = G::Stage.new(name: "source", purpose: "source", mutates: false, run: -> {})
    deploy = G::Stage.new(name: "deploy_drift", purpose: "deployment evidence", mutates: false, run: -> {})
    previous_results = G.instance_variable_get(:@last_results)
    baseline = { "source" => ["production failed"] }
    current_results = [
      G::Result.new(stage: "source", state: "failed", summary: "production failed",
                    changed: [], body: ["production failed"]),
      G::Result.new(stage: "deploy_drift", state: "skipped", summary: "no deploy stamps",
                    changed: [], body: ["deploy_drift inconclusive"]),
    ]

    fake_report = lambda do |selected, **|
      assert_equal %w[source deploy_drift], selected.map(&:name)
      G.instance_variable_set(:@last_results, current_results)
      [1, []]
    end

    G.stub(:verification_stages, [source, deploy]) do
      G.stub(:report, fake_report) do
        status, changed = G.verify_fix(target: "RAILS", baseline:)

        assert_equal 1, status
        assert_empty changed
      end
    end
  ensure
    G.instance_variable_set(:@last_results, previous_results)
  end

  # Each stub in turn around the block, without one more level of nesting per stub.
  def with_stubs(object, stubs, &block)
    return yield if stubs.empty?

    (name, value), *rest = stubs.to_a
    object.stub(name, value) { with_stubs(object, rest.to_h, &block) }
  end

  def test_pre_repair_baseline_refuses_to_cache_after_a_read_only_stage_mutates
    stage = G::Stage.new(name: "source", purpose: "measurement", mutates: false, run: -> {})
    fake_report = lambda do |selected, scan_only:, trees:, return_results:|
      G.instance_variable_set(:@last_results, [
        G::Result.new(stage: "source", state: "failed", summary: "changed by non-mutating stage",
                      changed: ["MASTER/lib/changed.rb"], body: ["source: changed by non-mutating stage"])
      ])
      [1, ["MASTER/lib/changed.rb"]]
    end

    stubs = { verification_stages: [stage], trees_for_target: ["MASTER"], baseline_key: "baseline-mutation-test",
              read_baseline: nil, report: fake_report,
              write_baseline: ->(*) { flunk("an unsafe baseline was persisted") } }

    error = with_stubs(G, stubs) { assert_raises(G::BaselineMutation) { G.baseline(target: "MASTER") } }

    assert_match(/read-only pre-repair proof changed 1 attributed path/, error.message)
    assert_includes error.message, "MASTER/lib/changed.rb"
  end

  # Another writer's edit in another tree is named, and the baseline stands.
  def test_a_change_in_another_tree_does_not_block_the_baseline
    stage = G::Stage.new(name: "source", purpose: "measurement", mutates: false, run: -> {})
    outside = ->(_selected, scan_only:, trees:, return_results:) { [0, ["STUDIO/postpro/lib/stocks.rb"]] }
    saved = []
    stubs = { verification_stages: [stage], trees_for_target: ["MASTER"], baseline_key: "baseline-outside-test",
              read_baseline: nil, report: outside, write_baseline: ->(*args) { saved << args } }

    out, = capture_io { with_stubs(G, stubs) { G.baseline(target: "MASTER") } }

    assert_equal 1, saved.size
    assert_includes out, "another writer changed 1 path(s) outside MASTER during the baseline: STUDIO/postpro/lib/stocks.rb"
  end


  def test_rails_fix_verification_uses_the_rails_source_proof_without_generic_suite_duplication
    source = G::Stage.new(name: "source", purpose: "source", mutates: false, run: -> {})
    suites = G::Stage.new(name: "suites", purpose: "suites", mutates: false, run: -> {})
    captured = nil

    G.stub(:stages, [source, suites]) do
      G.stub(:report, ->(selected, **_kwargs) { captured = selected; [0, []] }) do
        G.verify_fix(target: "RAILS")
      end
    end

    assert_equal %w[source], captured.map(&:name)
  end

  def test_rails_checks_can_force_inconclusive_blocking_for_proofs
    captured_envs = []
    capture = ->(*_args, **kwargs) { captured_envs << kwargs.fetch(:env); [true, [], 0] }

    G.stub(:capture, capture) do
      G.rails_checks(scan_only: true)
      G.rails_checks(scan_only: true, strict_inconclusive: true)
    end

    assert_equal G.send(:strict_env).fetch("CHECK_STRICT_INCONCLUSIVE"), captured_envs[0].fetch("CHECK_STRICT_INCONCLUSIVE")
    assert_equal "1", captured_envs[1].fetch("CHECK_STRICT_INCONCLUSIVE")
  end

  # Rails verification delegates to premerge without narrowing flags. Keep its
  # default group set observable so a future --apps-only default cannot silently
  # turn a full /fix proof into a smaller one.
  def test_rails_premerge_default_lists_every_verification_group
    script = File.join(G::ROOT, "MASTER", "tools", "rails", "premerge.rb")
    ok, lines, status = G.capture(G::RUBY, script, "--list", chdir: G::ROOT)
    assert_equal 0, status, lines.join("\n")

    output = lines.join("\n")
    %w[apps pwa contracts coverage checks].each do |group|
      assert_match(/^\s*#{Regexp.escape(group)}\s/m, output, "premerge default omitted #{group}")
    end
  end

  def test_master_fix_verification_reaches_the_constitutional_self_test
    suite = G.suite_jobs(%w[MASTER]).find { |job| job.first == "MASTER" }
    assert_equal [G::RUBY, File.join(G::MASTER, "bin", "check"), "--profile=ci"], suite[1]
    check_source = File.read(File.join(G::MASTER, "bin", "check"))
    assert_includes check_source, 'rake["selftest"]'
  end

  def test_check_chain_loads_strict_mode_directly
    flags = G.send(:strict_env)

    assert_equal "0", flags.fetch("CHECK_REQUIRE_LIVE")
    assert_equal "0", flags.fetch("CHECK_STRICT_ERRORS")
  end

  def test_every_runtime_stage_uses_the_shared_ruby_selection
    assert_equal Operator::RubyRunner.check_ruby, G::RUBY
    assert_equal Operator::RubyRunner.bundle_cmd, G::BUNDLE

    rails = G.suite_jobs(%w[RAILS]).find { |job| job.first == "brgen suite" }
    assert_equal [G::RUBY, G::BUNDLE, "exec", G::RUBY, "-S", "rails", "test"], rails[1]

    tools = G.suite_jobs(%w[MASTER]).find { |job| job.first == "tools" }
    assert_equal [G::RUBY, "-S", "rake"], tools[1]
    assert_equal File.join(G::MASTER, "tools"), tools[2]
    assert_equal true, tools[5]
  end

  def test_studio_scope_has_a_media_suite
    jobs = G.suite_jobs(%w[STUDIO])
    studio = jobs.find { |job| job.first == "STUDIO media" }

    refute_nil studio
    assert_equal "STUDIO", studio[4]
    assert_equal [G::RUBY, "-S", "rake", "test"], studio[1]
    assert_equal File.join(G::ROOT, "STUDIO"), studio[2]
  end

  def test_every_suite_job_names_a_tree_the_scoping_knows
    strays = G.suite_jobs.map { |job| job[4] } - G::TREES

    assert_empty strays, "a suite tagged with a tree --tree cannot name is unreachable"
  end

  def test_an_unknown_tree_is_refused_rather_than_narrowing_to_nothing
    assert_equal G::TREES, G.normalise_trees(nil)
    assert_equal %w[RAILS], G.normalise_trees("rails")
    assert_raises(ArgumentError) { G.normalise_trees("NOPE") }
  end

  def test_malformed_council_harvest_has_no_executable_picks
    Dir.mktmpdir do |root|
      dir = File.join(root, ".master", "critiques")
      FileUtils.mkdir_p(dir)
      File.write(
        File.join(dir, "general_latest.md"),
        "# council critique — general\n\n- a proposal\n- another proposal\n",
      )

      assert_empty G.picks_in(dir)
    end
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

  # Exit 3 is `bin/check --semantic-only` saying it reached nobody. Read as a
  # failure, it blames the tree for a provider's billing.
  def test_exit_three_is_skipped_and_every_other_failure_is_a_failure
    assert_equal "ok", G.classify(true, 0)
    assert_equal "skipped", G.classify(false, 3)
    assert_equal "failed", G.classify(false, 1)
  end

  # design_baseline prints its summary above its detail, which is how
  # tools/sweep.rb once reported a detail row as the verdict.
  # A stage captures its output and can run for minutes. The first subtree /fix sat
  # silent through a whole MASTER suite run, so every stage runs under the heartbeat,
  # in its own unit.
  def test_every_stage_runs_under_the_heartbeat_in_its_own_unit
    spoken = []
    wrapper = lambda do |label, **options, &block|
      spoken << [label, options[:unit]]
      block.call({})
    end
    stage = G::Stage.new(name: "suites", purpose: "complete test suites", mutates: false, run: -> { [true, ["suite0: ok"], 0] })

    Operator::CheckHeartbeat.stub(:around, wrapper) do
      capture_io { G.send(:run_stage, stage, G.send(:dirty)) }
    end

    assert_equal [%w[suites suite0]], spoken
  end

  def test_the_verdict_is_the_summary_line_not_the_last_line
    body = ["sprawl_census: lone_dirs 53 (ceiling 53)", "  MASTER/foo.rb"]

    assert_equal "sprawl_census: lone_dirs 53 (ceiling 53)", G.verdict(body)
    assert_equal "openbsd: failed — reach", G.verdict(["deploy-openbsd10: clean", "openbsd: failed — reach"])
  end

  def test_internal_stage_children_do_not_receive_the_parent_lock_fd
    previous = ENV["MASTER_PROCESS_LOCK_FD"]
    ENV["MASTER_PROCESS_LOCK_FD"] = "91"
    _ok, body, status = G.send(:capture, G::RUBY, "-e", 'abort "lock fd leaked" if ENV["MASTER_PROCESS_LOCK_FD"]')

    assert_equal 0, status
    assert_empty body
  ensure
    previous.nil? ? ENV.delete("MASTER_PROCESS_LOCK_FD") : ENV["MASTER_PROCESS_LOCK_FD"] = previous
  end

  def test_internal_stage_children_do_not_inherit_the_parents_bundle
    previous = %w[RUBYOPT BUNDLE_GEMFILE].to_h { |key| [key, ENV.fetch(key, nil)] }
    ENV["BUNDLE_GEMFILE"] = File.join(G::MASTER, "Gemfile")
    ENV["RUBYOPT"] = "-W0"
    probe = 'abort "bundle leaked" if ENV["BUNDLE_GEMFILE"] || ENV["RUBYOPT"]'
    _ok, body, status = G.send(:capture, G::RUBY, "-e", probe)

    assert_equal 0, status, body.join("\n")
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def test_generated_paths_are_recognised_in_every_tree_that_has_them
    %w[STUDIO/replicate/lora/.cache/x.json RAILS/brgen/app/assets/builds/application.css
       RAILS/amber/public/assets/x.js MASTER/Gemfile.lock].each do |path|
      assert_match G::GENERATED, path
    end
    refute_match G::GENERATED, "MASTER/lib/operator/check_chain.rb"
  end

  def test_dirty_parser_keeps_both_sides_of_a_rename
    status = "R  old.rb\0new.rb\0 M changed.rb\0?? new.txt\0"

    assert_equal ["old.rb", "new.rb", "changed.rb", "new.txt"], G.send(:parse_dirty_paths, status)
  end

  def test_only_selects_a_subset_and_list_reports_it
    out, = capture_io { G.run(scan_only: true, only: %w[sprawl], list: true) }

    assert_includes out, "sprawl"
    refute_includes out, "lexical"
  end

  # /fix measures the failing ladder before it repairs anything, and that run costs minutes.
  # Keep distinct scope fingerprints in one bounded cache; targets within
  # the same governed tree share the same check scope across disposable worktrees.
  def test_baseline_records_are_reused_by_key_and_scoped_to_the_governed_tree
    saved = File.file?(G::BASELINE_FILE) ? File.read(G::BASELINE_FILE) : nil
    G.write_baseline("k1", { "suites" => ["x fail"] })
    G.write_baseline("k2", { "lexical" => ["y fail"] })

    assert_equal({ "suites" => ["x fail"] }, G.read_baseline("k1"))
    assert_equal({ "lexical" => ["y fail"] }, G.read_baseline("k2"))
    assert_nil G.read_baseline("missing")
    assert_equal G.baseline_key("MASTER/lib/a"), G.baseline_key("MASTER/lib/b")
    refute_equal G.baseline_key("MASTER/lib/a"), G.baseline_key("RAILS")
  ensure
    saved ? File.write(G::BASELINE_FILE, saved) : FileUtils.rm_f(G::BASELINE_FILE)
  end

  def test_verified_check_snapshot_can_be_rekeyed_for_the_resulting_revision
    saved = File.file?(G::BASELINE_FILE) ? File.read(G::BASELINE_FILE) : nil
    previous_results = G.instance_variable_get(:@last_results)
    G.clear_verified_fix_snapshots!
    G.instance_variable_set(:@last_results, [
      G::Result.new(stage: "suites", state: "failed", summary: "standing failure",
                    changed: [], body: ["x fail"])
    ])

    G.remember_verified_snapshot("MASTER")
    G.persist_verified_baselines!(["MASTER"])

    assert_equal({ "suites" => ["x fail"] }, G.read_baseline(G.baseline_key("MASTER")))
  ensure
    G.instance_variable_set(:@last_results, previous_results)
    G.clear_verified_fix_snapshots!
    saved ? File.write(G::BASELINE_FILE, saved) : FileUtils.rm_f(G::BASELINE_FILE)
  end

  def test_final_fix_proof_is_inconclusive_without_a_verified_candidate_baseline
    saved = File.file?(G::BASELINE_FILE) ? File.binread(G::BASELINE_FILE) : nil
    G.clear_verified_fix_snapshots!
    FileUtils.rm_f(G::BASELINE_FILE)

    result = nil
    capture_io { result = G.verify_cached_fix(target: "MASTER") }

    assert_equal [3, []], result
  ensure
    G.clear_verified_fix_snapshots!
    saved ? File.binwrite(G::BASELINE_FILE, saved) : FileUtils.rm_f(G::BASELINE_FILE)
  end

  def test_final_fix_proof_reuses_the_verified_baseline_for_its_candidate
    saved = File.file?(G::BASELINE_FILE) ? File.binread(G::BASELINE_FILE) : nil
    previous_results = G.instance_variable_get(:@last_results)
    G.clear_verified_fix_snapshots!
    key = G.baseline_key("MASTER")
    G.write_baseline(key, {})

    result = G.stub(:report, lambda { |_selected, scan_only:, trees:, return_results:|
      G.instance_variable_set(:@last_results, [])
      [0, []]
    }) do
      G.verify_cached_fix(target: "MASTER")
    end

    assert_equal [0, []], result
  ensure
    G.instance_variable_set(:@last_results, previous_results)
    G.clear_verified_fix_snapshots!
    saved ? File.binwrite(G::BASELINE_FILE, saved) : FileUtils.rm_f(G::BASELINE_FILE)
  end

  def test_untracked_scanned_source_content_invalidates_the_baseline_key
    Dir.mktmpdir("check-baseline") do |root|
      system("git", "-C", root, "init", "--quiet") || flunk("git init failed")
      FileUtils.mkdir_p(File.join(root, "app"))
      tracked = File.join(root, "app", "tracked.rb")
      File.write(tracked, "A = 1\n")
      system("git", "-C", root, "add", "app/tracked.rb") || flunk("git add failed")
      committed = system(
        "git", "-C", root, "-c", "user.name=MASTER", "-c", "user.email=master@example.invalid",
        "commit", "--quiet", "-m", "baseline",
      )
      flunk("git commit failed") unless committed

      File.write(File.join(root, "app", "new.rb"), "B = 1\n")
      first = G.baseline_key("app", root:, trees: ["app"])
      File.write(File.join(root, "app", "new.rb"), "B = 2\n")
      second = G.baseline_key("app", root:, trees: ["app"])

      refute_equal first, second, "untracked source content must participate in the fingerprint"
    end
  end

  def test_baseline_fingerprint_refuses_git_command_failure
    Dir.mktmpdir("not-a-repo") do |root|
      error = assert_raises(RuntimeError) { G.baseline_key("app", root:, trees: ["app"]) }
      assert_match(/git rev-parse failed/, error.message)
    end
  end
end
