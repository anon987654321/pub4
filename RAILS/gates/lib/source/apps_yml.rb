# frozen_string_literal: true

require "yaml"
require_relative "../../../../OPENBSD/lib/gate_result"

module Deploy
  class AppsYmlValidator
    ROOT = File.expand_path("../../..", __dir__)
    APPS_YML = File.join(ROOT, "apps.yml")
    VALID_STATUSES = %w[done planned].freeze

    def self.run
      new.run
    end

    def initialize
      @result = GateResult.new
    end

    def run
      unless File.file?(APPS_YML)
        @result.fail("Missing apps.yml at #{APPS_YML}")
        return @result
      end

      data = YAML.safe_load(File.read(APPS_YML), permitted_classes: [Symbol])
      apps = data.fetch("apps", nil)
      unless apps.is_a?(Hash)
        @result.fail("'apps' key must be a Hash")
        return @result
      end

      ports = []
      domains = []

      apps.each do |name, meta|
        validate_app(name.to_s, meta, ports:, domains:)
      end

      ports.tally.each { |port, count| @result.fail("Duplicate port #{port} used by #{count} apps") if count > 1 }
      domains.tally.each { |domain, count| @result.fail("Duplicate domain #{domain} used by #{count} apps") if count > 1 }

      @result
    end

    private

    def validate_app(name, meta, ports:, domains:)
      app_dir = File.join(ROOT, name)
      @result.fail("#{name}: declared in apps.yml but no directory #{app_dir}") unless File.directory?(app_dir)

      deploy_script = meta["deploy_script"]
      if deploy_script
        full_deploy = File.join(ROOT, "..", deploy_script)
        full_deploy2 = File.join(ROOT, deploy_script)
        @result.fail("#{name}: deploy_script '#{deploy_script}' does not exist") unless File.file?(full_deploy) || File.file?(full_deploy2)
      else
        @result.warn("#{name}: no deploy_script declared")
      end

      port = meta["port"]
      if port
        @result.fail("#{name}: port must be integer, got #{port.class}") unless port.is_a?(Integer)
        ports << port if port.is_a?(Integer)
      else
        @result.warn("#{name}: no port declared")
      end

      domain = meta["domain"]
      if domain
        domains << domain
      else
        @result.warn("#{name}: no domain declared")
      end

      (meta["features"] || {}).each_value do |section|
        next unless section.is_a?(Array)

        section.each do |feat|
          next unless feat.is_a?(Hash)

          status = feat["status"]
          next if VALID_STATUSES.include?(status.to_s)

          @result.fail("#{name}: feature '#{feat['name']}' has invalid status '#{status}' (expected done|planned)")
        end
      end
    end
  end
end
