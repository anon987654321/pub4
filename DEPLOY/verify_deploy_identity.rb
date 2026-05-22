#!/usr/bin/env ruby
# frozen_string_literal: true
# frozen_string_literal: true

# Verifies low-level DEPLOY identity hygiene without requiring app dependencies.
# Run from the repository root:
#   ruby DEPLOY/verify_deploy_identity.rb

require "yaml"

ROOT = File.expand_path("..", __dir__)
RAILS_ROOT = File.join(ROOT, "DEPLOY", "rails")
APPS_FILE = File.join(RAILS_ROOT, "apps.yml")
metadata = YAML.load_file(APPS_FILE).fetch("apps")

failures = []
ports = Hash.new { |h, k| h[k] = [] }
domains = Hash.new { |h, k| h[k] = [] }

metadata.each do |app, expected|
  script = File.join(ROOT, expected.fetch("deploy_script"))
  app_path = File.join(ROOT, expected.fetch("app_path"))
  readme = File.join(RAILS_ROOT, app, "README.md")
  gemfile = File.join(app_path, "Gemfile")
  routes = File.join(app_path, "config", "routes.rb")

  ports[expected.fetch("port")] << app
  domains[expected.fetch("domain")] << app

  failures << "missing app directory for #{app}: #{app_path}" unless Dir.exist?(app_path)
  failures << "missing README for #{app}: #{readme}" unless File.file?(readme)
  failures << "missing Gemfile for #{app}: #{gemfile}" unless File.file?(gemfile)
  failures << "missing routes for #{app}: #{routes}" unless File.file?(routes)

  unless File.file?(script)
    failures << "missing deploy script for #{app}: #{script}"
    next
  end

  content = File.read(script)
  checks = {
    "set -euo pipefail" => "missing strict mode for #{app}",
    "APP_NAME=#{app}" => "wrong APP_NAME for #{app}",
    "APP_DOMAIN=#{expected.fetch("domain")}" => "wrong APP_DOMAIN for #{app}",
    "APP_PORT=#{expected.fetch("port")}" => "wrong APP_PORT for #{app}",
    "SCRIPT_DIR=${0:a:h}" => "missing zsh script dir resolution for #{app}",
    "SRC_DIR=${SCRIPT_DIR}/app" => "missing source dir for #{app}",
    "SHARED_BUNDLE_CACHE" => "missing shared bundle cache for #{app}",
    'doas mkdir -p "${APP_DIR}/.bundle"' => "missing app .bundle mkdir for #{app}",
    "bundle config set --local deployment true" => "missing modern bundler deployment config for #{app}",
    "bundle config set --local without 'development test'" => "missing modern bundler without config for #{app}",
    "install_rcd \"$APP_NAME\" \"$APP_DIR\" \"$APP_PORT\" \"$APP_NAME\"" => "missing standard rc.d install call for #{app}",
    "relayd_add_relay \"$APP_DOMAIN\" \"$APP_PORT\"" => "missing standard relay call for #{app}"
  }

  checks.each do |needle, message|
    failures << message unless content.include?(needle)
  end

  failures << "template placeholder left in #{app}" if content.include?("%APP_NAME%") || content.include?("%")
  failures << "deprecated bundler flags left in #{app}" if content.include?("bundle install --deployment --without")
  failures << "hard-coded amber bundle coupling left in #{app}" if content.include?("/home/amber/.bundle/gems") && app != "amber"
  failures << "unquoted cp source in #{app}" if content.include?("cp -R ${SRC_DIR}")

  if File.file?(readme)
    readme_content = File.read(readme)
    failures << "README missing deploy script path for #{app}" unless readme_content.include?(expected.fetch("deploy_script")) || readme_content.include?("#{app}.sh")
  end

  if File.file?(gemfile) && File.file?(readme)
    gemfile_content = File.read(gemfile)
    readme_content = File.read(readme)
    if gemfile_content.include?('gem "sqlite3"') && readme_content.match?(/Rails 8, PostgreSQL(,|\.)/)
      failures << "README claims PostgreSQL as current stack while Gemfile uses SQLite for #{app}"
    end
  end

  if File.file?(routes)
    routes_content = File.read(routes)
    failures << "missing health route for #{app}" unless routes_content.include?("rails/health#show")
  end
end

ports.each do |port, apps|
  failures << "port collision #{port}: #{apps.join(', ')}" if apps.size > 1
end

domains.each do |domain, apps|
  failures << "domain collision #{domain}: #{apps.join(', ')}" if apps.size > 1
end

if failures.empty?
  puts "DEPLOY identity verification passed for #{metadata.keys.join(', ')}"
else
  warn "DEPLOY identity verification failed:"
  failures.each { |failure| warn "- #{failure}" }
  exit 1
end
