# frozen_string_literal: true

require "minitest/autorun"
require "yaml"

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
      assert_includes source, 'cover "#{app_dir}/app/**/*.rb"',
                      "#{app}: coverage scope must resolve to RAILS/#{app}/app, not RAILS/app"
    end
  end

  def test_coverage_policy_includes_app_engines_and_shared_code
    source = File.read(File.join(ROOT, "__shared/test/coverage.rb"))
    assert_includes source, 'cover "#{app_dir}/engines/**/app/**/*.rb"'
    assert_includes source, 'cover "__shared/app/**/*.rb"'
    assert_includes source, 'cover "__shared/lib/**/*.rb"'
    assert_includes source, 'cover_views "#{app_dir}/app/views/**/*.erb"'
    assert_includes source, 'cover_views "#{app_dir}/engines/**/app/views/**/*.erb"'
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
    runner = File.join(ROOT, "..", "MASTER", "tools", "rails", "coverage.rb")
    assert File.file?(runner), "MASTER/tools/rails/coverage.rb is missing"

    source = File.read(runner)
    assert_includes source, 'APPS_FILE = File.join(ROOT, "apps.yml")'
    assert_includes source, 'YAML.safe_load_file(APPS_FILE).fetch("apps")'
    assert_includes source, "SimpleCov.collate"
    assert_includes source, "minimum 100"
    assert_includes source, 'PUB4_COVERAGE_PATH'
  end

  def test_premerge_cannot_omit_the_full_coverage_group_by_default
    source = File.read(File.join(ROOT, "..", "MASTER", "tools", "rails", "premerge.rb"))

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
    source = File.read(File.join(ROOT, "..", "MASTER", "tools", "rails", "coverage.rb"))
    assert_includes source, 'VERIFYING = ENV["MASTER_FIX_VERIFY"] == "1"'
    assert_includes source, 'Dir.mktmpdir("pub4-coverage-")'
    assert_includes source, 'ENV.fetch("PUB4_COVERAGE_ROOT", File.join(rails_root, "coverage"))'
    assert_includes source, 'FileUtils.rm_rf(COVERAGE_ROOT) if VERIFYING'
  end

  # The enforced number is a recorded floor per app. Without an entry the gate would
  # raise at load for that app, and a floor outside 1..100 would pass nothing or
  # everything.
  def test_every_app_has_a_recorded_coverage_floor_for_each_criterion
    floors = YAML.safe_load_file(File.join(ROOT, "__shared/test/coverage_floors.yml"))

    APPS.each do |app|
      %w[line branch method].each do |criterion|
        value = floors.dig(app, criterion)
        assert_kind_of Numeric, value, "#{app}: no #{criterion} floor in coverage_floors.yml"
        assert_operator value, :>, 0, "#{app}: #{criterion} floor must be above zero"
        assert_operator value, :<=, 100, "#{app}: #{criterion} floor is a percentage"
      end
    end
  end

  # One-file runs cannot reach a whole-app number, so the minimum applies to full
  # runs only; strict mode keeps the 100%-per-file target reachable on request.
  def test_the_minimum_applies_to_full_runs_and_strict_mode_keeps_the_old_target
    source = File.read(File.join(ROOT, "__shared/test/coverage.rb"))
    assert_includes source, 'ENV["PUB4_COVERAGE_STRICT"] == "1"'
    assert_includes source, 'ENV["FULL_COVERAGE"] == "1" || ENV["PUB4_CI_GUARD"] == "1"'
    assert_includes source, "minimum 100, per: own_source"
  end

end
