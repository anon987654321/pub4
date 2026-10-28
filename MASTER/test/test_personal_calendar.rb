# frozen_string_literal: true

require_relative "test_helper"
require "master"
require_relative "../lib/ground/personal_calendar"

class TestPersonalCalendar < Minitest::Test
  def setup
    @root = Dir.mktmpdir("master-personal-calendar")
    @subject = "calendar-owner"
    @calendar = Master::Ground::PersonalCalendar.new(root: @root)
    @permissions = Master::Ground::PersonalPermissions.new(root: @root)
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def grant_calendar
    @permissions.grant(
      scope: "calendar_read", subject: @subject, confirmed_by: "local owner",
      purpose: Master::Ground::PersonalCalendar::READ_PERMISSION_PURPOSE
    )
  end

  def source(content)
    path = File.join(@root, "calendar.ics")
    File.write(path, content)
    path
  end

  def calendar_text
    <<~ICS
      BEGIN:VCALENDAR
      VERSION:2.0
      BEGIN:VEVENT
      UID:one
      DTSTART;TZID=Europe/Oslo:20261021T103000
      SUMMARY:Coffee\\, and chat
      LOCATION:Bryggen
      END:VEVENT
      BEGIN:VEVENT
      UID:two
      DTSTART;VALUE=DATE:20261022
      SUMMARY:All day
      END:VEVENT
      BEGIN:VEVENT
      UID:three
      DTSTART;TZID=Europe/Oslo:20261021T120000
      SUMMARY:Weekly review
      RRULE:FREQ=WEEKLY;BYDAY=WE
      END:VEVENT
      END:VCALENDAR
    ICS
  end

  def test_import_and_read_only_date_listing
    grant_calendar
    imported = @calendar.import!(subject: @subject, source: source(calendar_text))
    assert_equal 3, imported.fetch(:event_count)
    assert_equal 1, imported.fetch(:recurring_series)
    state = @calendar.status(subject: @subject)
    assert state.fetch(:imported)
    assert_equal 0o600, File.stat(state.fetch(:path)).mode & 0o777

    agenda = @calendar.events_for(subject: @subject, date: Date.iso8601("2026-10-21"))
    assert_equal ["Coffee, and chat", "Weekly review"], agenda.fetch(:events).map(&:summary)
    assert_equal 1, agenda.fetch(:recurring_series)
    assert agenda.fetch(:events).last.recurring
    assert_equal "Bryggen", agenda.fetch(:events).first.location
  end

  def test_calendar_read_permission_is_required_and_subject_bound
    assert_raises(Master::Ground::PersonalWorkspace::PermissionDenied) do
      @calendar.import!(subject: @subject, source: source(calendar_text))
    end

    grant_calendar
    assert_raises(Master::Ground::PersonalWorkspace::PermissionDenied) do
      @calendar.events_for(subject: "another-person", date: "2026-10-21")
    end
  end

  def test_invalid_or_non_ics_import_is_rejected
    grant_calendar
    txt = File.join(@root, "calendar.txt")
    File.write(txt, calendar_text)
    assert_raises(ArgumentError) { @calendar.import!(subject: @subject, source: txt) }
    assert_raises(ArgumentError) { @calendar.import!(subject: @subject, source: source("not a calendar")) }
  end

  def test_missing_calendar_is_an_explicit_error
    grant_calendar
    assert_raises(ArgumentError) { @calendar.events_for(subject: @subject, date: "2026-10-21") }
  end
end
