# frozen_string_literal: true

require "tmpdir"
require_relative "test_helper"
require_relative "../lib/fix/transaction"

class TestFixTransaction < Minitest::Test
  def test_rollback_restores_the_snapshot
    Dir.mktmpdir do |dir|
      path = File.join(dir, "note.txt")
      File.write(path, "before")
      tx = Master::Fix::Transaction.new(root: dir, paths: ["note.txt"], id: "rollback")
      tx.begin!
      File.write(path, "after")
      tx.observe!

      result = tx.rollback!

      assert result.ok?
      assert_equal "before", File.read(path)
      refute tx.active?
    end
  end

  def test_transaction_reports_snapshot_cost_and_file_count
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "one.txt"), "one\n")
      File.write(File.join(dir, "two.txt"), "two\n")
      events = []
      bus = Object.new
      bus.define_singleton_method(:publish) { |event, **payload| events << [event, payload] }

      tx = Master::Fix::Transaction.new(root: dir, paths: %w[one.txt two.txt], id: "snapshot-metrics", bus:).begin!
      _event, payload = events.find { |event, _data| event == "fix:transaction_snapshot_summary" }

      refute_nil payload
      assert_equal 2, payload.fetch(:tracked_paths)
      assert_equal 2, payload.fetch(:file_snapshots)
      assert_operator payload.fetch(:elapsed_ms), :>=, 0
      assert tx.rollback!.ok?
    end
  end

  def test_rollback_refuses_an_unobserved_concurrent_change
    Dir.mktmpdir do |dir|
      path = File.join(dir, "note.txt")
      File.write(path, "before")
      tx = Master::Fix::Transaction.new(root: dir, paths: ["note.txt"], id: "conflict")
      tx.begin!
      File.write(path, "outside-change")

      result = tx.rollback!

      refute result.ok?
      assert_equal :policy, result.category
      assert_includes result.message, "concurrent changes"
      assert_equal "outside-change", File.read(path)
    end
  end

  def two_files(dir)
    %w[ours.txt theirs.txt].map { |name| File.join(dir, name).tap { |path| File.write(path, "before") } }
  end

  def test_a_released_foreign_change_is_left_alone_and_the_rest_rolls_back
    Dir.mktmpdir do |dir|
      ours, theirs = two_files(dir)
      tx = Master::Fix::Transaction.new(root: dir, paths: ["ours.txt", "theirs.txt"], id: "release").begin!
      File.write(ours, "after")
      tx.observe!
      File.write(theirs, "outside-change")

      assert_equal ["theirs.txt"], tx.release!(tx.conflicts)
      assert tx.rollback!.ok?
      assert_equal %w[before outside-change], [File.read(ours), File.read(theirs)]
    end
  end

  def test_corrupt_recovery_manifest_is_reported_and_preserved
    Dir.mktmpdir do |dir|
      path = File.join(dir, "note.txt")
      File.write(path, "before")
      id = "corrupt-manifest"
      tx = Master::Fix::Transaction.new(root: dir, paths: ["note.txt"], id:).begin!
      manifest = File.join(dir, ".master", "fix_transactions", id, "manifest.json")
      File.write(manifest, "{not-json")
      tx.send(:release_lock)
      tx.instance_variable_set(:@active, false)

      result = Master::Fix::Transaction::Recovery.recover!(root: dir, id:)

      refute result.ok?
      assert_equal :infrastructure, result.category
      assert_includes result.message, "manifest is corrupt"
      assert_equal "before", File.read(path)
      assert File.file?(manifest), "preserve corrupt evidence for diagnosis instead of deleting it"
    end
  end

  def test_recovery_rejects_a_manifest_path_that_escapes_the_transaction_root
    Dir.mktmpdir do |base|
      root = File.join(base, "repo")
      FileUtils.mkdir_p(root)
      outside = File.join(base, "outside.txt")
      File.write(outside, "preserve outside bytes")
      path = File.join(root, "note.txt")
      File.write(path, "before")
      id = "unsafe-path"
      tx = Master::Fix::Transaction.new(root:, paths: [path], id:).begin!
      manifest = File.join(root, ".master", "fix_transactions", id, "manifest.json")
      data = JSON.parse(File.read(manifest))
      snapshot = data.fetch("snapshots").delete("note.txt")
      snapshot["path"] = "../outside.txt"
      data["snapshots"]["../outside.txt"] = snapshot
      fingerprints = data.fetch("seen").delete("note.txt")
      data["seen"]["../outside.txt"] = fingerprints
      data["paths"] = ["../outside.txt"]
      File.write(manifest, JSON.pretty_generate(data))
      tx.send(:release_lock)
      tx.instance_variable_set(:@active, false)

      result = Master::Fix::Transaction::Recovery.recover!(root:, id:)

      refute result.ok?
      assert_equal :infrastructure, result.category
      assert_includes result.message, "unsafe or non-canonical path"
      assert_equal "preserve outside bytes", File.read(outside)
      assert_equal "before", File.read(path)
      assert Master::Fix::Transaction::Recovery.persisted?(root:, id:)
    end
  end

  def test_recovery_rejects_a_snapshot_store_outside_the_transaction
    Dir.mktmpdir do |base|
      root = File.join(base, "repo")
      FileUtils.mkdir_p(root)
      outside = File.join(base, "outside.txt")
      File.write(outside, "external content")
      path = File.join(root, "note.txt")
      File.write(path, "before")
      id = "unsafe-store"
      tx = Master::Fix::Transaction.new(root:, paths: [path], id:).begin!
      File.write(path, "after")
      tx.observe!
      manifest = File.join(root, ".master", "fix_transactions", id, "manifest.json")
      data = JSON.parse(File.read(manifest))
      data.fetch("snapshots").fetch("note.txt")["store"] = outside
      File.write(manifest, JSON.pretty_generate(data))
      tx.send(:release_lock)
      tx.instance_variable_set(:@active, false)

      result = Master::Fix::Transaction::Recovery.recover!(root:, id:)

      refute result.ok?
      assert_equal :infrastructure, result.category
      assert_includes result.message, "snapshot invalid: note.txt"
      assert_equal "after", File.read(path)
      assert_equal "external content", File.read(outside)
      assert Master::Fix::Transaction::Recovery.persisted?(root:, id:)
    end
  end

  def test_recovery_refuses_to_race_with_a_live_transaction
    Dir.mktmpdir do |dir|
      path = File.join(dir, "note.txt")
      File.write(path, "before")
      tx = Master::Fix::Transaction.new(root: dir, paths: ["note.txt"], id: "live-lock").begin!

      load_error = assert_raises(RuntimeError) do
        Master::Fix::Transaction::Recovery.load_persisted(root: dir, id: "live-lock")
      end
      assert_includes load_error.message, "active transaction holds the root lock"

      result = Master::Fix::Transaction::Recovery.recover!(root: dir, id: "live-lock")

      refute result.ok?
      assert_equal :infrastructure, result.category
      assert_includes result.message, "active transaction holds the root lock"
      assert tx.active?
      assert_equal "before", File.read(path)
      assert tx.rollback!.ok?
      assert_equal "before", File.read(path)
    end
  end

  def test_recovery_restores_an_open_transaction_after_post_write_observation
    Dir.mktmpdir do |dir|
      path = File.join(dir, "note.txt")
      File.write(path, "before")
      id = "recover"
      tx = Master::Fix::Transaction.new(root: dir, paths: ["note.txt"], id:)
      tx.begin!
      File.write(path, "after")
      tx.observe!
      tx.send(:release_lock)
      tx.instance_variable_set(:@active, false)

      result = Master::Fix::Transaction::Recovery.recover!(root: dir, id:)

      assert result.ok?
      assert_equal "before", File.read(path)
      refute Dir.exist?(File.join(dir, ".master", "fix_transactions", id))
    end
  end

  def test_failed_delivery_finalization_releases_lock_for_a_safe_retry
    Dir.mktmpdir do |dir|
      path = File.join(dir, "note.txt")
      File.write(path, "before")
      id = "delivery-retry"
      tx = Master::Fix::Transaction.new(root: dir, paths: ["note.txt"], id:).begin!
      File.write(path, "after")
      tx.observe!
      tx.delivery.begin!(head_before: "parent")
      tx.delivery.record_commit!(head_after: "commit-1")
      tx.send(:release_lock)
      tx.instance_variable_set(:@active, false)

      recovered = Master::Fix::Transaction::Recovery.load_persisted(root: dir, id:)
      failed = recovered.delivery.finalize!(head: "wrong-head")
      refute failed.ok?
      assert_includes failed.message, "delivery HEAD mismatch"
      assert Master::Fix::Transaction::Recovery.persisted?(root: dir, id:)

      retrying = Master::Fix::Transaction::Recovery.load_persisted(root: dir, id:)
      assert retrying.delivery.pending?
      completed = retrying.delivery.finalize!(head: "commit-1")

      assert completed.ok?
      refute Master::Fix::Transaction::Recovery.persisted?(root: dir, id:)
    end
  end

  def test_recovery_does_not_overwrite_a_write_whose_owner_is_ambiguous
    Dir.mktmpdir do |dir|
      path = File.join(dir, "note.txt")
      File.write(path, "before")
      id = "unobserved-write"
      tx = Master::Fix::Transaction.new(root: dir, paths: ["note.txt"], id:).begin!

      # Simulate a process dying between mutating a file and persisting its
      # post-write fingerprint. Recovery cannot prove whether this was our
      # incomplete write or another writer, so it must preserve the bytes and
      # report a conflict instead of blindly restoring the old snapshot.
      File.write(path, "after")
      tx.send(:release_lock)
      tx.instance_variable_set(:@active, false)

      result = Master::Fix::Transaction::Recovery.recover!(root: dir, id:)

      refute result.ok?
      assert_equal :policy, result.category
      assert_includes result.message, "concurrent changes"
      assert_equal "after", File.read(path)
      assert Master::Fix::Transaction::Recovery.persisted?(root: dir, id:),
             "the conflict manifest must remain for operator review"
    end
  end

  def test_checkpoint_advances_the_rollback_floor
    Dir.mktmpdir do |dir|
      path = File.join(dir, "note.txt")
      File.write(path, "before")
      tx = Master::Fix::Transaction.new(root: dir, paths: ["note.txt"], id: "checkpoint")
      tx.begin!

      File.write(path, "delivered")
      result = tx.checkpoint!(["note.txt"])

      assert result.ok?
      File.write(path, "later")
      tx.observe!
      rollback = tx.rollback!

      assert rollback.ok?
      assert_equal "delivered", File.read(path)
    end
  end
end
