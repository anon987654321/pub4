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

  def test_read_only_modes_fetch_the_web_but_never_write_or_execute
    %i[observe plan].each do |profile|
      capabilities = Master::Core::Capabilities.for(profile)

      assert capabilities.allows?(:network), "#{profile} cannot fetch a page"
      refute capabilities.allows?(:write), "#{profile} can write"
      refute capabilities.allows?(:execute), "#{profile} can execute"
    end
  end
end
