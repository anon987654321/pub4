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
    assert_equal 1, ci.scan("FULL_COVERAGE=1").size
    assert_includes ci, "FULL_COVERAGE=1 DEFAULT_TEST="
    assert_includes ci, "FULL_COVERAGE=1 bin/rails test:system"
  end

  def test_full_coverage_runner_exists_and_collates_every_app
    runner = File.join(ROOT, "bin", "coverage")
    assert File.file?(runner), "RAILS/bin/coverage is missing"

    source = File.read(runner)
    APPS.each { |app| assert_includes source, "apps" }
    assert_includes source, "SimpleCov.collate"
    assert_includes source, "minimum 100"
    assert_includes source, "minimum_per_file 100"
  end

  def test_coverage_policy_tracks_runtime_dimensions
    source = File.read(File.join(ROOT, "__shared/test/coverage.rb"))
    assert_includes source, "enable_coverage :branch"
    assert_includes source, "enable_coverage :method"
    assert_includes source, "enable_coverage :eval"
    assert_includes source, "track_tests"
  end
end
