# frozen_string_literal: true

require "minitest/autorun"
# Every read below inspects UTF-8 source. Under a C locale -- which is how the
# weekly integrity run invokes these on vm23 -- Ruby defaults file reads to
# US-ASCII and each one raises "invalid byte sequence". Same require, same
# reason, as RAILS/gates/runner.rb.
require_relative "../lib/utf8"

class HealthCheckStructureTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SCRIPT = File.join(ROOT, "health_check.rb")

  def source
    @source ||= File.read(SCRIPT)
  end

  def test_script_exists
    assert File.file?(SCRIPT), "missing health_check.rb"
  end

  def test_defines_core_helper_methods
    %w[run privileged load_apps load_standalone_apps service_running? curl_ok?].each do |method|
      assert_match(/def #{Regexp.escape(method)}/, source, "expected helper #{method}")
    end
  end

  def test_supports_documented_cli_flags
    %w[--core --all-ready-apps --public --json].each do |flag|
      assert_includes source, flag
    end
  end

  def test_checks_loopback_up_and_health_paths
    assert_includes source, "/up"
    assert_includes source, "/health"
    assert_includes source, "127.0.0.1"
  end

  def test_public_mode_checks_https_endpoints
    assert_includes source, "options[:public]"
    assert_includes source, "https://"
  end
end
