# frozen_string_literal: true

require "minitest/autorun"

class CoveragePolicyTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  APPS = %w[amber brgen bsdports].freeze

  def test_every_rails_app_starts_coverage_before_application_boot
    APPS.each do |app|
      source = File.read(File.join(ROOT, app, "test/test_helper.rb"))
      coverage = source.index('require_relative "../../__shared/test/coverage"')
      boot = source.index('require_relative "../config/environment"')
      refute_nil coverage, "#{app}: test helper does not load the coverage policy"
      refute_nil boot, "#{app}: test helper no longer boots Rails"
      assert_operator coverage, :<, boot, "#{app}: coverage starts after Rails boot"
    end
  end

  def test_every_app_coverage_scope_points_at_the_real_app_tree
    source = File.read(File.join(ROOT, "__shared/test/coverage.rb"))

    APPS.each do |app|
      assert_includes source, 'cover "#{app}/app/**/*.rb"',
                      "#{app}: coverage scope must resolve to RAILS/#{app}/app, not RAILS/app"
    end
  end

  def test_coverage_policy_includes_app_engines_and_shared_code
    source = File.read(File.join(ROOT, "__shared/test/coverage.rb"))
    assert_includes source, 'cover "#{app}/engines/**/app/**/*.rb"'
    assert_includes source, 'cover "__shared/app/**/*.rb"'
    assert_includes source, 'cover "__shared/lib/**/*.rb"'
    assert_includes source, 'cover_views "#{app}/app/views/**/*.erb"'
    assert_includes source, 'cover_views "#{app}/engines/**/app/views/**/*.erb"'
    assert_includes source, 'cover_views "__shared/app/views/**/*.erb"'
  end

  def test_coverage_policy_has_explicit_application_groups
    source = File.read(File.join(ROOT, "__shared/test/coverage.rb"))
    %w[Application Libraries Engines Shared].each do |group|
      assert_includes source, %Q[group "#{group}"],
                      "missing SimpleCov group #{group.inspect}"
    end
  end

  def test_ci_requests_full_coverage
    ci = File.read(File.join(ROOT, "__shared/config/ci.rb"))
    assert_operator ci.scan("FULL_COVERAGE=1").size, :>=, 2
    assert_includes ci, "FULL_COVERAGE=1 DEFAULT_TEST="
    assert_includes ci, "FULL_COVERAGE=1 bin/rails test:system"
  end

  def test_full_coverage_runner_exists_and_collates_the_apps_inventory
    runner = File.join(ROOT, "bin", "coverage")
    assert File.file?(runner), "RAILS/bin/coverage is missing"

    source = File.read(runner)
    assert_includes source, 'APPS_FILE = File.join(ROOT, "apps.yml")'
    assert_includes source, 'YAML.safe_load_file(APPS_FILE).fetch("apps")'
    assert_includes source, "SimpleCov.collate"
    assert_includes source, "minimum 100"
    assert_includes source, 'PUB4_COVERAGE_PATH'
  end

  def test_premerge_cannot_omit_the_full_coverage_group_by_default
    source = File.read(File.join(ROOT, "bin", "premerge"))

    assert_includes source, 'group: :coverage'
    assert_includes source, 'else %i[apps pwa contracts coverage gates]'
    assert_includes source, 'elsif ARGV.include?("--coverage") then [:coverage]'
    assert_includes source, 'elsif ARGV.include?("--gates") then [:gates]'
  end

  def test_all_rails_apps_pin_the_same_simplecov_major_minor_line
    APPS.each do |app|
      gemfile = File.read(File.join(ROOT, app, "Gemfile"))
      lockfile = File.read(File.join(ROOT, app, "Gemfile.lock"))

      assert_includes gemfile, 'gem "simplecov", "~> 1.2", require: false'
      assert_includes lockfile, "simplecov (1.2.0)"
      assert_includes lockfile, "simplecov (~> 1.2)"
    end
  end

  def test_coverage_policy_tracks_runtime_dimensions
    source = File.read(File.join(ROOT, "__shared/test/coverage.rb"))
    assert_includes source, "enable_coverage :branch"
    assert_includes source, "enable_coverage :method"
    assert_includes source, "enable_coverage :eval"
    assert_includes source, "track_tests"
  end
  def test_fix_verification_coverage_uses_a_disposable_root
    source = File.read(File.join(ROOT, "bin", "coverage"))
    assert_includes source, 'VERIFYING = ENV["MASTER_FIX_VERIFY"] == "1"'
    assert_includes source, 'Dir.mktmpdir("pub4-coverage-")'
    assert_includes source, 'ENV.fetch("PUB4_COVERAGE_ROOT", File.join(rails_root, "coverage"))'
    assert_includes source, 'FileUtils.rm_rf(COVERAGE_ROOT) if VERIFYING'
  end

end
