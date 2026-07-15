#!/usr/bin/env ruby
# frozen_string_literal: true

# apps.yml Validator
# Run standalone or via gates/runner.rb (future integration)
# Checks:
# - YAML parses and has 'apps' top-level hash
# - Every declared app has a corresponding RAILS/<name>/ directory
# - deploy_script file exists
# - Ports are unique integers
# - Domains are unique
# - Feature entries have valid status (done | planned)

require "yaml"

ROOT = File.expand_path("../..", __FILE__)
APPS_YML = File.join(ROOT, "apps.yml")

def fail!(msg)
  @failures << msg
end

def validate
  @failures = []
  @warnings = []

  unless File.file?(APPS_YML)
    fail!("Missing apps.yml at #{APPS_YML}")
    return report
  end

  data = YAML.safe_load(File.read(APPS_YML), permitted_classes: [Symbol])
  apps = data.fetch("apps", nil)

  unless apps.is_a?(Hash)
    fail!("'apps' key must be a Hash")
    return report
  end

  ports = []
  domains = []

  apps.each do |name, meta|
    name = name.to_s
    app_dir = File.join(ROOT, name)
    fail!("#{name}: declared in apps.yml but no directory #{app_dir}") unless File.directory?(app_dir)

    deploy_script = meta["deploy_script"]
    if deploy_script
      full_deploy = File.join(ROOT, "..", deploy_script) # relative to repo root usually
      full_deploy2 = File.join(ROOT, deploy_script)
      unless File.file?(full_deploy) || File.file?(full_deploy2)
        fail!("#{name}: deploy_script '#{deploy_script}' does not exist")
      end
    else
      @warnings << "#{name}: no deploy_script declared"
    end

    port = meta["port"]
    if port
      unless port.is_a?(Integer)
        fail!("#{name}: port must be integer, got #{port.class}")
      else
        ports << port
      end
    else
      @warnings << "#{name}: no port declared"
    end

    domain = meta["domain"]
    if domain
      domains << domain
    else
      @warnings << "#{name}: no domain declared"
    end

    features = meta["features"] || {}
    features.each_value do |section|
      next unless section.is_a?(Array)
      section.each do |feat|
        next unless feat.is_a?(Hash)
        status = feat["status"]
        unless %w[done planned].include?(status.to_s)
          fail!("#{name}: feature '#{feat['name']}' has invalid status '#{status}' (expected done|planned)")
        end
      end
    end
  end

  # Uniqueness
  ports.tally.each do |p, count|
    fail!("Duplicate port #{p} used by #{count} apps") if count > 1
  end
  domains.tally.each do |d, count|
    fail!("Duplicate domain #{d} used by #{count} apps") if count > 1
  end

  report
end

def report
  if @warnings.any?
    warn "apps.yml validator warnings:"
    @warnings.each { |w| warn "  - #{w}" }
  end

  if @failures.any?
    warn "apps.yml validator FAILURES:"
    @failures.each { |f| warn "  - #{f}" }
    exit 1
  end

  puts "apps.yml validator: OK (#{@failures.size} failures, #{@warnings.size} warnings)"
  exit 0
end

if __FILE__ == $0
  validate
end
