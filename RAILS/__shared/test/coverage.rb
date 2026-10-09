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

# The monorepo keeps the app at RAILS/<app>; the deploy copy-tree keeps it at
# /home/<app>/app beside __shared, so the directory is "app" while the name
# stays the app. Without this the copy-tree run died "unknown Rails app".
app_dir = [app, "app"].find do |dir|
  File.file?(File.join(rails_root, dir, "config", "application.rb"))
end
raise "coverage: unknown Rails app #{app.inspect}" unless app_dir

SimpleCov.root(rails_root)
SimpleCov.coverage_path(
  ENV["PUB4_COVERAGE_PATH"].to_s.strip.empty? ?
    File.join(rails_root, "coverage", app) :
    File.expand_path(ENV.fetch("PUB4_COVERAGE_PATH"))
)
SimpleCov.command_name "#{app}:rails"

SimpleCov.start "rails" do
  cover "#{app_dir}/app/**/*.rb"
  cover "#{app_dir}/engines/**/app/**/*.rb"
  cover "#{app_dir}/lib/**/*.rb"
  cover "__shared/app/**/*.rb"
  cover "__shared/lib/**/*.rb"

  cover_views "#{app_dir}/app/views/**/*.erb"
  cover_views "#{app_dir}/engines/**/app/views/**/*.erb"
  cover_views "__shared/app/views/**/*.erb"

  group "Application", "#{app_dir}/app"
  group "Libraries", "#{app_dir}/lib"
  group "Engines", "#{app_dir}/engines"
  group "Shared", ["__shared/app", "__shared/lib"]

  enable_coverage :branch
  enable_coverage :method
  enable_coverage :eval

  coverage :branch, ignore: :eval_generated
  coverage :method, ignore: :eval_generated
  track_tests

  # Each app run must fully cover its own executable surface. Shared code is
  # included in every report but is judged only after all application reports
  # are collated, because a shared branch can legitimately be exercised by a
  # different consumer than the current app.
  own_source = %r{\A#{Regexp.escape(app_dir)}/(?:app|engines|lib)/}
  %i[line branch method].each do |criterion|
    coverage criterion do
      minimum 100, per: own_source
    end
  end
end
