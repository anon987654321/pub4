# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "tmpdir"
require "json"
require "yaml"
# Under a C locale -- which is how the weekly integrity run invokes these on
# vm23 -- Ruby defaults file reads to US-ASCII. Same require, same reason, as
# MASTER/gates/runner.rb.
require_relative "../lib/utf8"

# Behaviour, not spelling. These run health_check.rb the way the laptop and the
# installed uptime wrapper do -- --public-only, which needs no vm23 tool -- with
# CURL pointed at a stub, so the verdict is the script's and not a grep of it.
class HealthCheckBehaviourTest < Minitest::Test
  OPENBSD = File.expand_path("..", __dir__)
  SCRIPT = File.join(OPENBSD, "gates", "health_check.rb")
  APPS = YAML.safe_load_file(File.join(OPENBSD, "..", "RAILS", "apps.yml")).fetch("apps")
  FACE = JSON.parse(File.read(File.join(OPENBSD, "deploy_inventory.json"))).fetch("master_face")

  def stub_curl(dir, body)
    path = File.join(dir, "curl")
    File.write(path, "#!/bin/sh\n#{body}\n")
    File.chmod(0o755, path)
    path
  end

  def run_public_only(curl, *extra)
    Open3.capture3({ "CURL" => curl, "HEALTH_CHECK_TIMEOUT" => "2" },
                   RbConfig.ruby, SCRIPT, "--public-only", "--all-ready-apps", *extra)
  end

  def test_every_endpoint_answering_is_a_pass_that_says_it_checked_nothing_on_the_box
    Dir.mktmpdir do |dir|
      out, err, status = run_public_only(stub_curl(dir, "exit 0"))
      assert status.success?, "expected a pass, got: #{err}"
      assert_includes out, "public-only (#{APPS.size} app(s); nothing on vm23 was checked)"
    end
  end

  def test_an_endpoint_that_refuses_fails_and_names_every_public_host
    Dir.mktmpdir do |dir|
      _, err, status = run_public_only(stub_curl(dir, "echo 'curl: (7) Failed to connect' >&2; exit 7"))
      refute status.success?
      APPS.each_value { |meta| assert_includes err, "#{meta.fetch('domain')} https" }
      assert_includes err, "#{FACE.fetch('domain')} https", "master's public name must come from deploy_inventory.json"
    end
  end

  def test_json_success_lists_the_apps_it_checked
    Dir.mktmpdir do |dir|
      out, _, status = run_public_only(stub_curl(dir, "exit 0"), "--json")
      assert status.success?
      assert_equal APPS.keys.sort, JSON.parse(out).fetch("apps_checked")
    end
  end

  def test_documented_flags_are_accepted
    out, _, status = Open3.capture3(RbConfig.ruby, SCRIPT, "--help")
    assert status.success?
    %w[--core --all-ready-apps --public --public-only --json].each { |flag| assert_includes out, flag }
  end
end
