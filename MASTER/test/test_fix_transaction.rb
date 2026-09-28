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
end
