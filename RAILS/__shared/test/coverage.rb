# frozen_string_literal: true

# One coverage policy for every Rails app. SimpleCov's root is the RAILS tree so
# app, engine and shared paths can be collated without inventing another loader.
# The per-app CI run enforces its own application/engine files; the collated run
# enforces the shared layer after all three applications have contributed.
require "simplecov"

rails_root = File.expand_path("../..", __dir__)
app = ENV["PUB4_CI_APP"].to_s.strip
app = File.basename(Dir.pwd) if app.empty?
app = File.basename(File.expand_path("..")) if app == "app"

raise "coverage: unknown Rails app #{app.inspect}" unless File.directory?(File.join(rails_root, app))

SimpleCov.root(rails_root)
SimpleCov.coverage_path(
  ENV["PUB4_COVERAGE_PATH"].to_s.strip.empty? ?
    File.join(rails_root, "coverage", app) :
    File.expand_path(ENV.fetch("PUB4_COVERAGE_PATH"))
)
SimpleCov.command_name "#{app}:rails"

SimpleCov.start "rails" do
  cover "#{app}/app/**/*.rb"
  cover "#{app}/engines/**/app/**/*.rb"
  cover "#{app}/lib/**/*.rb"
  cover "__shared/app/**/*.rb"
  cover "__shared/lib/**/*.rb"

  cover_views "#{app}/app/views/**/*.erb"
  cover_views "#{app}/engines/**/app/views/**/*.erb"
  cover_views "__shared/app/views/**/*.erb"

  group "Application", "#{app}/app"
  group "Libraries", "#{app}/lib"
  group "Engines", "#{app}/engines"
  group "Shared", ["__shared/app", "__shared/lib"]

  enable_coverage :branch
  enable_coverage :method
  enable_coverage :eval

  coverage :branch, ignore: :eval_generated
  coverage :method, ignore: :eval_generated
  track_tests

  # Individual app CI must fully cover its own executable surface. Shared code
  # is included in every report but is judged only after the three application
  # runs are collated, because shared branches legitimately divide by consumer.
  %i[line branch method].each do |criterion|
    coverage criterion do
      minimum 0
      minimum 100, per: group("Application")
      minimum 100, per: group("Libraries")
      minimum 100, per: group("Engines")
    end
  end
end
