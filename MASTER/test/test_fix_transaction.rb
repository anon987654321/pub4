# frozen_string_literal: true

require "tmpdir"
require_relative "test_helper"
require_relative "../lib/fix/transaction"

class TestFixTransaction < Minitest::Test
  def test_transaction_id_collision_preserves_the_existing_manifest
    Dir.mktmpdir do |dir|
      path = File.join(dir, "note.txt")
      File.write(path, "before")
      id = "stable-id"
      original = Master::Fix::Transaction.new(root: dir, paths: ["note.txt"], id:).begin!
      manifest = File.join(dir, ".master", "fix_transactions", id, "manifest.json")
      before_manifest = File.binread(manifest)
      original.send(:release_lock)
      original.instance_variable_set(:@active, false)

      replacement = Master::Fix::Transaction.new(root: dir, paths: ["note.txt"], id:)
      error = assert_raises(RuntimeError) { replacement.begin! }

      assert_includes error.message, "transaction id already exists"
      refute replacement.active?
      assert_equal before_manifest, File.binread(manifest)
      assert_equal "before", File.read(path)

      recovered = Master::Fix::Transaction::Recovery.recover!(root: dir, id:)
      assert recovered.ok?, -> { recovered.message.to_s }
      refute File.exist?(manifest)
    end
  end

  def test_begin_failure_after_durable_manifest_leaves_object_inactive_and_recoverable
    Dir.mktmpdir do |dir|
      path = File.join(dir, "note.txt")
      File.write(path, "before")
      id = "durable-start"
      tx = Master::Fix::Transaction.new(root: dir, paths: ["note.txt"], id:)
      original_persist = tx.method(:persist!)
      tx.define_singleton_method(:persist!) do
        original_persist.call
        raise "simulated post-persist failure"
      end

      error = assert_raises(RuntimeError) { tx.begin! }

      assert_equal "simulated post-persist failure", error.message
      refute tx.active?, "a failed begin cannot claim ownership after releasing its lock"
      assert Master::Fix::Transaction::Recovery.persisted?(root: dir, id:)
      assert_equal "before", File.read(path)

      recovered = Master::Fix::Transaction::Recovery.recover!(root: dir, id:)
      assert recovered.ok?, -> { recovered.message.to_s }
      refute Master::Fix::Transaction::Recovery.persisted?(root: dir, id:)
      assert_equal "before", File.read(path)
    end
  end

  def test_transaction_refuses_a_symlinked_state_directory_before_writing
    Dir.mktmpdir do |base|
      root = File.join(base, "repo")
      outside = File.join(base, "outside")
      FileUtils.mkdir_p([root, outside])
      File.symlink(outside, File.join(root, ".master"))

      tx = Master::Fix::Transaction.new(root:, paths: [], id: "state-symlink")
      error = assert_raises(RuntimeError) { tx.begin! }

      assert_includes error.message, "MASTER state directory is a symlink"
      assert_empty Dir.children(outside)
      refute tx.active?
    end
  end

  def test_recovery_refuses_a_symlinked_snapshot_storage_directory
    Dir.mktmpdir do |base|
      root = File.join(base, "repo")
      outside = File.join(base, "outside")
      FileUtils.mkdir_p([root, outside])
      path = File.join(root, "note.txt")
      File.write(path, "before")
      id = "snapshot-symlink"
      tx = Master::Fix::Transaction.new(root:, paths: [path], id:).begin!
      files = File.join(root, ".master", "fix_transactions", id, "files")
      moved = File.join(base, "saved-snapshots")
      FileUtils.mv(files, moved)
      File.write(File.join(outside, "sentinel"), "do not touch")
      File.symlink(outside, files)
      tx.send(:release_lock)
      tx.instance_variable_set(:@active, false)

      recovery = Master::Fix::Transaction::Recovery.recover!(root:, id:)

      refute recovery.ok?
      assert_equal :infrastructure, recovery.category
      assert_includes recovery.message, "transaction snapshot directory is a symlink"
      assert_equal "do not touch", File.read(File.join(outside, "sentinel"))
      assert_equal "before", File.read(path)
      assert Master::Fix::Transaction::Recovery.persisted?(root:, id:)
    end
  end

  def test_transaction_id_collision_preserves_an_orphan_directory_for_diagnosis
    Dir.mktmpdir do |dir|
      id = "orphan-collision"
      orphan = File.join(dir, ".master", "fix_transactions", id)
      FileUtils.mkdir_p(orphan)
      sentinel = File.join(orphan, "preserve-me")
      File.write(sentinel, "operator evidence")

      tx = Master::Fix::Transaction.new(root: dir, paths: [], id:)
      error = assert_raises(RuntimeError) { tx.begin! }

      assert_includes error.message, "transaction id already exists"
      refute tx.active?
      assert_equal "operator evidence", File.read(sentinel)
    end
  end

  def test_transaction_refuses_unsupported_directory_paths_without_leaving_a_partial_snapshot
    Dir.mktmpdir do |dir|
      tx = Master::Fix::Transaction.new(root: dir, paths: ["."], id: "directory-path")

      error = assert_raises(RuntimeError) { tx.begin! }

      assert_includes error.message, "unsupported filesystem object"
      refute tx.active?
      refute Dir.exist?(File.join(dir, ".master", "fix_transactions", "directory-path"))
    end
  end

  def test_transaction_rejects_paths_outside_its_workspace_instead_of_dropping_them
    Dir.mktmpdir do |dir|
      error = assert_raises(RuntimeError) do
        Master::Fix::Transaction.new(root: dir, paths: ["../outside.txt"], id: "outside-path")
      end

      assert_includes error.message, "transaction contains an unsafe path"
      refute File.exist?(File.join(dir, ".master", "fix_transactions", "outside-path"))
    end
  end

  def test_transaction_refuses_a_path_through_a_symlinked_parent
    Dir.mktmpdir do |base|
      root = File.join(base, "repo")
      outside = File.join(base, "outside")
      FileUtils.mkdir_p([root, outside])
      outside_file = File.join(outside, "note.txt")
      File.write(outside_file, "outside bytes")
      File.symlink(outside, File.join(root, "linked"))

      tx = Master::Fix::Transaction.new(root:, paths: ["linked/note.txt"], id: "symlink-parent")
      error = assert_raises(RuntimeError) { tx.begin! }

      assert_includes error.message, "path escapes workspace"
      refute tx.active?
      assert_equal "outside bytes", File.read(outside_file)
      refute Dir.exist?(File.join(root, ".master", "fix_transactions", "symlink-parent"))
    end
  end

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

  def test_transaction_reports_the_snapshot_path_count
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

  def test_recovery_rejects_a_symlinked_snapshot_store_even_after_terminal_state
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "note.txt"), "before")
      tx = Master::Fix::Transaction.new(root: dir, paths: ["note.txt"], id: "symlink-store").begin!
      manifest = File.join(dir, ".master", "fix_transactions", tx.id, "manifest.json")
      data = JSON.parse(File.read(manifest))
      store = data.fetch("snapshots").fetch("note.txt").fetch("store")
      tx.send(:release_lock)
      tx.instance_variable_set(:@active, false)
      tx.send(:cleanup!)

      outside = File.join(dir, "outside")
      File.write(outside, "do not read")
      storage = File.join(dir, ".master", "fix_transactions", tx.id, "files")
      FileUtils.mkdir_p(storage)
      File.symlink(outside, store)
      data["state"] = "committed"
      File.write(manifest, JSON.generate(data))

      error = assert_raises(RuntimeError) do
        Master::Fix::Transaction::Recovery.load_persisted(root: dir, id: tx.id)
      end
      assert_match(/snapshot invalid/, error.message)
      assert_equal "do not read", File.read(outside)
    end
  end

  def test_recovery_rejects_non_string_delivery_head_metadata
    Dir.mktmpdir do |dir|
      tx = Master::Fix::Transaction.new(root: dir, paths: [], id: "bad-delivery-head").begin!
      manifest = File.join(dir, ".master", "fix_transactions", tx.id, "manifest.json")
      tx.send(:release_lock)
      tx.instance_variable_set(:@active, false)
      data = JSON.parse(File.read(manifest))
      data["delivery_head_after"] = { "unexpected" => "object" }
      File.write(manifest, JSON.generate(data))

      error = assert_raises(RuntimeError) do
        Master::Fix::Transaction::Recovery.load_persisted(root: dir, id: tx.id)
      end
      assert_match(/delivery heads malformed/, error.message)
    end
  end

  def test_recovery_preserves_conflict_manifest_and_snapshots_for_diagnosis
    Dir.mktmpdir do |dir|
      path = File.join(dir, "note.txt")
      File.write(path, "before")
      tx = Master::Fix::Transaction.new(root: dir, paths: ["note.txt"], id: "conflict-evidence").begin!
      File.write(path, "master change")
      tx.observe!
      File.write(path, "operator change")

      result = tx.rollback!
      assert result.err?
      assert_equal :policy, result.category
      assert_equal "operator change", File.read(path)

      manifest = File.join(dir, ".master", "fix_transactions", tx.id, "manifest.json")
      assert File.file?(manifest)
      recovery = Master::Fix::Transaction::Recovery.recover!(root: dir, id: tx.id)

      assert recovery.err?
      assert_equal :policy, recovery.category
      assert File.file?(manifest), "conflict evidence must remain available for operator diagnosis"
      assert_equal "operator change", File.read(path)
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

  def test_initial_snapshot_refuses_a_source_changed_during_capture
    Dir.mktmpdir do |dir|
      path = File.join(dir, "note.txt")
      File.write(path, "before")
      tx = Master::Fix::Transaction.new(root: dir, paths: ["note.txt"], id: "source-race")
      original_snapshot = tx.method(:snapshot)
      tx.define_singleton_method(:snapshot) do |relative, versioned: false|
        captured = original_snapshot.call(relative, versioned:)
        File.write(File.join(dir, relative), "concurrent edit")
        captured
      end

      error = assert_raises(RuntimeError) { tx.begin! }

      assert_includes error.message, "source changed during initial snapshot"
      refute tx.active?
      assert_equal "concurrent edit", File.read(path)
      refute Master::Fix::Transaction::Recovery.persisted?(root: dir, id: "source-race")
      refute Dir.exist?(File.join(dir, ".master", "fix_transactions", "source-race"))
    end
  end

  def test_failed_observation_does_not_make_an_unpersisted_change_look_owned
    Dir.mktmpdir do |dir|
      path = File.join(dir, "note.txt")
      File.write(path, "before")
      tx = Master::Fix::Transaction.new(root: dir, paths: ["note.txt"], id: "observe-failure").begin!
      original_persist = tx.method(:persist!)
      File.write(path, "concurrent or unverified change")
      tx.define_singleton_method(:persist!) { raise "simulated manifest write failure" }

      result = tx.observe_paths!(["note.txt"])

      refute result.ok?
      assert_equal :infrastructure, result.category
      refute tx.observed_current?("note.txt"), "failed persistence must not advance the in-memory ownership fingerprint"

      tx.define_singleton_method(:persist!) { original_persist.call }
      rollback = tx.rollback!

      refute rollback.ok?
      assert_equal :policy, rollback.category
      assert_equal "concurrent or unverified change", File.read(path)
    end
  end

  def test_failed_enlistment_restores_the_durable_ownership_boundary
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "tracked.txt"), "before")
      File.write(File.join(dir, "related.txt"), "related")
      tx = Master::Fix::Transaction.new(root: dir, paths: ["tracked.txt"], id: "enlist-write-failure").begin!
      original_persist = tx.method(:persist!)
      tx.define_singleton_method(:persist!) { raise "simulated manifest write failure" }

      result = tx.enlist!(["related.txt"])

      refute result.ok?
      assert_equal :infrastructure, result.category
      assert_equal ["tracked.txt"], tx.instance_variable_get(:@paths)
      assert_equal ["tracked.txt"], tx.instance_variable_get(:@snapshots).keys
      manifest = File.join(dir, ".master", "fix_transactions", tx.id, "manifest.json")
      data = JSON.parse(File.read(manifest))
      assert_equal ["tracked.txt"], data.fetch("paths")
      assert_equal ["tracked.txt"], data.fetch("snapshots").keys

      tx.define_singleton_method(:persist!) { original_persist.call }
      assert tx.rollback!.ok?
      assert_equal "before", File.read(File.join(dir, "tracked.txt"))
      assert_equal "related", File.read(File.join(dir, "related.txt"))
    end
  end

  def test_enlistment_rejects_a_directory_without_corrupting_the_open_transaction
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "note.txt"), "before")
      Dir.mkdir(File.join(dir, "assets"))
      tx = Master::Fix::Transaction.new(root: dir, paths: ["note.txt"], id: "enlist-directory").begin!

      result = tx.enlist!(["assets"])

      refute result.ok?
      assert_equal :policy, result.category
      assert_equal ["note.txt"], tx.instance_variable_get(:@paths)
      manifest = File.join(dir, ".master", "fix_transactions", tx.id, "manifest.json")
      data = JSON.parse(File.read(manifest))
      assert_equal ["note.txt"], data.fetch("paths")
      assert_equal ["note.txt"], data.fetch("snapshots").keys
      assert tx.rollback!.ok?
      assert_equal "before", File.read(File.join(dir, "note.txt"))
      assert Dir.exist?(File.join(dir, "assets"))
    end
  end

  def test_checkpoint_refuses_a_file_replaced_with_a_directory_and_preserves_old_backup
    Dir.mktmpdir do |dir|
      path = File.join(dir, "note.txt")
      File.write(path, "before")
      tx = Master::Fix::Transaction.new(root: dir, paths: ["note.txt"], id: "checkpoint-directory").begin!
      original_store = tx.instance_variable_get(:@snapshots).fetch("note.txt").store
      original_bytes = File.binread(original_store)
      File.delete(path)
      Dir.mkdir(path)

      result = tx.checkpoint!(["note.txt"])

      refute result.ok?
      assert_equal :policy, result.category
      assert_equal original_bytes, File.binread(original_store)
      assert_equal "before", File.binread(original_store)
      rollback = tx.rollback!
      refute rollback.ok?, "a concurrent filesystem type change is not safe to roll back automatically"
      assert_equal :policy, rollback.category
      assert Dir.exist?(path)
    end
  end

  def test_recovery_restores_the_versioned_checkpoint_after_process_loss
    Dir.mktmpdir do |dir|
      path = File.join(dir, "note.txt")
      File.write(path, "before")
      id = "checkpoint-recovery-clean"
      tx = Master::Fix::Transaction.new(root: dir, paths: ["note.txt"], id:).begin!

      File.write(path, "delivered")
      checkpoint = tx.checkpoint!(["note.txt"])
      assert checkpoint.ok?
      versioned_store = tx.instance_variable_get(:@snapshots).fetch("note.txt").store
      assert_match(/\.[0-9a-f]{16}\z/, versioned_store)
      assert_equal "delivered", File.read(versioned_store)

      tx.send(:release_lock)
      tx.instance_variable_set(:@active, false)

      recovery = Master::Fix::Transaction::Recovery.recover!(root: dir, id:)

      assert recovery.ok?, -> { recovery.message.to_s }
      assert_equal "delivered", File.read(path)
      refute Master::Fix::Transaction::Recovery.persisted?(root: dir, id:)
    end
  end

  def test_recovery_refuses_an_unobserved_edit_after_versioned_checkpoint
    Dir.mktmpdir do |dir|
      path = File.join(dir, "note.txt")
      File.write(path, "before")
      id = "checkpoint-recovery"
      tx = Master::Fix::Transaction.new(root: dir, paths: ["note.txt"], id:).begin!

      File.write(path, "delivered")
      checkpoint = tx.checkpoint!(["note.txt"])
      assert checkpoint.ok?
      versioned_store = tx.instance_variable_get(:@snapshots).fetch("note.txt").store
      assert_match(/\.[0-9a-f]{16}\z/, versioned_store)

      tx.send(:release_lock)
      tx.instance_variable_set(:@active, false)
      File.write(path, "unobserved later edit")

      recovery = Master::Fix::Transaction::Recovery.recover!(root: dir, id:)

      refute recovery.ok?, "an edit after the checkpoint was not journaled and must not be overwritten"
      assert_equal :policy, recovery.category
      assert_equal "unobserved later edit", File.read(path)
      assert Master::Fix::Transaction::Recovery.persisted?(root: dir, id:)
    end
  end

  def test_checkpoint_uses_a_new_snapshot_generation_before_advancing_the_floor
    Dir.mktmpdir do |dir|
      path = File.join(dir, "note.txt")
      File.write(path, "before")
      tx = Master::Fix::Transaction.new(root: dir, paths: ["note.txt"], id: "checkpoint-generation").begin!
      original_store = tx.instance_variable_get(:@snapshots).fetch("note.txt").store

      File.write(path, "delivered")
      result = tx.checkpoint!(["note.txt"])

      assert result.ok?
      current_store = tx.instance_variable_get(:@snapshots).fetch("note.txt").store
      refute_equal original_store, current_store
      assert_equal "delivered", File.read(current_store)
      refute File.exist?(original_store), "the old snapshot may be deleted only after the new manifest is durable"

      File.write(path, "later")
      tx.observe!
      assert tx.rollback!.ok?
      assert_equal "delivered", File.read(path)
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
  def test_transaction_telemetry_redacts_paths_and_free_form_diagnostics
    Dir.mktmpdir do |dir|
      private_path = "private/customer-name.txt"
      FileUtils.mkdir_p(File.join(dir, "private"))
      File.write(File.join(dir, private_path), "private bytes")
      events = []
      bus = Object.new
      bus.define_singleton_method(:publish) { |event, **payload| events << [event, payload] }
      tx = Master::Fix::Transaction.new(
        root: dir, paths: [private_path], id: "privacy-audit", bus:
      ).begin!

      tx.send(
        :emit, "fix:transaction_diagnostic",
        error: "permission denied for #{private_path}",
        detail: "customer-specific repair context"
      )

      serialized = events.inspect
      refute_includes serialized, private_path
      refute_includes serialized, "customer-name"
      refute_includes serialized, "permission denied"
      refute_includes serialized, "customer-specific repair context"

      start = events.find { |event, _| event == "fix:transaction_start" }.last
      assert_equal 1, start[:paths_count]
      assert_equal Digest::SHA256.hexdigest(private_path), start[:paths_digest]
      diagnostic = events.find { |event, _| event == "fix:transaction_diagnostic" }.last
      assert_equal Digest::SHA256.hexdigest("permission denied for #{private_path}"), diagnostic[:error_digest]
      assert_equal "customer-specific repair context".bytesize, diagnostic[:detail_bytes]
      assert_equal 1, diagnostic[:schema_version]

      assert tx.rollback!.ok?
    end
  end


end
