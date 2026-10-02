# frozen_string_literal: true

require "minitest/autorun"
require "master"

class PledgeProfileTest < Minitest::Test
  def test_profiles_have_declared_capabilities
    expected = {
      boot: %i[stdio read execute],
      model: %i[stdio read model],
      fix: %i[stdio read write create execute],
      device: %i[stdio read device],
      world: %i[stdio read world],
    }

    expected.each do |name, capabilities|
      profile = Master::Ground::Pledge.profile(name)
      assert_equal capabilities, profile.capabilities
      refute_empty profile.promises
    end
  end

  def test_profile_constructor_normalizes_values
    profile = Master::Ground::Pledge::Profile.new(
      name: "fix",
      capabilities: ["stdio", "write"],
      promises: +"stdio rpath"
    )

    assert_equal :fix, profile.name
    assert_equal %i[stdio write], profile.capabilities
    assert_equal "stdio rpath", profile.promises
    assert profile.capabilities.frozen?
    assert profile.promises.frozen?
  end

  def test_unknown_profile_is_rejected
    assert_raises(KeyError) { Master::Ground::Pledge.profile(:unknown) }
  end
end
