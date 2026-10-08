# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

class TestMobileOnboarding < Minitest::Test
  def test_android_starts_personal_owner_onboarding
    Dir.mktmpdir("android-onboarding") do |root|
      onboarding = Master::Device::Onboarding.new(android: true, root:)
      onboarding_root = root
      result = { subject: "subject123", onboarding: "owner0: tell me your name" }

      Master::Device::Agent.stub(:owner_subject, "") do
        Master::Device::Agent.stub(
          :claim_owner!,
          ->(root:, label:) do
            raise "root mismatch" unless root == onboarding_root
            raise "label mismatch" unless label == "Alex"
            result
          end,
        ) do
          output = onboarding.mobile_start!(platform: :android, label: "Alex")
          assert_includes output, "Android onboarding started"
          assert_includes output, "tell me your name"
        end
      end
    end
  end

  def test_android_requires_an_android_host
    onboarding = Master::Device::Onboarding.new(android: false, root: Dir.tmpdir)
    error = assert_raises(ArgumentError) { onboarding.mobile_start!(platform: :android) }
    assert_match(/Android\/Termux/, error.message)
  end

  def test_ios_starts_pwa_onboarding_without_claiming_native_device
    Dir.mktmpdir("ios-onboarding") do |root|
      Fiber[:master_pair_subject] = nil
      onboarding = Master::Device::Onboarding.new(android: false, root:)
      output = onboarding.mobile_start!(platform: :ios)

      assert_includes output, "iOS/PWA onboarding started"
      assert_includes output, "name"
      assert_includes output, "language"
    ensure
      Fiber[:master_pair_subject] = nil
    end
  end
end
