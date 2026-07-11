# frozen_string_literal: true

require "minitest/autorun"

class FleetHealthContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  ACTIVE_APPS = %w[amber brgen bsdports].freeze
  ARCHIVED_APPS = %w[hjerterom privcam pub_attorney mytoonz].freeze
  ALL_APPS = (ACTIVE_APPS + ARCHIVED_APPS).freeze

  def test_active_apps_expose_health_route
    ACTIVE_APPS.each do |app|
      routes = File.read(File.join(ROOT, app, "config", "routes.rb"))
      assert_match(/fleet\.rb/, routes, "#{app} must load shared fleet routes")
    end
    fleet_routes = File.read(File.join(ROOT, "shared", "config", "routes", "fleet.rb"))
    assert_match(/get ["']health["']/, fleet_routes)
  end

  def test_archived_apps_keep_health_route_for_redeploy
    ARCHIVED_APPS.each do |app|
      routes = File.read(File.join(ROOT, app, "config", "routes.rb"))
      assert_match(/fleet\.rb/, routes, "#{app} must load shared fleet routes")
    end
  end

  def test_shared_security_initializers_present
    %w[security_headers.rb content_security_policy.rb].each do |name|
      path = File.join(ROOT, "shared", "config", "initializers", name)
      assert File.file?(path), "missing #{name}"
      refute_includes File.read(path), "# Rails.application.configure do\n#", "#{name} should be active"
    end
  end

  def test_master_json_mirrors_apps_yml
    require "yaml"
    require "json"
    master = JSON.parse(File.read(File.expand_path("../../OPERATOR/master.json", __dir__)))
    apps_yml = YAML.safe_load(File.read(File.join(ROOT, "apps.yml"))).fetch("apps")
    expected = apps_yml.map { |name, meta| [name, meta["domain"], meta["port"]] }.sort
    actual = master.fetch("apps").map { |row| [row["name"], row["domain"], row["port"]] }.sort
    assert_equal expected, actual
  end

  def test_production_baseline_excludes_health_from_host_auth
    baseline = File.read(File.join(ROOT, "shared", "config", "environments", "production_baseline.rb"))
    assert_match(%r{/health}, baseline)
    assert_match(/force_ssl = false/, baseline)
  end
end