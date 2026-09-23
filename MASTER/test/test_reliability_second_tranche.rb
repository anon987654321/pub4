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

  def test_transaction_recovers_a_crashed_open_pass_from_disk
    Dir.mktmpdir("master-tx") do |root|
      path = File.join(root, "a.rb")
      File.write(path, "before\n")
      tx = Master::Fix::Transaction.new(root:, paths: [path], id: "crashed-pass")
      tx.begin!
      File.write(path, "partial\n")
      tx.observe!
      recovered = Master::Fix::Transaction.recover!(root:, id: tx.id)

      assert recovered.ok?
      assert_equal "before\n", File.read(path)
      refute Dir.exist?(File.join(root, ".master", "fix_transactions", tx.id))
    end
  end

  def test_transaction_preserves_tree_when_delivery_was_already_started
    Dir.mktmpdir("master-tx") do |root|
      path = File.join(root, "a.rb")
      File.write(path, "before\n")
      tx = Master::Fix::Transaction.new(root:, paths: [path], id: "delivery-pass")
      tx.begin!
      File.write(path, "committed-locally\n")
      tx.observe!
      tx.begin_delivery!

      recovered = Master::Fix::Transaction.recover!(root:, id: tx.id)

      assert recovered.ok?
      assert_equal :preserved_delivery, recovered.value!
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

  def test_fix_journal_refuses_a_live_active_process
    Dir.mktmpdir("master-journal") do |root|
      journal = Master::Fix::RunJournal.new(root:)
      first = journal.start_or_resume(target: root, files: [], max_passes: 2, budget_seconds: 10)
      journal.send(:persist, { "version" => 1, "runs" => [first] })

      error = assert_raises(RuntimeError) do
        Master::Fix::RunJournal.new(root:).start_or_resume(
          target: root, files: [], max_passes: 2, budget_seconds: 10,
        )
      end

      assert_match(/another fix process is active/, error.message)
    end
  end

  def test_resource_budget_sheds_critical_load
    budget = Master::Fix::ResourceBudget.new(root: Dir.pwd, config: { "load" => {
      "load_avg_1m" => { "warn" => 1, "crit" => 2 },
      "master_rss_mb" => { "warn" => 100, "crit" => 200 },
    }})
    measurement = budget.send(:classify, load_avg_1m: 3.0, rss_mb: nil, fd_count: nil,
                              thread_count: nil, process_count: nil, disk_free_pct: 50,
                              network: true, llm_quota_exhausted: 0)

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
