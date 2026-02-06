# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/pledge"

class TestPledge < Minitest::Test
  def test_available_returns_true_on_openbsd
    skip "Not running on OpenBSD" unless RUBY_PLATFORM.include?("openbsd")
    assert MASTER::Pledge.available?
  end

  def test_available_returns_false_on_non_openbsd
    skip "Running on OpenBSD" if RUBY_PLATFORM.include?("openbsd")
    refute MASTER::Pledge.available?
  end

  def test_pledge_raises_on_non_openbsd
    skip "Running on OpenBSD" if RUBY_PLATFORM.include?("openbsd")
    assert_raises(MASTER::Pledge::PledgeError) do
      MASTER::Pledge.pledge("stdio")
    end
  end

  def test_unveil_raises_on_non_openbsd
    skip "Running on OpenBSD" if RUBY_PLATFORM.include?("openbsd")
    assert_raises(MASTER::Pledge::PledgeError) do
      MASTER::Pledge.unveil("/tmp", "r")
    end
  end

  def test_lock_unveil_raises_on_non_openbsd
    skip "Running on OpenBSD" if RUBY_PLATFORM.include?("openbsd")
    assert_raises(MASTER::Pledge::PledgeError) do
      MASTER::Pledge.lock_unveil
    end
  end
end
