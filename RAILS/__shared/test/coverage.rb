# frozen_string_literal: true

# One coverage policy for every Rails app. Keep this tiny: the test helper must
# load it before Rails application code so unloaded files are not mistaken for
# tested files.
require "simplecov"

app_root = File.expand_path("../..", __dir__)
SimpleCov.root(app_root)
SimpleCov.coverage_path(File.join(app_root, "coverage"))
SimpleCov.command_name "#{ENV["PUB4_CI_APP"].to_s.empty? ? File.basename(Dir.pwd) : ENV["PUB4_CI_APP"]}:rails"

SimpleCov.start "rails" do
  cover "app/**/*.rb"
  cover "engines/**/app/**/*.rb"
  cover "lib/**/*.rb"
  cover_views "app/views/**/*.erb"
  cover_views "engines/**/app/views/**/*.erb"

  enable_coverage :branch
  enable_coverage :method
  enable_coverage :eval

  coverage :branch, ignore: :eval_generated
  coverage :method, ignore: :eval_generated
  track_tests

  if ENV["FULL_COVERAGE"] == "1"
    coverage :line, minimum: 100, minimum_per_file: 100
    coverage :branch, minimum: 100, minimum_per_file: 100
    coverage :method, minimum: 100, minimum_per_file: 100
  else
    coverage :line, minimum: 0
    coverage :branch, minimum: 0
    coverage :method, minimum: 0
  end
end
