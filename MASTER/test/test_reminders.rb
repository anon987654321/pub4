# frozen_string_literal: true

require "test_helper"
require "ground/reminder_time"
require "ground/assistant_tasks"
require "cli/session"

class TestReminderTime < Minitest::Test
  Time_ = Master::Ground::ReminderTime
  OSLO = "Europe/Oslo"
  # 2026-10-26 20:00 in Oslo (UTC+1 after the clocks went back on the 25th).
  NOW = Time.utc(2026, 10, 26, 19, 0)

  def test_tomorrow_at_nine_is_nine_on_the_owners_clock
    assert_equal Time.utc(2026, 10, 27, 8, 0), Time_.resolve("tomorrow at 9", zone: OSLO, now: NOW)
    assert_equal Time.utc(2026, 10, 27, 8, 0), Time_.resolve("i morgen kl 9", zone: OSLO, now: NOW)
    assert_equal Time.utc(2026, 10, 27, 8, 0), Time_.resolve("9am tomorrow", zone: OSLO, now: NOW)
  end

  def test_a_bare_time_already_past_today_means_tomorrow
    assert_equal Time.utc(2026, 10, 27, 6, 30), Time_.resolve("7:30", zone: OSLO, now: NOW)
    assert_equal Time.utc(2026, 10, 26, 21, 15), Time_.resolve("at 22:15", zone: OSLO, now: NOW)
  end

  def test_a_delay_counts_from_now
    assert_equal NOW + 1200, Time_.resolve("in 20 minutes", zone: OSLO, now: NOW)
    assert_equal NOW + 7200, Time_.resolve("om 2 timer", zone: OSLO, now: NOW)
  end

  def test_iso_passes_through_and_nonsense_is_nil
    assert_equal Time.utc(2026, 11, 1, 9, 0), Time_.resolve("2026-11-01T10:00:00+01:00", zone: OSLO, now: NOW)
    assert_nil Time_.resolve("sometime soon", zone: OSLO, now: NOW)
    assert_nil Time_.resolve("at 25:00", zone: OSLO, now: NOW)
  end

  def test_the_process_timezone_is_restored
    before = ENV.fetch("TZ", nil)
    Time_.resolve("tomorrow at 9", zone: "Asia/Tokyo", now: NOW)

    assert_equal before, ENV.fetch("TZ", nil)
  end
end

class TestReminderDelivery < Minitest::Test
  def with_tasks(now)
    Dir.mktmpdir do |root|
      clock = -> { now.call }
      yield Master::Ground::AssistantTasks.new(root:, subject: "local-uid-test", clock:)
    end
  end

  def test_a_due_task_is_said_to_ring_only_in_an_open_session_and_rings_once
    now = Time.utc(2026, 10, 26, 19, 0)
    with_tasks(-> { now }) do |tasks|
      task = tasks.call(action: "create", title: "Call the plumber", due_at: "in 20 minutes")
      assert_match(/open interactive MASTER session/, task.fetch("delivery"))
      assert_empty tasks.due_reminders

      now += 1300
      assert_equal ["Call the plumber"], tasks.due_reminders.map { |row| row["title"] }

      tasks.call(action: "reminded", id: task.fetch("id"))
      assert_empty tasks.due_reminders, "a reminder rings once"
    end
  end

  def test_moving_the_due_time_rearms_the_reminder
    now = Time.utc(2026, 10, 26, 19, 0)
    with_tasks(-> { now }) do |tasks|
      id = tasks.call(action: "create", title: "Stretch", due_at: "in 1 minute").fetch("id")
      now += 120
      tasks.call(action: "reminded", id:)
      tasks.call(action: "update", id:, due_at: "in 1 minute")
      now += 120

      assert_equal [id], tasks.due_reminders.map { |row| row["id"] }
    end
  end

  def test_a_task_without_a_due_time_makes_no_delivery_claim
    with_tasks(-> { Time.utc(2026, 10, 26) }) do |tasks|
      refute tasks.call(action: "create", title: "Someday").key?("delivery")
    end
  end
end

class TestSessionRingsReminders < Minitest::Test
  Refs = Struct.new(:root, :bus)

  class Tasks
    attr_reader :marked

    def initialize = @marked = []
    def due_reminders = [{ "id" => "a1", "title" => "Call the plumber" }]
    def call(action:, id:) = @marked << [action, id]
  end

  def test_a_due_reminder_is_printed_spoken_published_and_marked
    session = Master::CLI::Session.allocate
    events = []
    bus = Object.new
    bus.define_singleton_method(:publish) { |event, **payload| events << [event, payload] }
    session.instance_variable_set(:@refs, Refs.new(Dir.tmpdir, bus))
    tasks = Tasks.new
    spoken = []

    out, = capture_io do
      Master::Voice::Playback.stub(:speak, ->(text) { spoken << text }) do
        session.send(:ring_due_reminders, tasks:)
      end
    end

    assert_includes out, "remind0: Call the plumber"
    assert_equal ["Reminder: Call the plumber"], spoken
    assert_equal [["reminder:due", { task_id: "a1" }]], events
    assert_equal [%w[reminded a1]], tasks.marked
  end
end
