# frozen_string_literal: true

require "minitest/autorun"
require "master"

class CapabilityLawTest < Minitest::Test
  def test_capability_reduction_is_implemented_and_monotonic
    capabilities = Master::Core::Capabilities.for(:fix)

    capabilities.drop(:network)
    assert_raises(SecurityError) { capabilities.acquire(:network) }
    assert_raises(SecurityError) { capabilities.require!(:network) }

    capabilities.lock!
    assert_raises(SecurityError) { capabilities.drop(:read) }
  end
end
