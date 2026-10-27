# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "yaml"

# Four places name the fleet: RAILS/apps.yml (the truth), deploy_inventory.json,
# the DNS zones and relayd's routes. The first is edited; the rest are generated or
# gated. This fails the day one of them is edited by hand instead.
class TestInventoriesAgree < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def run_tool(*argv)
    out, status = Open3.capture2e(RbConfig.ruby, *argv, chdir: ROOT)
    [out, status.exitstatus]
  end

  def test_deploy_inventory_is_what_apps_yml_generates
    out, status = run_tool("OPENBSD/bin/sync_deploy_inventory.rb", "--check")

    assert_equal 0, status, out
  end

  def test_dns_zones_are_what_the_policy_renders
    out, status = run_tool("OPENBSD/bin/render_dns.rb", "--check")

    assert_equal 0, status, out
  end

  def test_every_apps_yml_domain_has_a_relayd_keypair
    apps = YAML.safe_load_file(File.join(ROOT, "RAILS", "apps.yml")).fetch("apps")
    relayd = File.read(File.join(ROOT, "OPENBSD", "etc", "relayd.conf"), encoding: "UTF-8")
    keypairs = relayd.scan(/tls keypair "([^"]+)"/).flatten

    missing = apps.values.map { |meta| meta.fetch("domain") }.reject { |domain| keypairs.include?(domain) }

    assert_empty missing, "apps.yml domains with no relayd tls keypair: #{missing.join(', ')}"
  end
end
