# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

class TestDeviceOwnerProfile < Minitest::Test
  Profile = Master::Device::OwnerProfile
  SUBJECT = "abc123"

  # The profile is personal memory, so it is written only after its owner grants that scope.
  def with_granted_root
    Dir.mktmpdir("owner-profile") do |root|
      purpose = Master::Ground::PersonalWorkspace::MEMORY_PERMISSION_PURPOSE
      permissions = Master::Ground::PersonalPermissions.new(root:)
      permissions.grant(scope: "personal_memory", subject: SUBJECT, confirmed_by: "local owner", purpose:)

      yield root
    end
  end

  def test_nothing_is_written_before_personal_memory_is_granted
    denied = Master::Ground::PersonalWorkspace::PermissionDenied

    Dir.mktmpdir("owner-profile") do |root|
      assert_raises(denied) { Profile.set(root:, subject: SUBJECT, name: "Alex") }
      assert_empty Profile.values(root:, subject: SUBJECT)
      assert_includes Profile.onboarding_prompt(root:, subject: SUBJECT), "/privacy grant personal_memory"
    end
  end

  def test_set_reads_back_only_declared_profile_fields
    with_granted_root do |root|
      Profile.set(root:, subject: SUBJECT, name: "Alex", language: "English", timezone: "Europe/Oslo",
                  ignored: "secret", interests: "music, code")

      values = Profile.values(root:, subject: SUBJECT)
      assert_equal "Alex", values["name"]
      assert_equal "English", values["language"]
      assert_equal "Europe/Oslo", values["timezone"]
      assert_equal "music, code", values["interests"]
      refute values.key?("ignored")
    end
  end

  def test_forget_removes_one_field_without_touching_the_others
    with_granted_root do |root|
      Profile.set(root:, subject: SUBJECT, name: "Alex", language: "English")
      Profile.forget(root:, subject: SUBJECT, key: "language")

      values = Profile.values(root:, subject: SUBJECT)
      assert_equal "Alex", values["name"]
      refute values.key?("language")
    end
  end

  def test_pet_name_customizes_the_wake_greeting
    with_granted_root do |root|
      Profile.set(root:, subject: SUBJECT, pet_name: "Mochi")

      assert_includes Profile.wake_greeting(root:, subject: SUBJECT), "Mochi"
    end
  end

  def test_onboarding_prompt_reports_missing_fields
    with_granted_root do |root|
      prompt = Profile.onboarding_prompt(root:, subject: SUBJECT)
      assert_match(/Name/, prompt)
      assert_match(/Language/, prompt)
    end
  end

  def test_onboarding_prompt_closes_after_all_fields_are_set
    with_granted_root do |root|
      Profile.set(root:, subject: SUBJECT, **Profile::KEYS.to_h { |key| [key.to_sym, "x"] })

      assert_equal "owner0: profile complete", Profile.onboarding_prompt(root:, subject: SUBJECT)
    end
  end
end
