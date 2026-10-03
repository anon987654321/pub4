# frozen_string_literal: true

require "minitest/autorun"
require "master"

class FixPatchTest < Minitest::Test
  class Transaction
    attr_reader :id, :rollback_count

    def initialize(id:, rollback_result:)
      @id = id
      @rollback_result = rollback_result
      @rollback_count = 0
    end

    def active? = true

    def rollback!
      @rollback_count += 1
      @rollback_result
    end
  end

  def test_installed_patch_carries_proof
    tx = Transaction.new(id: "patch1", rollback_result: Master::Result.err("unexpected"))
    proof = Master::Result.ok(:verified)

    result = Master::Fix::Patch.new(
      transaction: tx,
      apply: -> { :changed },
      verify: ->(value) { proof if value == :changed },
    ).run

    assert_equal :installed, result.state
    assert_equal :changed, result.value
    assert result.proof.ok?
    assert_equal 0, tx.rollback_count
  end

  def test_failed_proof_rolls_back
    tx = Transaction.new(id: "patch2", rollback_result: Master::Result.err("rolled back"))

    result = Master::Fix::Patch.new(
      transaction: tx,
      apply: -> { :changed },
      verify: ->(_) { false },
    ).run

    assert_equal :reverted, result.state
    assert_equal 1, tx.rollback_count
    refute result.proof.ok?
  end
end
