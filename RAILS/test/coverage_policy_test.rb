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

  def test_ci_requests_full_line_branch_and_method_coverage
    ci = File.read(File.join(ROOT, "__shared/config/ci.rb"))
    assert_includes ci, "FULL_COVERAGE=1"
    assert_includes ci, "FULL_COVERAGE=1 bin/rails test:system"
  end

  def test_coverage_policy_tracks_ruby_source_and_rendered_views
    source = File.read(File.join(ROOT, "__shared/test/coverage.rb"))
    assert_includes source, 'cover "app/**/*.rb"'
    assert_includes source, 'cover "engines/**/app/**/*.rb"'
    assert_includes source, 'cover "lib/**/*.rb"'
    assert_includes source, 'cover_views "app/views/**/*.erb"'
    assert_includes source, 'enable_coverage :branch'
    assert_includes source, 'enable_coverage :method'
    assert_includes source, 'enable_coverage :eval'
    assert_includes source, "track_tests"
  end

  def test_full_mode_pins_every_supported_criterion_to_one_hundred_percent
    source = File.read(File.join(ROOT, "__shared/test/coverage.rb"))
    %w[line branch method].each do |criterion|
      assert_includes source, "coverage :#{criterion}, minimum: 100, minimum_per_file: 100"
    end
  end
end
