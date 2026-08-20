# frozen_string_literal: true

require "test_helper"

# A block that only works in one direction is a block that leaks in the other.
class FediBlockTest < ActiveSupport::TestCase
  setup { Rails.cache.clear }
  teardown { Rails.cache.clear }

  test "a domain is matched however it is written" do
    FediBlock.create!(domain: "  Spam.Example  ")

    assert FediBlock.blocked?("spam.example")
    assert FediBlock.blocked?("SPAM.EXAMPLE")
    assert FediBlock.blocked?("www.spam.example")
    assert_not FediBlock.blocked?("example.com")
  end

  # Blocking an instance blocks the instance, not one hostname of it.
  test "subdomains of a blocked instance are blocked" do
    FediBlock.create!(domain: "spam.example")

    assert FediBlock.blocked?("relay.spam.example")
    assert_not FediBlock.blocked?("notspam.example")
  end

  test "a uri is read for its host, and rubbish is not a block" do
    FediBlock.create!(domain: "spam.example")

    assert FediBlock.blocked_uri?("https://spam.example/users/kari")
    assert_not FediBlock.blocked_uri?("https://elsewhere.example/users/kari")
    assert_not FediBlock.blocked_uri?("not a uri at all")
  end

  # The cache is what keeps this out of every inbox POST; it has to notice a new
  # block, or the list is a list of what was blocked when the process started.
  test "the cached list refreshes when a block is added" do
    assert_not FediBlock.blocked?("late.example")

    FediBlock.create!(domain: "late.example")
    assert FediBlock.blocked?("late.example")
  end

  test "a hostname is required, not a url" do
    assert_not FediBlock.new(domain: "https://spam.example/users").valid?
  end
end
