# frozen_string_literal: true

require "minitest/autorun"

class DeploySmokeContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  OPENBSD_ROOT = File.expand_path("../../OPENBSD", __dir__)
  APPS = %w[amber brgen bsdports].freeze
  RAILS_APPS = APPS
  SMOKE = File.join(OPENBSD_ROOT, "bin", "deploy-smoke.sh")

  # Every app's local port and public URL, and the rcctl service name. bsdports had
  # neither local check when this list was only strings.
  ENDPOINTS = {
    "master" => ["http://127.0.0.1:53187/up", "https://ai.brgen.no/up"],
    "brgen" => ["http://127.0.0.1:38182/up", "https://brgen.no/up"],
    "amber" => ["http://127.0.0.1:61352/up", "https://amber.brgen.no/up"],
    "bsdports" => ["http://127.0.0.1:47312/up", "https://bsdports.org/up"],
  }.freeze

  # An app may be waived only by its own named variable, so a waiver is visible in
  # the command that waives it.
  WAIVERS = { "amber" => "ALLOW_AMBER_DOWN", "bsdports" => "ALLOW_BSDPORTS_DOWN" }.freeze

  def smoke_body
    @smoke_body ||= begin
      assert File.file?(SMOKE), "missing OPENBSD/bin/deploy-smoke.sh"
      File.read(SMOKE)
    end
  end

  # Comments stripped: this script explains its own required/optional history in
  # prose, and an assertion over the raw file reads the explanation as the check.
  def smoke_code
    @smoke_code ||= smoke_body.lines.reject { |line| line.strip.start_with?("#") }.join
  end

  def test_deploy_smoke_script_exists_and_covers_apps
    ENDPOINTS.each_value do |urls|
      urls.each { |url| assert_includes smoke_code, url }
    end
    assert_includes smoke_code, "brgen_html_smoke"
    assert_includes smoke_code, "rcctl"
  end

  # The bug this replaces an assert_includes for: `https://bsdports.org/up` was
  # present all along, passed to check_http with a literal 0 for `required`. The URL
  # being mentioned proved nothing about whether a dead app fails the smoke, which
  # is the only thing this script is for.
  def test_every_endpoint_is_required_or_waived_by_its_own_named_variable
    ENDPOINTS.each do |app, urls|
      urls.each do |url|
        call = smoke_code.lines.find { |line| line.include?(url) && line.include?("check_http") }
        refute_nil call, "#{url} is in the script but not passed to check_http"

        required = call.split(url, 2).last.delete('"').strip
        expected = WAIVERS.fetch(app, "1")
        expected = "$#{app}_req" unless expected == "1"

        assert_equal expected, required,
                     "#{app} #{url} must be required (1) or gated on #{WAIVERS[app] || "nothing"} — " \
                     "a hardcoded 0 is a check that cannot fail, which is how a dead app read as green"
      end
    end
  end

  def test_every_app_has_an_rcctl_check
    ENDPOINTS.each_key do |app|
      assert_match(/check_rcctl\s+#{app}\s/, smoke_code, "#{app} has no rcctl check")
    end
  end

  # A waiver variable that no longer gates anything is an exemption outliving its
  # subject (soul.yml EXEMPTIONS_EXPIRE), and it reads as a considered decision.
  def test_each_waiver_variable_is_read_and_gates_a_check
    WAIVERS.each do |app, variable|
      assert_includes smoke_code, variable, "#{variable} is documented but never read"
      assert_match(/#{app}_req=0/, smoke_code, "#{variable} does not actually waive #{app}")
      assert_includes smoke_code, "$#{app}_req", "#{app}_req is set but passed to no check"
    end
  end

  def test_deploy_smoke_gate_static_contract
    gate = File.join(OPENBSD_ROOT, "deploy_smoke_gate.rb")
    assert File.file?(gate)
    body = File.read(gate)
    assert_includes body, "relayd.conf"
    assert_includes body, 'check http "/up"'
    assert_includes body, "assume_ssl"
  end

  def test_backlog_points_at_deploy_smoke
    # The operator debt register was consolidated into the repo-root TODO.md.
    backlog = File.read(File.expand_path("../../TODO.md", __dir__))
    assert_includes backlog, "deploy-smoke.sh"
    assert_includes backlog, "multi_app_ram"
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
    assert_includes baseline, 'ENV["CDN_ASSET_HOST"]'
    assert_includes baseline, "config.asset_host"
    sample = read(File.join(ROOT, "env.sample"))
    assert_includes sample, "CDN_ASSET_HOST"
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
