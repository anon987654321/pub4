# frozen_string_literal: true

require "minitest/autorun"

class DeploySmokeContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  OPENBSD_ROOT = File.expand_path("../../OPENBSD", __dir__)
  APPS = %w[amber brgen bsdports].freeze
  RAILS_APPS = APPS
  SMOKE = File.join(OPENBSD_ROOT, "bin", "deploy-smoke.sh")

  def test_deploy_smoke_script_exists_and_covers_apps
    assert File.file?(SMOKE), "missing OPENBSD/bin/deploy-smoke.sh"
    body = File.read(SMOKE)
    assert_includes body, "ALLOW_AMBER_DOWN"
    assert_includes body, "http://127.0.0.1:38182/up"
    assert_includes body, "http://127.0.0.1:61352/up"
    assert_includes body, "http://127.0.0.1:53187/up"
    assert_includes body, "https://brgen.no/up"
    assert_includes body, "https://amber.brgen.no/up"
    assert_includes body, "https://ai.brgen.no/up"
    assert_includes body, "https://bsdports.org/up"
    assert_includes body, "brgen_html_smoke"
    assert_includes body, "rcctl"
  end

  def test_deploy_smoke_gate_static_contract
    gate = File.join(OPENBSD_ROOT, "deploy_smoke_gate.rb")
    assert File.file?(gate)
    body = File.read(gate)
    assert_includes body, "relayd.conf"
    assert_includes body, 'check http "/up"'
    assert_includes body, "assume_ssl"
  end

  def test_debt_yml_points_at_deploy_smoke
    debt = File.read(File.join(OPENBSD_ROOT, "data", "debt.yml"))
    assert_includes debt, "deploy-smoke.sh"
    assert_includes debt, "multi_app_ram"
  end

  def test_all_deployed_apps_expose_rails_health_up_route
    APPS.each do |app|
      routes = read(File.join(ROOT, app, "config/routes.rb"))
      assert_match(%r{get\s+["']up["']}, routes, "#{app} missing /up health route")
      assert_includes routes, "rails/health#show", "#{app} should use rails health controller"
    end
  end

  def test_all_deployed_apps_have_rc_d_scripts_in_repo
    APPS.each do |app|
      script = File.join(OPENBSD_ROOT, "etc/rc.d", app)
      assert File.file?(script), "missing #{script}"
      body = File.read(script)
      assert_match(/daemon_execdir=/, body, "#{app} rc.d should set daemon_execdir")
      assert_match(/rc_cmd/, body, "#{app} rc.d should invoke rc_cmd")
    end
  end

  def test_master_rc_precompile_guard_present
    master = File.read(File.join(OPENBSD_ROOT, "etc/rc.d/master"))
    assert_includes master, "public/assets/assets"
    assert_includes master, "assets:precompile"
    assert_includes master, "chat/message?message=ping"
    refute_match(/chat\/metrics.*"model"/, master)
  end

  def test_rails_runtime_gate_precompiles_assets
    shared = read(File.join(ROOT, "_assets.sh"))
    assert_includes shared, "rails_assets_precompile_as_app"
    assert_includes shared, "assets:precompile"
  end

  def test_production_baseline_serves_precompiled_assets
    baseline = read(File.join(ROOT, "shared/config/environments/production_baseline.rb"))
    assert_includes baseline, "config.public_file_server.enabled = true"
    assert_includes baseline, "config.public_file_server.headers"
  end

  def test_brgen_solid_cache_schema_present
    cache = read(File.join(ROOT, "brgen/db/cache_schema.rb"))
    assert_includes cache, "solid_cache_entries"
    refute_includes cache, "define(version: 0)"
  end

  def test_brgen_face_assets_under_javascripts
    assert File.file?(File.join(ROOT, "brgen/app/assets/javascripts/particle_kernel.js"))
    assert File.file?(File.join(ROOT, "brgen/app/assets/javascripts/face.js"))
  end

  def test_stimulus_controllers_do_not_use_method_trailing_commas
    RAILS_APPS.each do |app|
      Dir.glob(File.join(ROOT, app, "app/javascript/controllers/**/*_controller.js")).each do |controller|
        body = read(controller)
        refute_match(/^\s{2}},\s*$/m, body, "#{controller} has a trailing comma after a class method")
        body.lines.grep(/StimulusReflex\.register|textContent|addEventListener|removeEventListener|style\.height/).each do |line|
          refute_match(/,\s*$/, line, "#{controller} has a trailing comma after a statement")
        end
      end
    end
  end

  private

  def read(path)
    File.read(path, encoding: "UTF-8")
  rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
    File.read(path).force_encoding("UTF-8").scrub
  rescue Errno::ENOENT
    flunk "missing file: #{path}"
  end
end
