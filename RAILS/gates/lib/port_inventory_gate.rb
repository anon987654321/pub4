# frozen_string_literal: true

require_relative "../../../OPENBSD/lib/deploy_inventory"
require_relative "../../../OPENBSD/lib/gate_result"

module Deploy
  class PortInventoryGate
    ROOT = File.expand_path("../../..", __dir__)
    MASTER_JSON = ENV.fetch("MASTER_JSON", File.join(ROOT, "OPENBSD", "master.json"))
    OPENBSD_DEPLOY = File.join(ROOT, "OPENBSD", "OPERATOR.sh")
    APPS_YML = File.join(ROOT, "RAILS", "apps.yml")
    RAILS_README = File.join(ROOT, "RAILS", "README.md")
    PWA_BUILDER = File.join(ROOT, "RAILS", "scripts", "build_workbox.mjs")
    RETIRED_ACTIVE_PATHS = [
      "OPENBSD/vps_console_install.exp",
      "OPENBSD/vps_console_poll_install.exp",
      "OPENBSD/usr/local/bin/relayd-watchdog",
      "RAILS/env.sample",
      "RAILS/scripts/build_workbox.mjs",
    ].freeze
    RETIRED_APP_NAMES = %w[baibl blognet].freeze

    def self.run
      new.run
    end

    def run
      inventory = Inventory.new(root: ROOT)
      apps = inventory.apps
      result = GateResult.new

      check_uniques(result, apps, :name)
      check_uniques(result, apps, :domain)
      check_uniques(result, apps, :port)
      check_ports(result, apps)
      check_master_json(result, apps)
      check_deploy_scripts(result, apps)
      check_openbsd_ports(result, apps)
      check_pwa_builder(result, apps)
      check_readmes(result, apps)
      check_retired_names_not_active(result)
      result
    end

    private

    def check_uniques(result, apps, field)
      apps.group_by { |app| app.public_send(field) }.each do |value, grouped|
        next if grouped.size == 1

        result.fail("#{field} collision #{value}: #{grouped.map(&:name).join(', ')}")
      end
    end

    def check_ports(result, apps)
      apps.each do |app|
        unless app.port.between?(1, 65_535)
          result.fail("#{app.name}: port #{app.port.inspect} must be between 1 and 65535")
        end
      end
    end

    def check_master_json(result, apps)
      unless File.file?(MASTER_JSON)
        result.fail("missing OPENBSD/master.json mirror: #{MASTER_JSON}")
        return
      end

      master = Inventory.new(root: ROOT).master_apps(path: MASTER_JSON)
      expected = apps.sort_by(&:name).map { |app| [app.name, app.domain, app.port] }
      actual = master.sort_by(&:name).map { |app| [app.name, app.domain, app.port] }
      result.fail("OPENBSD/master.json must mirror RAILS/apps.yml active apps") unless actual == expected
    end

    def check_deploy_scripts(result, apps)
      apps.each do |app|
        path = File.join(ROOT, app.deploy_script)
        unless File.file?(path)
          result.fail("#{app.name}: missing deploy script #{app.deploy_script}")
          next
        end

        text = File.read(path)
        {
          "APP_NAME=#{app.name}" => "APP_NAME",
          "APP_DOMAIN=#{app.domain}" => "APP_DOMAIN",
          "APP_PORT=#{app.port}" => "APP_PORT"
        }.each do |needle, label|
          result.fail("#{app.name}: deploy script #{label} must mirror apps.yml") unless text.include?(needle)
        end
      end
    end

    def openbsd_ports
      body = File.read(OPENBSD_DEPLOY)
      match = body.match(/typeset -A APP_PORTS=\(\n(?<ports>.*?)\n\)/m)
      return {} unless match

      match[:ports].lines.each_with_object({}) do |line, ports|
        entry = line.match(/\A\s*(?<name>[a-z0-9_]+)\s+(?<port>\d+)\s*(?:#.*)?\z/i)
        next unless entry

        ports[entry[:name]] = entry[:port].to_i
      end
    end

    def check_openbsd_ports(result, apps)
      unless File.file?(OPENBSD_DEPLOY)
        result.fail("missing OpenBSD deploy script: #{OPENBSD_DEPLOY}")
        return
      end

      ports = openbsd_ports
      result.fail("OPENBSD/OPERATOR.sh missing APP_PORTS map") if ports.empty?
      apps.each do |app|
        result.fail("#{app.name}: missing fixed OpenBSD APP_PORTS entry") unless ports.key?(app.name)
        next unless ports.key?(app.name) && ports.fetch(app.name) != app.port

        result.fail("#{app.name}: OpenBSD APP_PORTS #{ports.fetch(app.name)} must mirror apps.yml #{app.port}")
      end
    end

    def check_pwa_builder(result, apps)
      unless File.file?(PWA_BUILDER)
        result.fail("missing Workbox builder: #{PWA_BUILDER}")
        return
      end

      body = File.read(PWA_BUILDER)
      match = body.match(/const APPS = \[(?<apps>.*?)\]/)
      unless match
        result.fail("RAILS/scripts/build_workbox.mjs must expose const APPS")
        return
      end

      actual = match[:apps].scan(/"([^"]+)"/).flatten.sort
      expected = apps.map(&:name).sort
      result.fail("Workbox APPS must mirror RAILS/apps.yml active apps") unless actual == expected
    end

    def check_readmes(result, apps)
      root_readme = File.read(RAILS_README)
      result.fail("RAILS/README.md active app count must mirror apps.yml") unless root_readme.include?("#{apps.size} active production Rails")

      apps.each do |app|
        readme_path = File.join(ROOT, app.deploy_root, "README.md")
        unless File.file?(readme_path)
          result.fail("#{app.name}: missing README.md")
          next
        end

        readme = File.read(readme_path)
        result.fail("#{app.name}: README must point humans to apps.yml feature matrix") unless readme.include?("apps.yml")
        result.fail("#{app.name}: README deploy command must mirror apps.yml") unless readme.include?(app.deploy_script)
        result.fail("#{app.name}: README health check must mirror apps.yml port") unless readme.include?("127.0.0.1:#{app.port}/up")
      end
    end

    def check_retired_names_not_active(result)
      RETIRED_ACTIVE_PATHS.each do |relative|
        path = File.join(ROOT, relative)
        next unless File.file?(path)

        body = File.read(path)
        RETIRED_APP_NAMES.each do |name|
          result.fail("#{relative}: retired app #{name} must not appear in active deploy tooling") if body.match?(/\b#{Regexp.escape(name)}\b/)
        end
      end
    end
  end
end
