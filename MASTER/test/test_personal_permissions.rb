# frozen_string_literal: true

require_relative "test_helper"
require "master"
require_relative "../lib/ground/personal_permissions"
require_relative "../lib/ground/personal_calendar"

class TestPersonalPermissions < Minitest::Test
  def setup
    @root = Dir.mktmpdir("master_personal_permissions")
    @now = Time.utc(2026, 10, 19, 1)
    @permissions = Master::Ground::PersonalPermissions.new(root: @root, clock: -> { @now })
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_every_scope_is_denied_by_default
    %w[microphone speech_recognition camera location contacts messages notifications
       personal_memory calendar_read financial_data financial_actions tradedoubler.claims.read
       tradedoubler.claims.prepare tradedoubler.claims.submit external_messages purchases
       deployment destructive_actions].each do |scope|
      refute @permissions.allowed?(scope:), "#{scope} must default to deny"
    end
  end

  def test_unknown_scope_and_missing_confirmation_are_rejected
    assert_raises(ArgumentError) { @permissions.allowed?(scope: "everything") }
    assert_raises(ArgumentError) do
      @permissions.grant(scope: "microphone", confirmed_by: "", purpose: "voice chat")
    end
  end

  def test_grant_is_scoped_to_declared_purpose_and_can_expire
    @permissions.grant(scope: "microphone", confirmed_by: "device owner", purpose: "voice chat",
                       expires_at: @now + 60)
    assert @permissions.allowed?(scope: "microphone", purpose: "voice chat")
    refute @permissions.allowed?(scope: "microphone", purpose: "background recording")
    @now += 61
    refute @permissions.allowed?(scope: "microphone")
    refute @permissions.status.fetch("grants").fetch("microphone").fetch("active")
  end

  def test_revocation_is_immediate_and_auditable
    @permissions.grant(scope: "messages", confirmed_by: "owner", purpose: "summarize selected messages")
    assert @permissions.revoke(scope: "messages", confirmed_by: "owner", reason: "changed my mind")
    refute @permissions.allowed?(scope: "messages")
    refute @permissions.revoke(scope: "messages", confirmed_by: "owner")
    events = @permissions.status.fetch("events")
    assert_equal %w[grant revoke], events.map { |event| event.fetch("action") }
    assert_equal "changed my mind", events.last.fetch("detail")
  end

  def test_ledger_is_local_and_owner_only
    @permissions.grant(scope: "personal_memory", subject: "subject-a", confirmed_by: "owner", purpose: "remember chosen preferences")
    path = File.join(@root, ".master", "permissions", "personal.json")
    assert File.file?(path)
    assert_equal 0o600, File.stat(path).mode & 0o777
    assert_equal 0o700, File.stat(File.dirname(path)).mode & 0o777
  end

  def test_personal_memory_grants_do_not_cross_subjects
    @permissions.grant(
      scope: "personal_memory", subject: "subject-a", confirmed_by: "owner",
      purpose: "read and write personal profile and memory"
    )

    assert @permissions.allowed?(scope: "personal_memory", subject: "subject-a",
                                 purpose: "read and write personal profile and memory")
    refute @permissions.allowed?(scope: "personal_memory", subject: "subject-b",
                                 purpose: "read and write personal profile and memory")
    refute @permissions.allowed?(scope: "personal_memory",
                                 purpose: "read and write personal profile and memory")

    assert @permissions.revoke(scope: "personal_memory", subject: "subject-a",
                               confirmed_by: "owner", reason: "changed my mind")
    refute @permissions.allowed?(scope: "personal_memory", subject: "subject-a")
  end

  def test_calendar_read_grants_are_bound_to_subject_and_purpose
    purpose = Master::Ground::PersonalCalendar::READ_PERMISSION_PURPOSE
    @permissions.grant(
      scope: "calendar_read", subject: "subject-a", confirmed_by: "owner",
      purpose:
    )

    assert @permissions.allowed?(scope: "calendar_read", subject: "subject-a", purpose:)
    refute @permissions.allowed?(scope: "calendar_read", subject: "subject-b", purpose:)
    refute @permissions.allowed?(scope: "calendar_read", purpose:)
    refute @permissions.allowed?(scope: "calendar_read", subject: "subject-a", purpose: "send calendar data")
  end

  def test_state_is_persistent_and_inspectable
    @permissions.grant(scope: "financial_data", confirmed_by: "owner", purpose: "read monthly budget")
    snapshot = Master::Ground::PersonalPermissions.new(root: @root, clock: -> { @now }).status
    assert_equal "deny", snapshot.fetch("default")
    assert snapshot.fetch("grants").fetch("financial_data").fetch("active")
    assert_equal "read monthly budget", snapshot.fetch("grants").fetch("financial_data").fetch("purpose")
  end
end
