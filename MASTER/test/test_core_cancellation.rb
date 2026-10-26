# frozen_string_literal: true

require_relative "test_helper"

class TestCoreCancellation < Minitest::Test
  class NeverProposes
    def propose(_context, verbs:, scope:) = raise("a cancelled Fold must not ask the model for an effect")
  end

  class CancellingModel
    def initialize(token, path)
      @token = token
      @path = path
    end

    def propose(_context, verbs:, scope:)
      raise "Fold did not supply the closed verb set" unless verbs.include?(:write)

      @token.cancel!(reason: "operator stopped after proposal")
      Master::Core::Effect.write(@path, "must not be written")
    end
  end

  def constitution
    Master::Core::Constitution.load(data_dir: File.expand_path("../data", __dir__))
  end

  def build_fold(model:, root:, token:)
    Master::Core::Fold.new(
      model:, constitution: constitution, world: Master::Core::World.new(root:),
      memory: Master::Core::Memory.new, max_turns: 3, cancellation: token
    )
  end

  def test_cancelled_before_first_turn_does_not_call_the_model
    Dir.mktmpdir do |root|
      token = Master::Core::CancellationToken.new.cancel!(reason: "operator stop")
      result = build_fold(model: NeverProposes.new, root:, token:).run("stop")

      assert_equal :cancelled, result.reason
      assert_equal 0, result.turns
      assert_equal "cancelled: operator stop", result.summary
    end
  end

  def test_cancellation_after_a_model_proposal_prevents_the_effect
    Dir.mktmpdir do |root|
      token = Master::Core::CancellationToken.new
      result = build_fold(
        model: CancellingModel.new(token, "must-not-exist.txt"), root:, token:
      ).run("write then cancel")

      assert_equal :cancelled, result.reason
      assert_equal 1, result.turns
      refute File.exist?(File.join(root, "must-not-exist.txt"))
    end
  end

  def test_cancellation_is_sticky_and_keeps_the_first_reason
    token = Master::Core::CancellationToken.new
    token.cancel!(reason: "first")
    token.cancel!(reason: "second")

    assert_predicate token, :cancelled?
    assert_equal "first", token.reason
    assert_raises(ArgumentError) { token.cancel!(reason: "  ") }
  end
end
