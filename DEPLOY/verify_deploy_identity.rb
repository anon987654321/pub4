#!/usr/bin/env ruby
# frozen_string_literal: true

# Verifies low-level DEPLOY identity hygiene without requiring app dependencies.
# Run from the repository root:
#   ruby DEPLOY/verify_deploy_identity.rb

ROOT = File.expand_path("..", __dir__)
RAILS_ROOT = File.join(ROOT, "DEPLOY", "rails")
EXPECTED_RAILS_APPS = {
  "amber" => { domain: "amber.brgen.no", port: 61_352 },
  "baibl" => { domain: "baibl.no", port: 10_007 },
  "blognet" => { domain: "blognet.no", port: 10_002 },
  "brgen" => { domain: "brgen.no", port: 38_182 },
  "bsdports" => { domain: "bsdports.org", port: 47_312 },
  "hjerterom" => { domain: "hjerterom.no", port: 38_891 }
}.freeze

failures = []

EXPECTED_RAILS_APPS.each do |app, expected|
  script = File.join(RAILS_ROOT, app, "#{app}.sh")
  unless File.file?(script)
    failures << "missing deploy script: #{script}"
    next
  end

  content = File.read(script)
  checks = {
    "APP_NAME=#{app}" => "wrong APP_NAME for #{app}",
    "APP_DOMAIN=#{expected[:domain]}" => "wrong APP_DOMAIN for #{app}",
    "APP_PORT=#{expected[:port]}" => "wrong APP_PORT for #{app}",
    "SHARED_BUNDLE_CACHE" => "missing shared bundle cache for #{app}",
    "doas mkdir -p \"${APP_DIR}/.bundle\"" => "missing app .bundle mkdir for #{app}",
    "bundle config set --local deployment true" => "missing modern bundler deployment config for #{app}",
    "bundle config set --local without 'development test'" => "missing modern bundler without config for #{app}"
  }

  checks.each do |needle, message|
    failures << message unless content.include?(needle)
  end

  failures << "template placeholder left in #{app}" if content.include?("%APP_NAME%")
  failures << "deprecated bundler flags left in #{app}" if content.include?("bundle install --deployment --without")
  failures << "hard-coded amber bundle coupling left in #{app}" if content.include?("/home/amber/.bundle/gems") && app != "amber"
end

if failures.empty?
  puts "DEPLOY identity verification passed for #{EXPECTED_RAILS_APPS.keys.join(', ')}"
else
  warn "DEPLOY identity verification failed:"
  failures.each { |failure| warn "- #{failure}" }
  exit 1
end
