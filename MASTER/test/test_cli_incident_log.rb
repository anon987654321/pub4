# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "json"

class TestCliIncidentLog < Minitest::Test
  def log = Master::CLI::IncidentLog

  def at(day, hour) = Time.new(2026, 10, day, hour, 0, 0)

  def with_file
    Dir.mktmpdir { |dir| yield File.join(dir, "log.ndjson") }
  end

  def test_an_entry_is_kept_with_its_time_and_the_file_is_private
    with_file do |file|
      log.add("said something quietly as I left; later denied it", now: Time.new(2026, 10, 20, 21, 5, 0),
                 file:)

      assert_equal 1, log.entries(file:).size
      assert_equal "0600", format("%04o", File.stat(file).mode & 0o777)
      assert_includes log.list(file:), "2026-10-20 21:05  said something quietly"
    end
  end

  def test_incident_log_rotation_is_bounded_and_remains_private
    with_file do |file|
      8.times do |index|
        log.add("incident #{index}: " + "x" * 80, file:, max_bytes: 500)
      end

      assert File.file?("#{file}.1")
      assert_operator File.size(file), :<=, 500
      assert_operator File.size("#{file}.1"), :<=, 500
      assert_equal 0o600, File.stat(file).mode & 0o777
      File.readlines(file, chomp: true).each { |line| JSON.parse(line) }
    end
  end

  def test_an_empty_note_is_not_kept
    with_file do |file|
      assert_nil log.add("   ", file:)
      assert_empty log.entries(file:)
    end
  end

  def test_the_summary_counts_by_week_weekday_part_of_day_and_denial
    with_file do |file|
      log.add("quiet remark in the hall, she denied it", now: at(19, 21), file:)
      log.add("another remark at breakfast", now: at(20, 8), file:)
      summary = log.summary(file:)

      assert_includes summary, "2 entries"
      assert_includes summary, "evening 1"
      assert_includes summary, "morning 1"
      assert_includes summary, "mention a denial: 1 of 2"
      assert_includes summary, "say nothing about her"
    end
  end

  def test_an_empty_log_says_how_to_start
    with_file { |file| assert_includes log.summary(file:), "/incident add" }
  end

  def test_nothing_in_the_log_listens_or_leaves_the_machine
    lines = File.readlines(File.join(Master::ROOT, "lib", "cli", "incident_log.rb"))
    code = lines.reject { |line| line.strip.start_with?("#") }.join

    refute_match(/Net::HTTP|TCPSocket|Face::Ear|Device::Audio/, code)
  end
end
