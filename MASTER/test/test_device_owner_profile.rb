# frozen_string_literal: true

require_relative "../test_helper"
require "tmpdir"

class TestDeviceOwnerProfile < Minitest::Test
  Profile = Master::Device::OwnerProfile

  def test_set_reads_back_only_declared_profile_fields
    Dir.mktmpdir("owner-profile") do |root|
      subject = "abc123"
      Profile.set(root:, subject:, name: "Alex", language: "English", timezone: "Europe/Oslo",
                  ignored: "secret", interests: "music, code")

      values = Profile.values(root:, subject:)
      assert_equal "Alex", values["name"]
      assert_equal "English", values["language"]
      assert_equal "Europe/Oslo", values["timezone"]
      assert_equal "music, code", values["interests"]
      refute values.key?("ignored")
    end
  end

  def test_forget_removes_one_field_without_touching_the_others
    Dir.mktmpdir("owner-profile") do |root|
      subject = "abc123"
      Profile.set(root:, subject:, name: "Alex", language: "English")
      Profile.forget(root:, subject:, key: "language")

      values = Profile.values(root:, subject:)
      assert_equal "Alex", values["name"]
      refute values.key?("language")
    end
  end

  def test_onboarding_prompt_reports_missing_fields
    Dir.mktmpdir("owner-profile") do |root|
      prompt = Profile.onboarding_prompt(root:, subject: "abc123")
      assert_match(/Name/, prompt)
      assert_match(/Language/, prompt)
    end
  end

  def test_onboarding_prompt_closes_after_all_fields_are_set
    Dir.mktmpdir("owner-profile") do |root|
      fields = Profile::KEYS.to_h { |key| [key.to_sym, "x"] }
      Profile.set(root:, subject: "abc123", **fields)

      assert_equal "owner0: profile complete", Profile.onboarding_prompt(root:, subject: "abc123")
    end
  end
end
