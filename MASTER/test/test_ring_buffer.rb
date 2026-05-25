# frozen_string_literal: true

require_relative "test_helper"

class TestRingBuffer < Minitest::Test
  def test_push_and_to_a
    buf = Master::Trace::RingBuffer.new(3)
    buf.push("a").push("b").push("c")
    assert_equal %w[a b c], buf.to_a
  end

  def test_wraps_around
    buf = Master::Trace::RingBuffer.new(3)
    %w[a b c d].each { |x| buf.push(x) }
    assert_equal %w[b c d], buf.to_a
  end

  def test_each_without_block_returns_enumerator
    buf = Master::Trace::RingBuffer.new(3)
    buf.push("x")
    assert_instance_of Enumerator, buf.each
  end

  def test_to_a_without_block
    buf = Master::Trace::RingBuffer.new(3)
    buf.push("x").push("y")
    assert_equal %w[x y], buf.to_a  # must not raise LocalJumpError
  end

  def test_size_and_empty
    buf = Master::Trace::RingBuffer.new(4)
    assert buf.empty?
    buf.push("a")
    assert_equal 1, buf.size
    refute buf.empty?
  end
end
