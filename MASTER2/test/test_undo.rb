# frozen_string_literal: true

require_relative "test_helper"

class TestUndo < Minitest::Test
  def setup
    MASTER::Undo.clear
  end

  def test_push_adds_to_stack
    MASTER::Undo.push(:test, { foo: "bar" })
    assert MASTER::Undo.can_undo?
  end

  def test_empty_stack_cannot_undo
    refute MASTER::Undo.can_undo?
  end

  def test_undo_returns_operation
    MASTER::Undo.push(:test, { foo: "bar" })
    op = MASTER::Undo.undo
    assert_equal :test, op.type
    assert_equal({ foo: "bar" }, op.data)
  end

  def test_undo_moves_to_redo
    MASTER::Undo.push(:test, {})
    MASTER::Undo.undo
    assert MASTER::Undo.can_redo?
  end

  def test_clear_empties_stacks
    MASTER::Undo.push(:test, {})
    MASTER::Undo.clear
    refute MASTER::Undo.can_undo?
    refute MASTER::Undo.can_redo?
  end

  def test_history_returns_descriptions
    MASTER::Undo.track_edit("/path/to/file.rb", "content")
    history = MASTER::Undo.history
    assert_equal 1, history.size
    assert_match /Edit/, history.first
  end
end
