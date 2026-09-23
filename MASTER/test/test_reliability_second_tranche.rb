# frozen_string_literal: true

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
      assert_equal "two\n", File.read(path)

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
        wait_seconds: 0,
      )

      assert first.ok?
      assert first.value!.healthy?
      assert_equal 1, starts
      assert_empty supervisor.state("tts")["attempts"]
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
        "runs" => [first.merge("deadline_at" => (Time.now.utc - 1).iso8601)],
      })
      resumed = journal.start_or_resume(target: root, files: [], max_passes: 5, budget_seconds: 1)

      assert resumed["resumed"]
      assert_operator resumed["remaining_seconds"], :<=, 0
    end
  end

  def test_resource_budget_sheds_critical_load
    budget = Master::Fix::ResourceBudget.new(root: Dir.pwd, config: { "load" => {
      "load_avg_1m" => { "warn" => 1, "crit" => 2 },
      "master_rss_mb" => { "warn" => 100, "crit" => 200 },
    }})
    measurement = budget.send(:classify, load_avg_1m: 3.0, rss_mb: nil, fd_count: nil,
                              thread_count: nil, disk_free_pct: 50)

    assert budget.critical?(measurement)
    assert_includes measurement[:reasons].first, "load_avg_1m"
  end

  private

  def init_git(root)
    git(root, "init", "-q")
    git(root, "config", "user.email", "test@example.com")
    git(root, "config", "user.name", "test")
  end

  def git(root, *args)
    out, status = Open3.capture2e("git", "-C", root, *args)
    raise out unless status.success?

    out.strip
  end
end
