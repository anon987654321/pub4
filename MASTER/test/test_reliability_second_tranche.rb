# frozen_string_literal: true

require "digest"
require_relative "test_helper"
require "open3"

class TestReliabilitySecondTranche < Minitest::Test
  def test_transaction_rolls_back_only_owned_files
    Dir.mktmpdir("master-tx") do |root|
      a = File.join(root, "a.rb")
      b = File.join(root, "b.rb")
      File.write(a, "a0\n")
      File.write(b, "b0\n")
      tx = Master::Fix::Transaction.new(root:, paths: [a])
      tx.begin!
      File.write(a, "a1\n")
      File.write(b, "b1\n")
      tx.observe!
      assert tx.rollback!.ok?
      assert_equal "a0\n", File.read(a)
      assert_equal "b1\n", File.read(b)
    end
  end

  def test_transaction_recovery_fails_closed_on_a_conflict
    Dir.mktmpdir("master-tx") do |root|
      path = File.join(root, "a.rb")
      File.write(path, "before\n")
      tx = Master::Fix::Transaction.new(root:, paths: [path], id: "conflict-pass")
      tx.begin!
      File.write(path, "master-change\n")
      tx.observe!
      File.write(path, "human-change\n")
      git_state = tx.rollback!

      assert git_state.err?
      assert_equal :policy, git_state.category
      assert_equal "human-change\n", File.read(path)
      assert tx.state.to_sym == :conflict
    end
  end

  def test_transaction_recovers_a_crashed_open_pass_from_disk
    Dir.mktmpdir("master-tx") do |root|
      path = File.join(root, "a.rb")
      File.write(path, "before\n")
      tx = Master::Fix::Transaction.new(root:, paths: [path], id: "crashed-pass")
      tx.begin!
      File.write(path, "partial\n")
      tx.observe!
      recovered = Master::Fix::Transaction::Recovery.recover!(root:, id: tx.id)

      assert recovered.ok?
      assert_equal "before\n", File.read(path)
      refute Dir.exist?(File.join(root, ".master", "fix_transactions", tx.id))
    end
  end

  def test_transaction_rolls_back_when_delivery_started_before_commit
    Dir.mktmpdir("master-tx") do |root|
      path = File.join(root, "a.rb")
      File.write(path, "before\n")
      tx = Master::Fix::Transaction.new(root:, paths: [path], id: "delivery-pass")
      tx.begin!
      File.write(path, "committed-locally\n")
      tx.observe!
      tx.delivery.begin!(head_before: "before")

      result = tx.rollback!

      assert result.ok?
      assert_equal "before\n", File.read(path)
      refute Master::Fix::Transaction::Recovery.persisted?(root:, id: tx.id)
    end
  end

  def test_transaction_preserves_tree_when_commit_was_recorded
    Dir.mktmpdir("master-tx") do |root|
      path = File.join(root, "a.rb")
      File.write(path, "before\n")
      tx = Master::Fix::Transaction.new(root:, paths: [path], id: "delivery-pass")
      tx.begin!
      File.write(path, "committed-locally\n")
      tx.observe!
      tx.delivery.begin!(head_before: "before")
      tx.delivery.record_commit!(head_after: "commit-1")

      recovered = Master::Fix::Transaction::Recovery.recover!(root:, id: tx.id)

      assert recovered.ok?
      assert_equal :delivery_pending, recovered.value![:state]
      assert_equal "commit-1", recovered.value![:commit]
      assert_equal "committed-locally\n", File.read(path)
    end
  end

  def test_transaction_rejects_path_traversal_ids
    assert_raises(ArgumentError) do
      Master::Fix::Transaction.new(root: Dir.mktmpdir, paths: [], id: "../escape")
    end
  end

  def test_transaction_refuses_unobserved_concurrent_change
    Dir.mktmpdir("master-tx") do |root|
      path = File.join(root, "a.rb")
      File.write(path, "before\n")
      tx = Master::Fix::Transaction.new(root:, paths: [path])
      tx.begin!
      File.write(path, "master-change\n")
      tx.observe!
      File.write(path, "human-change\n")

      result = tx.rollback!

      assert result.err?
      assert_equal :policy, result.category
      assert_equal "human-change\n", File.read(path)
    end
  end

  def test_transaction_removes_files_created_by_the_pass
    Dir.mktmpdir("master-tx") do |root|
      path = File.join(root, "created.rb")
      tx = Master::Fix::Transaction.new(root:, paths: [path])
      tx.begin!
      File.write(path, "new\n")
      tx.observe!
      assert tx.rollback!.ok?
      refute File.exist?(path)
    end
  end

  def test_committer_defers_commit_until_transaction_finishes
    Dir.mktmpdir("master-committer") do |root|
      path = File.join(root, "a.rb")
      File.write(path, "one\n")
      init_git(root)
      git(root, "add", "a.rb")
      git(root, "commit", "-m", "seed")

      fake_git = Class.new do
        attr_reader :commits

        def initialize(root)
          @root = root
          @commits = []
          @head = "seed"
        end

        def changed_paths
          out, status = Open3.capture2e("git", "-C", @root, "status", "--porcelain")
          status.success? ? out.lines.map { |line| line[3..].to_s.strip } : []
        end

        def commit(message, paths:)
          @commits << [message, paths]
          system("git", "-C", @root, "add", "--", *paths)
          ok = system("git", "-C", @root, "commit", "-q", "-m", message)
          raise "fake commit failed" unless ok
          @head = Digest::SHA1.hexdigest(message)[0, 12]
        end

        def push = true
        def head = @head
        def ahead_behind = [0, 0]
      end.new(root)

      committer = Master::Fix::FixLoop::Committer.new(git: fake_git, root:)
      committer.baseline!
      tx = Master::Fix::Transaction.new(root:, paths: [path])
      committer.begin_transaction!(tx)
      File.write(path, "two\n")

      assert_equal :staged, committer.commit_if_dirty("fix")
      assert_empty fake_git.commits
      result = committer.finish_transaction("fix", owned_paths: [path])

      assert result.ok?
      assert_equal 1, fake_git.commits.size
      assert_equal "two\n", File.read(path)
    end
  end

  def test_committer_refuses_a_change_not_observed_by_master
    Dir.mktmpdir("master-committer") do |root|
      path = File.join(root, "a.rb")
      File.write(path, "one\n")
      init_git(root)
      git(root, "add", "a.rb")
      git(root, "commit", "-m", "seed")

      fake_git = Class.new do
        def initialize(root) = @root = root
        def changed_paths
          out, status = Open3.capture2e("git", "-C", @root, "status", "--porcelain")
          status.success? ? out.lines.map { |line| line[3..].to_s.strip } : []
        end
        def head = "head"
        def push = true
        def ahead_behind = [0, 0]
        def commit(*) = raise "must not commit a concurrent edit"
      end.new(root)

      committer = Master::Fix::FixLoop::Committer.new(git: fake_git, root:)
      committer.baseline!
      tx = Master::Fix::Transaction.new(root:, paths: [path])
      committer.begin_transaction!(tx)
      File.write(path, "master-change\n")
      committer.commit_if_dirty("fix")
      File.write(path, "human-change\n")

      result = committer.finish_transaction("fix", owned_paths: [path])

      assert result.err?
      assert_equal :policy, result.category
      assert_equal "human-change\n", File.read(path)
    end
  end

  # promote! answers with a Result, which /runtime promote reads without a
  # rescue; what matters is that an option-shaped "commit" is refused before
  # it reaches git and that nothing is recorded.
  def test_known_good_refuses_invalid_commit_records
    Dir.mktmpdir("master-known-good") do |root|
      result = Master::Ground::KnownGood.new(root:).promote!(commit: "--hard")

      assert result.err?
      assert_match(/not a Git SHA/, result.message)
      refute File.exist?(File.join(root, Master::Ground::KnownGood::PATH))
    end
  end

  def test_known_good_refuses_rollback_when_git_status_cannot_be_measured
    Dir.mktmpdir("master-known-good") do |root|
      init_git(root)
      path = File.join(root, "a.rb")
      File.write(path, "one\n")
      git(root, "add", "a.rb")
      git(root, "commit", "-m", "one")
      good = git(root, "rev-parse", "HEAD")
      Master::Ground::KnownGood.new(root:).promote!(commit: good)

      status = Struct.new(:success?).new(false)
      Master::Io::Exec.stub(:capture2, ["", status]) do
        result = Master::Ground::KnownGood.new(root:).rollback!

        assert result.err?
        assert_equal :infrastructure, result.category
        assert_match(/git status failed while checking rollback safety/, result.message)
      end
    end
  end

  def test_known_good_promotes_only_explicit_commit
    Dir.mktmpdir("master-known-good") do |root|
      init_git(root)
      path = File.join(root, "a.rb")
      File.write(path, "one\n")
      git(root, "add", "a.rb")
      git(root, "commit", "-m", "one")
      sha = git(root, "rev-parse", "HEAD")
      record = Master::Ground::KnownGood.new(root:).promote!(commit: sha, paths: [path])

      assert record.ok?
      assert_equal sha, Master::Ground::KnownGood.new(root:).current["commit"]
      assert Master::Ground::KnownGood.new(root:).matches_head?
    end
  end

  def test_known_good_rolls_clean_checkout_back_to_promoted_commit
    Dir.mktmpdir("master-known-good") do |root|
      init_git(root)
      path = File.join(root, "a.rb")
      File.write(path, "one\n")
      git(root, "add", "a.rb")
      git(root, "commit", "-m", "one")
      good = git(root, "rev-parse", "HEAD")
      Master::Ground::KnownGood.new(root:).promote!(commit: good)

      File.write(path, "two\n")
      git(root, "add", "a.rb")
      git(root, "commit", "-m", "two")

      result = Master::Ground::KnownGood.new(root:).rollback!

      assert result.ok?
      assert_equal good, git(root, "rev-parse", "HEAD")
      assert_equal "one\n", File.read(path)
    end
  end

  def test_known_good_rollback_refuses_dirty_tree
    Dir.mktmpdir("master-known-good") do |root|
      init_git(root)
      path = File.join(root, "a.rb")
      File.write(path, "one\n")
      git(root, "add", "a.rb")
      git(root, "commit", "-m", "one")
      good = git(root, "rev-parse", "HEAD")
      File.write(path, "two\n")
      git(root, "add", "a.rb")
      git(root, "commit", "-m", "two")
      File.write(path, "dirty\n")
      record = Master::Ground::KnownGood.new(root:).promote!(commit: good)
      result = Master::Ground::KnownGood.new(root:).rollback!

      assert record.ok?
      assert result.err?
      assert_equal :policy, result.category
      assert_equal "dirty\n", File.read(path)
    end
  end

  def test_service_supervisor_tolerates_broken_telemetry
    bus = Object.new
    def bus.publish(*) = raise "telemetry failed"

    Dir.mktmpdir("master-service") do |root|
      supervisor = Master::Ground::ServiceSupervisor.new(root:, bus:)
      result = supervisor.ensure(
        name: "tts",
        start: -> {},
        healthy: -> { true },
      )

      assert result.ok?
      assert result.value!.healthy?
    end
  end

  def test_service_supervisor_resets_restart_budget_after_recovery
    Dir.mktmpdir("master-service") do |root|
      healthy = false
      starts = 0
      supervisor = Master::Ground::ServiceSupervisor.new(root:)
      first = supervisor.ensure(
        name: "tts",
        start: -> { starts += 1; healthy = true },
        healthy: -> { healthy },
        max_restarts: 2,
        window_seconds: 60,
        wait_seconds: 1,
      )

      assert first.ok?
      assert first.value!.healthy?
      assert_equal 1, starts
      assert_empty supervisor.state("tts")["attempts"]
    end
  end

  def test_service_supervisor_surfaces_start_failure_without_retrying_forever
    Dir.mktmpdir("master-service") do |root|
      supervisor = Master::Ground::ServiceSupervisor.new(root:)
      attempts = 0
      result = supervisor.ensure(
        name: "tts",
        start: -> { attempts += 1; raise "start failed" },
        healthy: -> { false },
        max_restarts: 3,
        window_seconds: 60,
        wait_seconds: 1,
      )

      assert result.err?
      assert_equal :infrastructure, result.category
      assert_equal 1, attempts
    end
  end

  def test_service_supervisor_stops_restart_storms
    Dir.mktmpdir("master-service") do |root|
      starts = 0
      supervisor = Master::Ground::ServiceSupervisor.new(root:)
      4.times do
        result = supervisor.ensure(
          name: "tts",
          start: -> { starts += 1 },
          healthy: -> { false },
          max_restarts: 2,
          window_seconds: 60,
          wait_seconds: 0,
        )
        assert result.ok?
        assert result.value!.degraded?
      end

      assert_equal 2, starts
    end
  end

  def test_fix_journal_preserves_the_original_deadline
    Dir.mktmpdir("master-journal") do |root|
      journal = Master::Fix::RunJournal.new(root:)
      first = journal.start_or_resume(target: root, files: [], max_passes: 5, budget_seconds: 1)
      journal.send(:persist, {
        "version" => 1,
        "runs" => [first.merge("state" => "crashed", "pid" => 0, "deadline_at" => (Time.now.utc - 1).iso8601)],
      })
      resumed = journal.start_or_resume(target: root, files: [], max_passes: 5, budget_seconds: 1)

      assert resumed["resumed"]
      assert_operator resumed["remaining_seconds"], :<=, 0
    end
  end

  def test_fix_journal_resumes_delivery_failed_runs
    Dir.mktmpdir("master-journal") do |root|
      journal = Master::Fix::RunJournal.new(root:)
      first = journal.start_or_resume(target: root, files: [], max_passes: 2, budget_seconds: 10)
      journal.send(:persist, {
        "version" => 1,
        "runs" => [first.merge(
          "state" => "delivery_failed",
          "passes" => [{
            "pass" => 1,
            "state" => "delivery_failed",
            "transaction_id" => "delivery-pass",
          }],
        )],
      })

      resumed = Master::Fix::RunJournal.new(root:).start_or_resume(
        target: root, files: [], max_passes: 2, budget_seconds: 10,
      )

      assert resumed["resumed"]
      assert_equal "delivery_failed", resumed["resumed_from"]
      assert_equal 2, Master::Fix::RunJournal.new(root:).next_pass(resumed)
    end
  end

  def test_fix_journal_refuses_a_live_active_process
    Dir.mktmpdir("master-journal") do |root|
      journal = Master::Fix::RunJournal.new(root:)
      first = journal.start_or_resume(target: root, files: [], max_passes: 2, budget_seconds: 10)
      # The journal lets a process resume its own run, so "another" process
      # has to be a different live pid: the parent is one.
      journal.send(:persist, { "version" => 1, "runs" => [first.merge("pid" => Process.ppid)] })

      error = assert_raises(RuntimeError) do
        Master::Fix::RunJournal.new(root:).start_or_resume(
          target: root, files: [], max_passes: 2, budget_seconds: 10,
        )
      end

      assert_match(/another fix process is active/, error.message)
    end
  end

  def test_resource_budget_fails_closed_when_measurement_breaks
    budget = Master::Fix::ResourceBudget.new(root: Dir.pwd)
    def budget.classify(_values)
      raise "probe failure"
    end

    measurement = budget.measure

    assert budget.critical?(measurement)
    assert_includes measurement[:reasons].first, "resource measurement failed"
  end

  def test_resource_budget_sheds_critical_load
    budget = Master::Fix::ResourceBudget.new(root: Dir.pwd, cpus: 1, config: { "load" => {
      "load_avg_1m" => { "warn" => 1, "crit" => 2 },
      "master_rss_mb" => { "warn" => 100, "crit" => 200 },
    }})
    measurement = budget.send(:classify, load_avg_1m: 3.0, rss_mb: nil, fd_count: nil,
                              thread_count: nil, process_count: nil, disk_free_gb: 50,
                              network: true, llm_quota_exhausted: 0)

    assert budget.critical?(measurement)
    assert_includes measurement[:reasons].first, "load_avg_1m"
  end

  def test_resource_budget_load_limits_are_per_cpu
    config = { "load" => { "load_avg_1m" => { "warn" => 1.5, "crit" => 2.5 } } }
    calm = { rss_mb: nil, fd_count: nil, thread_count: nil, process_count: nil,
             disk_free_gb: 50, network: true, llm_quota_exhausted: 0 }

    one = Master::Fix::ResourceBudget.new(root: Dir.pwd, cpus: 1, config:)
    eight = Master::Fix::ResourceBudget.new(root: Dir.pwd, cpus: 8, config:)

    assert one.critical?(one.send(:classify, **calm, load_avg_1m: 3.0))
    refute eight.critical?(eight.send(:classify, **calm, load_avg_1m: 3.0))
    assert eight.critical?(eight.send(:classify, **calm, load_avg_1m: 21.0))
  end

  def test_resource_budget_disk_floor_is_gigabytes_free
    budget = Master::Fix::ResourceBudget.new(root: Dir.pwd, cpus: 1, config: {})
    calm = { load_avg_1m: nil, rss_mb: nil, fd_count: nil, thread_count: nil, process_count: nil,
             network: true, llm_quota_exhausted: 0 }

    assert_equal :ok, budget.send(:classify, **calm, disk_free_gb: 14.0)[:state], "14 GB free is room"
    assert budget.warning?(budget.send(:classify, **calm, disk_free_gb: 4.0))
    assert budget.critical?(budget.send(:classify, **calm, disk_free_gb: 1.5))
  end

  def test_resource_budget_process_limits_follow_the_platform
    config = { "resources" => { "process_count" => {
      "warn" => 256, "crit" => 512, "darwin" => { "warn" => 1200, "crit" => 1600 }
    } } }
    idle_mac = { load_avg_1m: nil, rss_mb: nil, fd_count: nil, thread_count: nil, process_count: 602,
                 disk_free_gb: 50, network: true, llm_quota_exhausted: 0 }

    mac = Master::Fix::ResourceBudget.new(root: Dir.pwd, cpus: 1, config:, platform: "arm64-darwin25")
    vm23 = Master::Fix::ResourceBudget.new(root: Dir.pwd, cpus: 1, config:, platform: "x86_64-openbsd7.8")

    assert_equal :ok, mac.send(:classify, **idle_mac)[:state]
    assert vm23.critical?(vm23.send(:classify, **idle_mac))
    assert mac.critical?(mac.send(:classify, **idle_mac, process_count: 1700))
  end

  def test_resource_budget_reads_load_on_this_host
    skip "no sysctl or /proc/loadavg here" unless ["/sbin/sysctl", "/usr/sbin/sysctl", "/proc/loadavg"].any? { |p| File.exist?(p) }

    load = Master::Fix::ResourceBudget.new(root: Dir.pwd).send(:load_average)

    refute_nil load, "the load guard is silently off when the probe finds nothing"
  end

  def test_transaction_exposes_interrupted_delivery_without_discarding_it
    Dir.mktmpdir("master-tx") do |root|
      path = File.join(root, "a.rb")
      File.write(path, "before\n")
      tx = Master::Fix::Transaction.new(root:, paths: [path], id: "delivery-pass")
      tx.begin!
      File.write(path, "committed-locally\n")
      tx.observe!
      tx.delivery.begin!(head_before: "before")
      tx.delivery.record_commit!(head_after: "after")

      recovery = Master::Fix::Transaction::Recovery.recover!(root:, id: tx.id)

      assert recovery.ok?
      assert_equal :delivery_pending, recovery.value![:state]
      assert_equal "after", recovery.value![:commit]
      assert_equal "committed-locally\n", File.read(path)
    end
  end

  def test_transaction_can_finalize_a_recovered_delivery
    Dir.mktmpdir("master-tx") do |root|
      path = File.join(root, "a.rb")
      File.write(path, "before\n")
      tx = Master::Fix::Transaction.new(root:, paths: [path], id: "delivery-finalize")
      tx.begin!
      File.write(path, "after\n")
      tx.observe!
      tx.delivery.begin!(head_before: "before")
      tx.delivery.record_commit!(head_after: "commit-1")

      recovered = Master::Fix::Transaction::Recovery.load_persisted(root:, id: tx.id)
      assert recovered.delivery.pending?
      result = recovered.delivery.finalize!(head: "commit-1")

      assert result.ok?
      refute Master::Fix::Transaction::Recovery.persisted?(root:, id: tx.id)
    end
  end

  private

  # pub4 ignores MASTER's state directory, so a fixture repo does too; without
  # it the known-good record promote! writes reads as a dirty tree.
  def init_git(root)
    git(root, "init", "-q")
    git(root, "config", "user.email", "test@example.com")
    git(root, "config", "user.name", "test")
    File.write(File.join(root, ".git", "info", "exclude"), ".master/\n")
  end

  def git(root, *args)
    out, status = Open3.capture2e("git", "-C", root, *args)
    raise out unless status.success?

    out.strip
  end
end
