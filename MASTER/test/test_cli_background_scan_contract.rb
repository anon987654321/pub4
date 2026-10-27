# frozen_string_literal: true

require_relative "test_helper"
require "cli/session"

class TestCliBackgroundScanContract < Minitest::Test
  def test_plain_session_keeps_repository_scanning_off
    with_env(
      "MASTER_BACKGROUND_SCAN" => nil,
      "MASTER_SKIP_BOOT_SCAN" => nil,
      "MASTER_PIPE" => nil,
    ) do
      session = Master::CLI::Session.allocate
      refute session.send(:background_scan_enabled?)
    end
  end

  def test_background_scanning_can_be_turned_off
    with_env(
      "MASTER_BACKGROUND_SCAN" => "0",
      "MASTER_SKIP_BOOT_SCAN" => nil,
      "MASTER_PIPE" => nil,
    ) do
      session = Master::CLI::Session.allocate
      refute session.send(:background_scan_enabled?)
    end
  end

  def test_background_scanning_requires_explicit_opt_in
    with_env(
      "MASTER_BACKGROUND_SCAN" => "1",
      "MASTER_SKIP_BOOT_SCAN" => nil,
      "MASTER_PIPE" => nil,
    ) do
      session = Master::CLI::Session.allocate
      assert session.send(:background_scan_enabled?)
    end
  end

  def test_skip_boot_scan_overrides_the_default
    with_env(
      "MASTER_BACKGROUND_SCAN" => "1",
      "MASTER_SKIP_BOOT_SCAN" => "1",
      "MASTER_PIPE" => nil,
    ) do
      session = Master::CLI::Session.allocate

      refute session.send(:background_scan_enabled?)
    end
  end

  def test_public_entrypoint_defaults_boot_scanning_off_but_allows_explicit_opt_in
    source = File.read(File.expand_path("../bin/master", __dir__))

    assert_includes source, 'ENV["MASTER_BACKGROUND_SCAN"] ||= "0"'
    assert_includes source, 'ENV["MASTER_SKIP_BOOT_SCAN"] ||= (ENV["MASTER_BACKGROUND_SCAN"] == "1" ? "0" : "1")'
  end

  private

  def with_env(values)
    previous = values.to_h { |key, _value| [key, ENV.key?(key) ? ENV.fetch(key) : nil] }
    present = values.keys.to_h { |key| [key, ENV.key?(key)] }
    values.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
    yield
  ensure
    previous.each do |key, value|
      present.fetch(key) ? ENV[key] = value : ENV.delete(key)
    end
  end
end
